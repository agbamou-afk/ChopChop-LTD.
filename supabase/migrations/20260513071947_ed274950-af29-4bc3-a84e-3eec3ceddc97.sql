
-- 1) PIN HASH: move to dedicated user_pins table, drop from profiles
CREATE TABLE IF NOT EXISTS public.user_pins (
  user_id uuid PRIMARY KEY,
  pin_hash text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.user_pins ENABLE ROW LEVEL SECURITY;

-- No SELECT policy for users (pin hash should never be readable by clients).
-- Owner can insert/update their own pin. Admins can manage all.
CREATE POLICY "Users insert own pin" ON public.user_pins
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users update own pin" ON public.user_pins
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Admins manage pins" ON public.user_pins
  FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin'))
  WITH CHECK (public.has_role(auth.uid(),'admin'));

-- Migrate any existing PIN hashes
INSERT INTO public.user_pins (user_id, pin_hash)
SELECT user_id, pin_hash FROM public.profiles WHERE pin_hash IS NOT NULL
ON CONFLICT (user_id) DO NOTHING;

-- Add a safe boolean to profiles to indicate PIN presence
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS has_pin boolean NOT NULL DEFAULT false;
UPDATE public.profiles SET has_pin = true WHERE pin_hash IS NOT NULL;
ALTER TABLE public.profiles DROP COLUMN IF EXISTS pin_hash;

-- Trigger to keep has_pin in sync
CREATE OR REPLACE FUNCTION public.sync_profile_has_pin()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    UPDATE public.profiles SET has_pin = false WHERE user_id = OLD.user_id;
    RETURN OLD;
  ELSE
    UPDATE public.profiles SET has_pin = true WHERE user_id = NEW.user_id;
    RETURN NEW;
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_user_pins_sync ON public.user_pins;
CREATE TRIGGER trg_user_pins_sync
AFTER INSERT OR UPDATE OR DELETE ON public.user_pins
FOR EACH ROW EXECUTE FUNCTION public.sync_profile_has_pin();

-- 2) AGENT PROFILES: drop overly broad SELECT; expose safe public view
DROP POLICY IF EXISTS "Anyone can view active agents" ON public.agent_profiles;

CREATE POLICY "Agents view own profile" ON public.agent_profiles
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE VIEW public.public_agents
WITH (security_invoker = true) AS
SELECT id, user_id, business_name, location, latitude, longitude, status
FROM public.agent_profiles
WHERE status = 'active';

GRANT SELECT ON public.public_agents TO anon, authenticated;

-- 3) TOPUP confirmation_code: hide from agent SELECT
DROP POLICY IF EXISTS "Agent views own topups" ON public.topup_requests;

CREATE OR REPLACE VIEW public.agent_topup_requests
WITH (security_invoker = true) AS
SELECT id, reference, client_user_id, agent_user_id, amount_gnf, status,
       expires_at, confirmed_at, cancelled_reason, transaction_id,
       created_at, updated_at
FROM public.topup_requests
WHERE agent_user_id = auth.uid();

GRANT SELECT ON public.agent_topup_requests TO authenticated;

-- 4) REALTIME: add baseline RLS on realtime.messages restricting subscription topics
-- Allow authenticated users to receive realtime broadcast/presence only on topics
-- they own (topic must equal their auth.uid()) or postgres_changes (no topic set by client).
ALTER TABLE IF EXISTS realtime.messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated can read own topic messages" ON realtime.messages;
CREATE POLICY "Authenticated can read own topic messages"
ON realtime.messages FOR SELECT TO authenticated
USING (
  (realtime.topic() IS NULL)
  OR (realtime.topic() = auth.uid()::text)
  OR (realtime.topic() LIKE 'public:%')
);

DROP POLICY IF EXISTS "Authenticated can write own topic messages" ON realtime.messages;
CREATE POLICY "Authenticated can write own topic messages"
ON realtime.messages FOR INSERT TO authenticated
WITH CHECK (
  (realtime.topic() = auth.uid()::text)
  OR (realtime.topic() LIKE 'public:%')
);

-- 5) SECURITY DEFINER functions: revoke EXECUTE from PUBLIC and anon
REVOKE EXECUTE ON FUNCTION public.claim_first_admin() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, app_role) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.find_user_by_phone(text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.wallet_topup_create(uuid, bigint) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.wallet_topup_confirm(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.wallet_topup_cancel(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.wallet_hold(bigint, text, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.wallet_release(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.wallet_capture(uuid, uuid, party_type, bigint, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.wallet_internal_transfer(uuid, text, uuid, text, bigint, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.ride_create(ride_mode, numeric, numeric, numeric, numeric, bigint, uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.ride_accept(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.ride_complete(uuid, bigint, integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.ride_cancel(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_create_agent(text, text, text, bigint, numeric) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_adjust_agent_float(uuid, bigint, text) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.claim_first_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, app_role) TO authenticated;
GRANT EXECUTE ON FUNCTION public.find_user_by_phone(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.wallet_topup_create(uuid, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.wallet_topup_confirm(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.wallet_topup_cancel(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.wallet_hold(bigint, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.wallet_release(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.wallet_capture(uuid, uuid, party_type, bigint, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ride_create(ride_mode, numeric, numeric, numeric, numeric, bigint, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ride_accept(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ride_complete(uuid, bigint, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ride_cancel(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_agent(text, text, text, bigint, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_adjust_agent_float(uuid, bigint, text) TO authenticated;
