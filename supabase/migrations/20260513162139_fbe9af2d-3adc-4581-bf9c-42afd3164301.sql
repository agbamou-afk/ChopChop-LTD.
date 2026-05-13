-- =========================================================
-- ANALYTICS EVENTS
-- =========================================================
CREATE TABLE public.analytics_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NULL,
  anonymous_session_id text NULL,
  event_type text NOT NULL,
  event_category text NOT NULL,
  event_name text NOT NULL,
  route text NULL,
  service_area text NULL,
  device_type text NULL,
  app_version text NULL,
  os text NULL,
  language text NULL,
  zone_country text NULL,
  zone_city text NULL,
  zone_commune text NULL,
  zone_neighborhood text NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_analytics_events_created_at ON public.analytics_events (created_at DESC);
CREATE INDEX idx_analytics_events_user_id ON public.analytics_events (user_id) WHERE user_id IS NOT NULL;
CREATE INDEX idx_analytics_events_event_name ON public.analytics_events (event_name);
CREATE INDEX idx_analytics_events_event_category ON public.analytics_events (event_category);
CREATE INDEX idx_analytics_events_session ON public.analytics_events (anonymous_session_id) WHERE anonymous_session_id IS NOT NULL;

ALTER TABLE public.analytics_events ENABLE ROW LEVEL SECURITY;

-- Anyone (anon or authenticated) can write events, but only their own user_id.
-- Anonymous events must have NULL user_id.
CREATE POLICY "Insert own analytics events"
ON public.analytics_events FOR INSERT
TO anon, authenticated
WITH CHECK (
  (auth.uid() IS NULL AND user_id IS NULL)
  OR (auth.uid() IS NOT NULL AND user_id = auth.uid())
);

CREATE POLICY "Users read own analytics events"
ON public.analytics_events FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Admins read all analytics events"
ON public.analytics_events FOR SELECT
TO authenticated
USING (public.is_any_admin(auth.uid()));

-- =========================================================
-- USER CONSENT
-- =========================================================
CREATE TABLE public.user_consent (
  user_id uuid PRIMARY KEY,
  basic_analytics boolean NOT NULL DEFAULT true,
  personalization boolean NOT NULL DEFAULT true,
  location_improvements boolean NOT NULL DEFAULT false,
  marketing_analytics boolean NOT NULL DEFAULT false,
  -- security_fraud is always true: kept here for transparency only
  security_fraud boolean NOT NULL DEFAULT true,
  consent_version int NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_consent ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own consent"
ON public.user_consent FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users insert own consent"
ON public.user_consent FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users update own consent"
ON public.user_consent FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id AND security_fraud = true);

CREATE POLICY "Admins read all consent"
ON public.user_consent FOR SELECT
TO authenticated
USING (public.is_any_admin(auth.uid()));

-- Auto-touch updated_at
CREATE TRIGGER trg_user_consent_updated_at
BEFORE UPDATE ON public.user_consent
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- =========================================================
-- AI INSIGHTS
-- =========================================================
CREATE TYPE public.insight_section AS ENUM (
  'executive', 'behavior', 'mobility', 'wallet',
  'marketplace', 'driver', 'merchant', 'fraud',
  'growth', 'recommendation'
);

CREATE TYPE public.insight_confidence AS ENUM ('low', 'medium', 'high');

CREATE TABLE public.ai_insights (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  section public.insight_section NOT NULL,
  title text NOT NULL,
  summary text NOT NULL,
  recommendation text NULL,
  confidence public.insight_confidence NOT NULL DEFAULT 'medium',
  metrics jsonb NOT NULL DEFAULT '{}'::jsonb,
  generated_for_date date NOT NULL DEFAULT (now() AT TIME ZONE 'UTC')::date,
  generated_by_user_id uuid NULL,
  status text NOT NULL DEFAULT 'new', -- new | reviewed | accepted | rejected
  reviewed_by uuid NULL,
  reviewed_at timestamptz NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_ai_insights_date ON public.ai_insights (generated_for_date DESC);
CREATE INDEX idx_ai_insights_section ON public.ai_insights (section);

ALTER TABLE public.ai_insights ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins read ai insights"
ON public.ai_insights FOR SELECT
TO authenticated
USING (public.is_any_admin(auth.uid()));

CREATE POLICY "Admins update ai insight status"
ON public.ai_insights FOR UPDATE
TO authenticated
USING (public.is_any_admin(auth.uid()))
WITH CHECK (public.is_any_admin(auth.uid()));

-- Inserts are restricted to the service role (edge function with service key).

-- =========================================================
-- AGGREGATION HELPER (admin-only)
-- =========================================================
CREATE OR REPLACE FUNCTION public.analytics_summary(p_days int DEFAULT 7)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_since timestamptz := now() - (p_days || ' days')::interval;
  v_result jsonb;
BEGIN
  IF v_uid IS NULL OR NOT public.is_any_admin(v_uid) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  WITH ev AS (
    SELECT * FROM public.analytics_events WHERE created_at >= v_since
  ),
  by_day AS (
    SELECT date_trunc('day', created_at) AS day, count(*)::int AS n
    FROM ev GROUP BY 1 ORDER BY 1
  ),
  by_category AS (
    SELECT event_category, count(*)::int AS n
    FROM ev GROUP BY 1 ORDER BY n DESC LIMIT 12
  ),
  top_events AS (
    SELECT event_name, count(*)::int AS n
    FROM ev GROUP BY 1 ORDER BY n DESC LIMIT 12
  ),
  top_routes AS (
    SELECT route, count(*)::int AS n
    FROM ev WHERE route IS NOT NULL GROUP BY 1 ORDER BY n DESC LIMIT 8
  ),
  top_zones AS (
    SELECT zone_neighborhood AS zone, count(*)::int AS n
    FROM ev WHERE zone_neighborhood IS NOT NULL GROUP BY 1 ORDER BY n DESC LIMIT 8
  ),
  top_search AS (
    SELECT lower(metadata->>'normalized_query') AS q, count(*)::int AS n
    FROM ev
    WHERE event_name = 'search.command.submitted'
      AND metadata ? 'normalized_query'
    GROUP BY 1 ORDER BY n DESC LIMIT 10
  ),
  failed_search AS (
    SELECT lower(metadata->>'normalized_query') AS q, count(*)::int AS n
    FROM ev
    WHERE event_name = 'search.command.no_result'
      AND metadata ? 'normalized_query'
    GROUP BY 1 ORDER BY n DESC LIMIT 10
  ),
  active_users AS (
    SELECT count(DISTINCT user_id)::int AS n
    FROM ev WHERE user_id IS NOT NULL
  ),
  active_sessions AS (
    SELECT count(DISTINCT anonymous_session_id)::int AS n FROM ev
  )
  SELECT jsonb_build_object(
    'window_days', p_days,
    'total_events', (SELECT count(*)::int FROM ev),
    'active_users', (SELECT n FROM active_users),
    'active_sessions', (SELECT n FROM active_sessions),
    'by_day', COALESCE((SELECT jsonb_agg(jsonb_build_object('day', day, 'n', n)) FROM by_day), '[]'::jsonb),
    'by_category', COALESCE((SELECT jsonb_agg(jsonb_build_object('category', event_category, 'n', n)) FROM by_category), '[]'::jsonb),
    'top_events', COALESCE((SELECT jsonb_agg(jsonb_build_object('name', event_name, 'n', n)) FROM top_events), '[]'::jsonb),
    'top_routes', COALESCE((SELECT jsonb_agg(jsonb_build_object('route', route, 'n', n)) FROM top_routes), '[]'::jsonb),
    'top_zones', COALESCE((SELECT jsonb_agg(jsonb_build_object('zone', zone, 'n', n)) FROM top_zones), '[]'::jsonb),
    'top_search', COALESCE((SELECT jsonb_agg(jsonb_build_object('q', q, 'n', n)) FROM top_search), '[]'::jsonb),
    'failed_search', COALESCE((SELECT jsonb_agg(jsonb_build_object('q', q, 'n', n)) FROM failed_search), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;