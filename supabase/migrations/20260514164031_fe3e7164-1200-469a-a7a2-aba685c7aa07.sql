CREATE OR REPLACE FUNCTION public.ride_complete(p_ride_id uuid, p_actual_fare_gnf bigint DEFAULT NULL::bigint, p_commission_bps integer DEFAULT 1500)
 RETURNS rides
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_ride public.rides;
  v_fare BIGINT;
  v_platform BIGINT;
  v_driver_earn BIGINT;
  v_payment public.wallet_transactions;
  v_commission public.wallet_transactions;
  v_to_party TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;
  IF v_ride.client_id <> v_uid AND v_ride.driver_id <> v_uid AND NOT public.has_role(v_uid, 'admin') THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_ride.status = 'completed' THEN RETURN v_ride; END IF;
  IF v_ride.status = 'cancelled' THEN RAISE EXCEPTION 'Ride already cancelled'; END IF;

  v_fare := COALESCE(p_actual_fare_gnf, v_ride.fare_gnf);
  v_platform := (v_fare * p_commission_bps) / 10000;
  v_driver_earn := v_fare - v_platform;

  IF v_ride.driver_id IS NOT NULL THEN
    v_to_party := 'driver';
  ELSE
    v_to_party := 'master';
  END IF;

  SELECT * INTO v_payment FROM public.wallet_capture(
    p_hold_id := v_ride.hold_tx_id,
    p_to_user_id := v_ride.driver_id,
    p_to_party_type := v_to_party::party_type,
    p_actual_amount_gnf := v_fare,
    p_description := 'Course ' || v_ride.mode::text
  );

  IF v_ride.driver_id IS NOT NULL AND v_platform > 0 THEN
    SELECT * INTO v_commission FROM public.wallet_internal_transfer(
      p_from_user_id := v_ride.driver_id,
      p_from_party_type := 'driver',
      p_to_user_id := NULL,
      p_to_party_type := 'master',
      p_amount_gnf := v_platform,
      p_description := 'Commission course ' || v_ride.id::text
    );
  END IF;

  UPDATE public.rides SET
    status = 'completed',
    fare_gnf = v_fare,
    platform_fee_gnf = v_platform,
    driver_earning_gnf = v_driver_earn,
    payment_tx_id = v_payment.id,
    completed_at = now()
  WHERE id = p_ride_id
  RETURNING * INTO v_ride;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (
    v_uid, 'wallet', 'ride.payment_captured', 'ride', v_ride.id::text,
    jsonb_build_object(
      'ride_id', v_ride.id,
      'fare_gnf', v_fare,
      'driver_earning_gnf', v_driver_earn,
      'platform_fee_gnf', v_platform,
      'payment_tx_id', v_payment.id,
      'client_id', v_ride.client_id,
      'driver_id', v_ride.driver_id
    ),
    'Capture wallet pour course ' || v_ride.mode::text
  );

  IF v_commission.id IS NOT NULL THEN
    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
    VALUES (
      v_uid, 'wallet', 'ride.commission_collected', 'ride', v_ride.id::text,
      jsonb_build_object(
        'ride_id', v_ride.id,
        'amount_gnf', v_platform,
        'commission_tx_id', v_commission.id,
        'driver_id', v_ride.driver_id
      ),
      'Commission CHOP CHOP'
    );
  END IF;

  RETURN v_ride;
END $function$;

CREATE OR REPLACE FUNCTION public.ride_integrity_check(p_ride_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ride public.rides;
  v_pay public.wallet_transactions;
  v_commission_count int;
  v_commission_total bigint;
  v_capture_count int;
  v_audit_count int;
  v_client_wallet public.wallets;
  v_driver_wallet public.wallets;
  v_master_wallet public.wallets;
  v_checks jsonb := '[]'::jsonb;
  v_ok boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id;
  IF v_ride.id IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;
  IF v_ride.client_id <> v_uid AND v_ride.driver_id <> v_uid AND NOT public.has_role(v_uid, 'admin') THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_ride.status <> 'completed' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ride_not_completed', 'status', v_ride.status);
  END IF;

  SELECT * INTO v_pay FROM public.wallet_transactions WHERE id = v_ride.payment_tx_id;

  SELECT count(*) INTO v_capture_count
    FROM public.wallet_transactions
   WHERE related_entity = 'capture:' || v_ride.hold_tx_id::text
     AND type = 'payment' AND status = 'completed';

  SELECT count(*), coalesce(sum(amount_gnf),0) INTO v_commission_count, v_commission_total
    FROM public.wallet_transactions
   WHERE type = 'transfer' AND status = 'completed'
     AND description = 'Commission course ' || v_ride.id::text;

  SELECT count(*) INTO v_audit_count
    FROM public.audit_logs
   WHERE module = 'wallet' AND target_id = v_ride.id::text;

  SELECT * INTO v_client_wallet FROM public.wallets
   WHERE owner_user_id = v_ride.client_id AND party_type = 'client' LIMIT 1;
  IF v_ride.driver_id IS NOT NULL THEN
    SELECT * INTO v_driver_wallet FROM public.wallets
     WHERE owner_user_id = v_ride.driver_id AND party_type = 'driver' LIMIT 1;
  END IF;
  SELECT * INTO v_master_wallet FROM public.wallets WHERE party_type = 'master' LIMIT 1;

  v_checks := v_checks || jsonb_build_object(
    'name','customer_debited',
    'ok', v_pay.id IS NOT NULL AND v_pay.amount_gnf = v_ride.fare_gnf,
    'expected_gnf', v_ride.fare_gnf,
    'observed_gnf', v_pay.amount_gnf
  );
  v_checks := v_checks || jsonb_build_object(
    'name','driver_credited_net',
    'ok', v_ride.driver_id IS NULL
       OR (coalesce(v_pay.amount_gnf,0) - v_commission_total) = v_ride.driver_earning_gnf,
    'expected_gnf', v_ride.driver_earning_gnf,
    'observed_gnf', coalesce(v_pay.amount_gnf,0) - v_commission_total
  );
  v_checks := v_checks || jsonb_build_object(
    'name','commission_recorded',
    'ok', v_ride.platform_fee_gnf = v_commission_total OR v_ride.driver_id IS NULL,
    'expected_gnf', v_ride.platform_fee_gnf,
    'observed_gnf', v_commission_total
  );
  v_checks := v_checks || jsonb_build_object(
    'name','no_duplicate_capture',
    'ok', v_capture_count = 1,
    'capture_count', v_capture_count
  );
  v_checks := v_checks || jsonb_build_object(
    'name','single_commission_entry',
    'ok', (v_ride.driver_id IS NULL AND v_commission_count = 0)
       OR (v_ride.platform_fee_gnf = 0 AND v_commission_count = 0)
       OR v_commission_count = 1,
    'commission_count', v_commission_count
  );
  v_checks := v_checks || jsonb_build_object(
    'name','audit_logs_present',
    'ok', v_audit_count >= 1,
    'audit_count', v_audit_count
  );

  SELECT bool_and((c->>'ok')::boolean) INTO v_ok FROM jsonb_array_elements(v_checks) c;

  RETURN jsonb_build_object(
    'ok', v_ok,
    'ride_id', v_ride.id,
    'mode', v_ride.mode,
    'fare_gnf', v_ride.fare_gnf,
    'driver_earning_gnf', v_ride.driver_earning_gnf,
    'platform_fee_gnf', v_ride.platform_fee_gnf,
    'completed_at', v_ride.completed_at,
    'wallets', jsonb_build_object(
      'client_balance_gnf', v_client_wallet.balance_gnf,
      'driver_balance_gnf', v_driver_wallet.balance_gnf,
      'master_balance_gnf', v_master_wallet.balance_gnf
    ),
    'checks', v_checks
  );
END $$;

GRANT EXECUTE ON FUNCTION public.ride_integrity_check(uuid) TO authenticated;