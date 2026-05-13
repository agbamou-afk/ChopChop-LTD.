import { corsHeaders } from 'npm:@supabase/supabase-js@2/cors';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { checkMapsRateLimit, logMapsRequest } from '../_shared/maps-rate-limit.ts';

interface LatLng { lat: number; lng: number }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  const start = Date.now();
  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  let userId: string | null = null;
  const authHeader = req.headers.get('Authorization') ?? '';
  if (authHeader) {
    const userClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: { user } } = await userClient.auth.getUser();
    userId = user?.id ?? null;
  }

  try {
    const body = await req.json();
    const origins: LatLng[] = body.origins ?? [];
    const destinations: LatLng[] = body.destinations ?? [];
    const mode = body.mode ?? 'driving';
    if (!origins.length || !destinations.length || origins.length > 25 || destinations.length > 25) {
      return new Response(JSON.stringify({ error: 'Invalid origins/destinations' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (userId) {
      const rl = await checkMapsRateLimit(admin, userId, 'eta', 120);
      if (!rl.allowed) {
        return new Response(JSON.stringify({ error: 'Rate limited' }), {
          status: 429,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
    }

    const key = Deno.env.get('GOOGLE_MAPS_SERVER_KEY');
    if (!key) throw new Error('GOOGLE_MAPS_SERVER_KEY not configured');
    const params = new URLSearchParams({
      origins: origins.map(o => `${o.lat},${o.lng}`).join('|'),
      destinations: destinations.map(d => `${d.lat},${d.lng}`).join('|'),
      mode,
      key,
      region: 'gn',
      language: 'fr',
    });
    const r = await fetch(`https://maps.googleapis.com/maps/api/distancematrix/json?${params}`);
    const data = await r.json();
    if (data.status !== 'OK') {
      await logMapsRequest(admin, {
        user_id: userId, provider: 'google', action: 'eta',
        input: body, status: 'error',
        error_message: data.status, latency_ms: Date.now() - start,
      });
      return new Response(JSON.stringify({ error: data.status }), {
        status: 502,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    const rows = data.rows.map((row: any) => row.elements.map((el: any) => ({
      status: el.status,
      distanceM: el.distance?.value ?? null,
      durationS: el.duration?.value ?? null,
    })));
    await logMapsRequest(admin, {
      user_id: userId, provider: 'google', action: 'eta',
      input: { o: origins.length, d: destinations.length },
      latency_ms: Date.now() - start,
    });
    return new Response(JSON.stringify({ rows, provider: 'google' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});