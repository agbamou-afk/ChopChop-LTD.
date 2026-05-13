import type { LatLng } from './geo';
import type { NormalizedRoute, RouteMode, RouteProvider, EtaMatrixCell } from './providers/types';
import { googleProvider } from './providers/googleProvider';
import { osrmProvider } from './providers/osrmProvider';
import { graphhopperProvider } from './providers/graphhopperProvider';

const providers: Record<string, RouteProvider> = {
  google: googleProvider, osrm: osrmProvider, graphhopper: graphhopperProvider,
};
let activeProvider: RouteProvider = googleProvider;
const routeCache = new Map<string, { at: number; route: NormalizedRoute }>();
const etaCache = new Map<string, { at: number; rows: EtaMatrixCell[][] }>();
const ROUTE_TTL = 60_000, ETA_TTL = 30_000;
function key(o: LatLng, d: LatLng, mode: string) {
  return `${o.lat.toFixed(5)},${o.lng.toFixed(5)}|${d.lat.toFixed(5)},${d.lng.toFixed(5)}|${mode}`;
}
export const RoutingService = {
  setProvider(name: 'google' | 'osrm' | 'graphhopper') { activeProvider = providers[name] ?? googleProvider; },
  getProvider() { return activeProvider.name; },
  async route(origin: LatLng, destination: LatLng, mode: RouteMode = 'driving'): Promise<NormalizedRoute> {
    const k = key(origin, destination, mode);
    const cached = routeCache.get(k);
    if (cached && Date.now() - cached.at < ROUTE_TTL) return cached.route;
    const route = await activeProvider.route({ origin, destination, mode });
    routeCache.set(k, { at: Date.now(), route });
    return route;
  },
  async eta(origins: LatLng[], destinations: LatLng[], mode: RouteMode = 'driving') {
    const k = origins.map(o => `${o.lat.toFixed(4)},${o.lng.toFixed(4)}`).join(';') + '||' +
      destinations.map(d => `${d.lat.toFixed(4)},${d.lng.toFixed(4)}`).join(';') + '|' + mode;
    const cached = etaCache.get(k);
    if (cached && Date.now() - cached.at < ETA_TTL) return cached.rows;
    const rows = await activeProvider.eta(origins, destinations, mode);
    etaCache.set(k, { at: Date.now(), rows });
    return rows;
  },
};
