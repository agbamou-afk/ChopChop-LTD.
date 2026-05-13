import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
export interface MapConfig {
  mapboxToken: string; styleUrl: string;
  defaultCenter: { lat: number; lng: number };
  defaultZoom: number;
  flags: { heatmap: boolean; surge: boolean; clustering: boolean };
  provider: 'google' | 'osrm' | 'graphhopper';
}
let cached: MapConfig | null = null;
let inflight: Promise<MapConfig> | null = null;
async function fetchConfig(): Promise<MapConfig> {
  if (cached) return cached;
  if (inflight) return inflight;
  inflight = (async () => {
    const { data, error } = await supabase.functions.invoke('maps-config');
    if (error) throw error;
    cached = data as MapConfig;
    return cached;
  })();
  return inflight;
}
export function useMapConfig() {
  const [config, setConfig] = useState<MapConfig | null>(cached);
  const [error, setError] = useState<Error | null>(null);
  useEffect(() => { if (cached) return; fetchConfig().then(setConfig).catch(setError); }, []);
  return { config, error, loading: !config && !error };
}
