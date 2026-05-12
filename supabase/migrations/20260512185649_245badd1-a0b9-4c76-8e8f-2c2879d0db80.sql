-- Hold funds on caller's client wallet
CREATE OR REPLACE FUNCTION public.wallet_hold(
  p_amount_gnf bigint,
  p_reference text DEFAULT NULL,
  p_description text DEFAULT NULL
) RETURNS public.wallet_transactions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_wallet public.wallets;
  v_txn public.wallet_transactions;
  v_ref text;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF p_amount_gnf <= 0 THEN RAISE EXCEPTION 'Invalid amount'; END IF;

  SELECT * INTO v_wallet FROM public.wallets
   WHERE owner_user_id = v_caller AND party_type = 'client' FOR UPDATE;
  IF v_wallet.id IS NULL THEN RAISE EXCEPTION 'Wallet not found'; END IF;
  IF (v_wallet.balance_gnf - v_wallet.held_gnf) < p_amount_gnf THEN
    RAISE EXCEPTION 'Insufficient balance';
  END IF;

  UPDATE public.wallets SET held_gnf = held_gnf + p_amount_gnf WHERE id = v_wallet.id;

  v_ref := coalesce(p_reference, 'CC-HD-' || upper(substring(replace(gen_random_uuid()::text,'-',''),1,10)));

  INSERT INTO public.wallet_transactions (
    reference, type, status, amount_gnf,
    from_wallet_id, related_user_id, related_entity, description
  ) VALUES (
    v_ref, 'hold', 'pending', p_amount_gnf,
    v_wallet.id, v_caller, 'wallet:hold', coalesce(p_description, 'Réservation de fonds')
  ) RETURNING * INTO v_txn;

  RETURN v_txn;
END $$;

-- Release a hold (cancel booking)
CREATE OR REPLACE FUNCTION public.wallet_release(
  p_hold_id uuid,
  p_reason text DEFAULT NULL
) RETURNS public.wallet_transactions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_hold public.wallet_transactions;
  v_wallet public.wallets;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_hold FROM public.wallet_transactions
   WHERE id = p_hold_id FOR UPDATE;
  IF v_hold.id IS NULL THEN RAISE EXCEPTION 'Hold not found'; END IF;
  IF v_hold.type <> 'hold' OR v_hold.status <> 'pending' THEN
    RAISE EXCEPTION 'Hold is not active';
  END IF;
  IF v_hold.related_user_id <> v_caller AND NOT public.has_role(v_caller, 'admin') THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT * INTO v_wallet FROM public.wallets WHERE id = v_hold.from_wallet_id FOR UPDATE;
  UPDATE public.wallets SET held_gnf = greatest(held_gnf - v_hold.amount_gnf, 0)
   WHERE id = v_wallet.id;

  UPDATE public.wallet_transactions
     SET status = 'cancelled', completed_at = now(),
         description = coalesce(p_reason, description)
   WHERE id = v_hold.id
   RETURNING * INTO v_hold;

  RETURN v_hold;
END $$;

-- Capture a hold and pay the recipient (driver/merchant/master)
CREATE OR REPLACE FUNCTION public.wallet_capture(
  p_hold_id uuid,
  p_to_user_id uuid DEFAULT NULL,
  p_to_party_type public.party_type DEFAULT 'master',
  p_actual_amount_gnf bigint DEFAULT NULL,
  p_description text DEFAULT NULL
) RETURNS public.wallet_transactions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_hold public.wallet_transactions;
  v_client_wallet public.wallets;
  v_to_wallet public.wallets;
  v_amount bigint;
  v_pay_txn public.wallet_transactions;
  v_ref text;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_hold FROM public.wallet_transactions
   WHERE id = p_hold_id FOR UPDATE;
  IF v_hold.id IS NULL THEN RAISE EXCEPTION 'Hold not found'; END IF;
  IF v_hold.type <> 'hold' OR v_hold.status <> 'pending' THEN
    RAISE EXCEPTION 'Hold is not active';
  END IF;
  IF v_hold.related_user_id <> v_caller AND NOT public.has_role(v_caller, 'admin') THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  v_amount := coalesce(p_actual_amount_gnf, v_hold.amount_gnf);
  IF v_amount <= 0 THEN RAISE EXCEPTION 'Invalid amount'; END IF;
  IF v_amount > v_hold.amount_gnf THEN
    RAISE EXCEPTION 'Captured amount exceeds hold';
  END IF;

  SELECT * INTO v_client_wallet FROM public.wallets WHERE id = v_hold.from_wallet_id FOR UPDATE;

  IF p_to_party_type = 'master' OR p_to_user_id IS NULL THEN
    SELECT * INTO v_to_wallet FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;
  ELSE
    SELECT * INTO v_to_wallet FROM public.wallets
     WHERE owner_user_id = p_to_user_id AND party_type = p_to_party_type FOR UPDATE;
    IF v_to_wallet.id IS NULL THEN
      INSERT INTO public.wallets (owner_user_id, party_type)
      VALUES (p_to_user_id, p_to_party_type)
      RETURNING * INTO v_to_wallet;
    END IF;
  END IF;
  IF v_to_wallet.id IS NULL THEN RAISE EXCEPTION 'Recipient wallet not found'; END IF;

  -- Release the full hold, then move actual amount
  UPDATE public.wallets
     SET held_gnf = greatest(held_gnf - v_hold.amount_gnf, 0),
         balance_gnf = balance_gnf - v_amount
   WHERE id = v_client_wallet.id;
  UPDATE public.wallets SET balance_gnf = balance_gnf + v_amount WHERE id = v_to_wallet.id;

  v_ref := 'CC-PY-' || upper(substring(replace(gen_random_uuid()::text,'-',''),1,10));

  INSERT INTO public.wallet_transactions (
    reference, type, status, amount_gnf,
    from_wallet_id, to_wallet_id, related_user_id, related_entity,
    description, completed_at, metadata
  ) VALUES (
    v_ref, 'payment', 'completed', v_amount,
    v_client_wallet.id, v_to_wallet.id, v_caller, 'capture:' || v_hold.id,
    coalesce(p_description, 'Paiement CHOP CHOP'), now(),
    jsonb_build_object('hold_id', v_hold.id, 'hold_amount_gnf', v_hold.amount_gnf)
  ) RETURNING * INTO v_pay_txn;

  UPDATE public.wallet_transactions
     SET status = 'completed', completed_at = now(),
         metadata = metadata || jsonb_build_object('captured_txn_id', v_pay_txn.id, 'captured_amount_gnf', v_amount)
   WHERE id = v_hold.id;

  RETURN v_pay_txn;
END $$;