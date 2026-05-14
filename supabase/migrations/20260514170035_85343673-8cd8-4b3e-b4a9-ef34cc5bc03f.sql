
-- Generate / preserve a 6-char pickup_code on metadata when phase becomes 'arrived'
CREATE OR REPLACE FUNCTION public.ride_set_phase(p_ride_id uuid, p_phase text)
 RETURNS rides
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_ride public.rides;
  v_code text;
  v_meta jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF p_phase NOT IN ('approach','arrived','on_trip','at_destination') THEN
    RAISE EXCEPTION 'Invalid phase %', p_phase;
  END IF;
  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;
  IF v_ride.driver_id <> v_uid AND v_ride.client_id <> v_uid AND NOT public.has_role(v_uid,'admin') THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  v_meta := COALESCE(v_ride.metadata,'{}'::jsonb) || jsonb_build_object('phase', p_phase);

  IF p_phase = 'arrived' AND COALESCE(v_meta->>'pickup_code','') = '' THEN
    -- 6-char alphanumeric, exclude ambiguous chars
    v_code := upper(substr(translate(encode(gen_random_bytes(8),'base64'),'+/=OIl01',''),1,6));
    v_meta := v_meta || jsonb_build_object('pickup_code', v_code, 'arrived_at', to_jsonb(now()));
  END IF;

  UPDATE public.rides
     SET metadata = v_meta,
         updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;
  RETURN v_ride;
END; $function$;

-- Customer-driven pickup confirmation: validates code, then transitions to in_progress.
CREATE OR REPLACE FUNCTION public.ride_confirm_pickup(p_ride_id uuid, p_code text)
 RETURNS rides
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_ride public.rides;
  v_expected text;
  v_provided text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF p_code IS NULL OR length(trim(p_code)) = 0 THEN
    RAISE EXCEPTION 'Pickup code required';
  END IF;

  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;

  -- Customer or admin (driver cannot self-confirm pickup)
  IF v_ride.client_id <> v_uid AND NOT public.has_role(v_uid,'admin') THEN
    RAISE EXCEPTION 'Only the customer can confirm pickup';
  END IF;
  IF v_ride.driver_id IS NULL THEN
    RAISE EXCEPTION 'No driver assigned';
  END IF;
  IF v_ride.status <> 'pending' THEN
    RAISE EXCEPTION 'Ride is not awaiting pickup';
  END IF;
  IF COALESCE(v_ride.metadata->>'phase','') <> 'arrived' THEN
    RAISE EXCEPTION 'Driver has not arrived yet';
  END IF;

  v_expected := upper(COALESCE(v_ride.metadata->>'pickup_code',''));
  -- Accept either the bare code, or a QR payload like "CHOP-PICKUP-<code>"
  v_provided := upper(trim(p_code));
  IF v_provided LIKE 'CHOP-PICKUP-%' THEN
    v_provided := substr(v_provided, length('CHOP-PICKUP-') + 1);
  END IF;
  IF v_expected = '' OR v_provided <> v_expected THEN
    RAISE EXCEPTION 'Invalid pickup code';
  END IF;

  UPDATE public.rides
     SET status = 'in_progress',
         metadata = COALESCE(metadata,'{}'::jsonb) || jsonb_build_object(
           'phase','on_trip',
           'started_at', to_jsonb(now()),
           'pickup_confirmed_by','customer'
         ),
         updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;

  RETURN v_ride;
END; $function$;

GRANT EXECUTE ON FUNCTION public.ride_confirm_pickup(uuid, text) TO authenticated;
