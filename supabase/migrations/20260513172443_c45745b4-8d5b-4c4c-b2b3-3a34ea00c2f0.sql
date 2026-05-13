
-- 1) Allow agent_user_id to be null (Orange Money flow has no agent)
ALTER TABLE public.topup_requests ALTER COLUMN agent_user_id DROP NOT NULL;

-- 2) Extend topup_requests with provider + matching fields
ALTER TABLE public.topup_requests
  ADD COLUMN IF NOT EXISTS provider text NOT NULL DEFAULT 'agent',
  ADD COLUMN IF NOT EXISTS user_phone text,
  ADD COLUMN IF NOT EXISTS matched_provider_transaction_id text,
  ADD COLUMN IF NOT EXISTS notes text;

ALTER TABLE public.topup_requests
  ADD CONSTRAINT topup_requests_provider_chk
  CHECK (provider IN ('agent','orange_money'));

-- 3) Extend topup_status enum
ALTER TYPE public.topup_status ADD VALUE IF NOT EXISTS 'matched';
ALTER TYPE public.topup_status ADD VALUE IF NOT EXISTS 'needs_review';
ALTER TYPE public.topup_status ADD VALUE IF NOT EXISTS 'credited';
ALTER TYPE public.topup_status ADD VALUE IF NOT EXISTS 'failed';

-- 4) Reference sequence + generator
CREATE SEQUENCE IF NOT EXISTS public.topup_reference_seq START 1;

CREATE OR REPLACE FUNCTION public.gen_topup_reference()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_year int := EXTRACT(YEAR FROM now())::int;
  v_n bigint := nextval('public.topup_reference_seq');
BEGIN
  RETURN 'CC-TOPUP-' || v_year::text || '-' || lpad(v_n::text, 6, '0');
END;
$$;

-- 5) payment_provider_events table
CREATE TABLE IF NOT EXISTS public.payment_provider_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL,
  event_type text NOT NULL DEFAULT 'payment.received',
  provider_transaction_id text NOT NULL,
  payer_phone text,
  amount_gnf bigint NOT NULL,
  currency text NOT NULL DEFAULT 'GNF',
  status text NOT NULL DEFAULT 'successful',
  raw_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  matched_user_id uuid,
  matched_topup_request_id uuid,
  match_confidence numeric,
  processing_status text NOT NULL DEFAULT 'received',
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  CONSTRAINT payment_provider_events_unique_tx UNIQUE (provider, provider_transaction_id),
  CONSTRAINT payment_provider_events_processing_chk
    CHECK (processing_status IN ('received','matched','credited','needs_review','rejected','duplicate'))
);

CREATE INDEX IF NOT EXISTS idx_ppe_processing ON public.payment_provider_events (processing_status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ppe_payer_phone ON public.payment_provider_events (payer_phone);
CREATE INDEX IF NOT EXISTS idx_ppe_amount_time ON public.payment_provider_events (amount_gnf, created_at DESC);

ALTER TABLE public.payment_provider_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins read provider events"
  ON public.payment_provider_events
  FOR SELECT TO authenticated
  USING (public.is_any_admin(auth.uid()));

CREATE POLICY "Admins update provider events"
  ON public.payment_provider_events
  FOR UPDATE TO authenticated
  USING (public.is_any_admin(auth.uid()))
  WITH CHECK (public.is_any_admin(auth.uid()));

-- INSERTs are only via SECURITY DEFINER functions / service_role (no policy = denied for normal users).

-- 6) RPC: user creates an Orange Money top-up request
CREATE OR REPLACE FUNCTION public.wallet_topup_om_create(p_amount_gnf bigint)
RETURNS public.topup_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_wallet public.wallets;
  v_phone text;
  v_ref text;
  v_row public.topup_requests;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF p_amount_gnf <= 0 THEN RAISE EXCEPTION 'Invalid amount'; END IF;
  IF p_amount_gnf < 1000 THEN RAISE EXCEPTION 'Minimum top-up is 1000 GNF'; END IF;
  IF p_amount_gnf > 50000000 THEN RAISE EXCEPTION 'Maximum top-up is 50,000,000 GNF'; END IF;

  SELECT * INTO v_wallet FROM public.wallets
   WHERE owner_user_id = v_uid AND party_type = 'client'
   LIMIT 1;
  IF v_wallet.id IS NULL THEN
    RAISE EXCEPTION 'Wallet not found';
  END IF;
  IF v_wallet.status <> 'active' THEN
    RAISE EXCEPTION 'Wallet is not active';
  END IF;

  SELECT phone INTO v_phone FROM public.profiles WHERE user_id = v_uid LIMIT 1;

  v_ref := public.gen_topup_reference();

  INSERT INTO public.topup_requests (
    reference, client_user_id, agent_user_id, amount_gnf,
    confirmation_code, provider, user_phone, status, expires_at
  ) VALUES (
    v_ref, v_uid, NULL, p_amount_gnf,
    '------', 'orange_money', v_phone, 'pending'::topup_status, now() + interval '24 hours'
  ) RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.wallet_topup_om_create(bigint) FROM public;
GRANT EXECUTE ON FUNCTION public.wallet_topup_om_create(bigint) TO authenticated;

-- 7) RPC: credit wallet after a provider event is matched (called by edge fn / admins)
CREATE OR REPLACE FUNCTION public.wallet_topup_om_credit(
  p_event_id uuid,
  p_topup_request_id uuid
)
RETURNS public.wallet_transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_caller_is_admin boolean := false;
  v_event public.payment_provider_events;
  v_topup public.topup_requests;
  v_client_wallet public.wallets;
  v_master public.wallets;
  v_tx public.wallet_transactions;
  v_ref text;
BEGIN
  -- Allow service_role (no auth.uid()) OR finance_admin / god_admin
  IF v_caller IS NOT NULL THEN
    v_caller_is_admin :=
      public.has_app_role(v_caller, 'god_admin')
      OR public.has_app_role(v_caller, 'finance_admin')
      OR public.has_role(v_caller, 'admin'::public.app_role);
    IF NOT v_caller_is_admin THEN
      RAISE EXCEPTION 'Not authorized';
    END IF;
  END IF;

  SELECT * INTO v_event FROM public.payment_provider_events WHERE id = p_event_id FOR UPDATE;
  IF v_event.id IS NULL THEN RAISE EXCEPTION 'Provider event not found'; END IF;
  IF v_event.processing_status = 'credited' THEN RAISE EXCEPTION 'Event already credited'; END IF;
  IF v_event.status <> 'successful' THEN RAISE EXCEPTION 'Provider payment not successful'; END IF;

  SELECT * INTO v_topup FROM public.topup_requests WHERE id = p_topup_request_id FOR UPDATE;
  IF v_topup.id IS NULL THEN RAISE EXCEPTION 'Top-up request not found'; END IF;
  IF v_topup.status::text NOT IN ('pending','matched','needs_review') THEN
    RAISE EXCEPTION 'Top-up request is not eligible (status=%)', v_topup.status;
  END IF;
  IF v_topup.amount_gnf <> v_event.amount_gnf THEN
    RAISE EXCEPTION 'Amount mismatch';
  END IF;

  SELECT * INTO v_client_wallet FROM public.wallets
    WHERE owner_user_id = v_topup.client_user_id AND party_type = 'client' FOR UPDATE;
  IF v_client_wallet.id IS NULL THEN RAISE EXCEPTION 'Client wallet not found'; END IF;
  IF v_client_wallet.status <> 'active' THEN RAISE EXCEPTION 'Wallet is not active'; END IF;

  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;
  IF v_master.id IS NULL THEN RAISE EXCEPTION 'Master wallet not found'; END IF;

  -- Move funds: master -> client
  UPDATE public.wallets SET balance_gnf = balance_gnf + v_event.amount_gnf WHERE id = v_client_wallet.id;
  -- Master may go negative; that's OK, daily reconciliation matches against OM merchant balance.
  UPDATE public.wallets SET balance_gnf = balance_gnf - v_event.amount_gnf WHERE id = v_master.id;

  v_ref := 'CC-OM-' || upper(substring(replace(gen_random_uuid()::text,'-',''),1,10));

  INSERT INTO public.wallet_transactions (
    reference, type, status, amount_gnf,
    from_wallet_id, to_wallet_id, related_user_id, related_entity,
    description, completed_at, metadata
  ) VALUES (
    v_ref, 'topup', 'completed', v_event.amount_gnf,
    v_master.id, v_client_wallet.id, v_topup.client_user_id,
    'orange_money:' || v_event.provider_transaction_id,
    'Recharge Orange Money ' || v_topup.reference, now(),
    jsonb_build_object(
      'event_id', v_event.id,
      'topup_request_id', v_topup.id,
      'provider_transaction_id', v_event.provider_transaction_id,
      'payer_phone', v_event.payer_phone
    )
  ) RETURNING * INTO v_tx;

  UPDATE public.topup_requests
    SET status = 'credited'::topup_status,
        confirmed_at = now(),
        transaction_id = v_tx.id,
        matched_provider_transaction_id = v_event.provider_transaction_id
    WHERE id = v_topup.id;

  UPDATE public.payment_provider_events
    SET processing_status = 'credited',
        matched_user_id = v_topup.client_user_id,
        matched_topup_request_id = v_topup.id,
        processed_at = now()
    WHERE id = v_event.id;

  -- Audit
  INSERT INTO public.audit_logs (actor_user_id, actor_role, module, action, target_type, target_id, after, note)
  VALUES (
    v_caller, public.current_admin_role(v_caller),
    'wallet', 'wallet.topup.credit', 'wallet_transaction', v_tx.id::text,
    jsonb_build_object('amount_gnf', v_event.amount_gnf, 'reference', v_topup.reference),
    'Orange Money top-up credited'
  );

  RETURN v_tx;
END;
$$;

REVOKE ALL ON FUNCTION public.wallet_topup_om_credit(uuid, uuid) FROM public;
-- Service role can call without grant. Authenticated callers must be admins (enforced inside).
GRANT EXECUTE ON FUNCTION public.wallet_topup_om_credit(uuid, uuid) TO authenticated;

-- 8) RPC: admin manual wallet credit (god_admin / finance_admin only)
CREATE OR REPLACE FUNCTION public.wallet_admin_credit(
  p_user_id uuid,
  p_amount_gnf bigint,
  p_reason text,
  p_provider_tx_id text DEFAULT NULL
)
RETURNS public.wallet_transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_client_wallet public.wallets;
  v_master public.wallets;
  v_tx public.wallet_transactions;
  v_ref text;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT (public.has_app_role(v_caller, 'god_admin') OR public.has_app_role(v_caller, 'finance_admin')) THEN
    RAISE EXCEPTION 'Only finance or god admins can credit wallets';
  END IF;
  IF p_amount_gnf <= 0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;
  IF coalesce(trim(p_reason),'') = '' THEN RAISE EXCEPTION 'Reason is required'; END IF;

  SELECT * INTO v_client_wallet FROM public.wallets
    WHERE owner_user_id = p_user_id AND party_type = 'client' FOR UPDATE;
  IF v_client_wallet.id IS NULL THEN RAISE EXCEPTION 'Client wallet not found'; END IF;

  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;
  IF v_master.id IS NULL THEN RAISE EXCEPTION 'Master wallet not found'; END IF;

  UPDATE public.wallets SET balance_gnf = balance_gnf + p_amount_gnf WHERE id = v_client_wallet.id;
  UPDATE public.wallets SET balance_gnf = balance_gnf - p_amount_gnf WHERE id = v_master.id;

  v_ref := 'CC-MA-' || upper(substring(replace(gen_random_uuid()::text,'-',''),1,10));

  INSERT INTO public.wallet_transactions (
    reference, type, status, amount_gnf,
    from_wallet_id, to_wallet_id, related_user_id, related_entity,
    description, completed_at, metadata
  ) VALUES (
    v_ref, 'adjustment', 'completed', p_amount_gnf,
    v_master.id, v_client_wallet.id, p_user_id,
    'admin_credit',
    p_reason, now(),
    jsonb_build_object(
      'admin_user_id', v_caller,
      'provider_transaction_id', p_provider_tx_id
    )
  ) RETURNING * INTO v_tx;

  INSERT INTO public.audit_logs (actor_user_id, actor_role, module, action, target_type, target_id, after, note)
  VALUES (
    v_caller, public.current_admin_role(v_caller),
    'wallet', 'wallet.admin.credit', 'wallet_transaction', v_tx.id::text,
    jsonb_build_object('amount_gnf', p_amount_gnf, 'user_id', p_user_id, 'provider_tx_id', p_provider_tx_id),
    p_reason
  );

  RETURN v_tx;
END;
$$;

REVOKE ALL ON FUNCTION public.wallet_admin_credit(uuid, bigint, text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.wallet_admin_credit(uuid, bigint, text, text) TO authenticated;
