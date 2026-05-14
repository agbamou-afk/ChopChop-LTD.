-- Auto-dispatch a ride to the nearest online driver matching its mode.
-- Without this, ride_create() inserts a pending ride but no driver ever
-- sees it because nothing populates ride_offers. This closes the loop so
-- the full Moto lifecycle works end-to-end without manual DB intervention.

CREATE OR REPLACE FUNCTION public.ride_dispatch(p_ride_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ride       public.rides;
  v_vehicle    public.driver_vehicle_type;
  v_driver     uuid;
  v_offer_id   uuid;
  v_dist_m     integer;
BEGIN
  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id;
  IF v_ride.id IS NULL OR v_ride.status <> 'pending' OR v_ride.driver_id IS NOT NULL THEN
    RETURN NULL;
  END IF;

  -- Map ride mode -> vehicle type. Fall back to 'moto' for unknown modes.
  v_vehicle := CASE v_ride.mode::text
                 WHEN 'moto'    THEN 'moto'::public.driver_vehicle_type
                 WHEN 'toktok'  THEN 'toktok'::public.driver_vehicle_type
                 ELSE 'moto'::public.driver_vehicle_type
               END;

  -- Pick the nearest online, approved driver of the right vehicle type
  -- that currently has no active offer for this ride.
  SELECT dl.user_id,
         (6371000 * acos(
            greatest(-1, least(1,
              cos(radians(v_ride.pickup_lat)) * cos(radians(dl.lat)) *
              cos(radians(dl.lng) - radians(v_ride.pickup_lng)) +
              sin(radians(v_ride.pickup_lat)) * sin(radians(dl.lat))
            ))
          ))::integer
    INTO v_driver, v_dist_m
    FROM public.driver_locations dl
    JOIN public.driver_profiles  dp ON dp.user_id = dl.user_id
   WHERE dp.status = 'approved'
     AND dp.vehicle_type = v_vehicle
     AND dp.presence = 'online'
     AND dl.status = 'online'
     AND NOT EXISTS (
       SELECT 1 FROM public.ride_offers o
        WHERE o.ride_id = p_ride_id AND o.driver_id = dl.user_id
     )
   ORDER BY 2 ASC
   LIMIT 1;

  IF v_driver IS NULL THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.ride_offers (
    ride_id, driver_id, status, sent_at, expires_at,
    distance_to_pickup_m, estimated_fare_gnf, estimated_earning_gnf
  ) VALUES (
    p_ride_id, v_driver, 'pending', now(), now() + interval '30 seconds',
    v_dist_m, v_ride.fare_gnf, (v_ride.fare_gnf * 85) / 100
  ) RETURNING id INTO v_offer_id;

  RETURN v_offer_id;
END;
$$;

-- Trigger: dispatch on every new pending ride.
CREATE OR REPLACE FUNCTION public.rides_after_insert_dispatch()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.status = 'pending' AND NEW.driver_id IS NULL THEN
    PERFORM public.ride_dispatch(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_rides_after_insert_dispatch ON public.rides;
CREATE TRIGGER trg_rides_after_insert_dispatch
AFTER INSERT ON public.rides
FOR EACH ROW EXECUTE FUNCTION public.rides_after_insert_dispatch();

-- Re-dispatch when a driver declines, so the next-nearest driver gets a
-- chance instead of the ride hanging forever.
CREATE OR REPLACE FUNCTION public.ride_offers_after_update_redispatch()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ride public.rides;
BEGIN
  IF NEW.status IN ('declined', 'expired') AND OLD.status <> NEW.status THEN
    SELECT * INTO v_ride FROM public.rides WHERE id = NEW.ride_id;
    IF v_ride.id IS NOT NULL AND v_ride.status = 'pending' AND v_ride.driver_id IS NULL THEN
      PERFORM public.ride_dispatch(NEW.ride_id);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ride_offers_after_update_redispatch ON public.ride_offers;
CREATE TRIGGER trg_ride_offers_after_update_redispatch
AFTER UPDATE ON public.ride_offers
FOR EACH ROW EXECUTE FUNCTION public.ride_offers_after_update_redispatch();