import type { LatLng } from './geo';
const COMMUNES: Array<{ name: string; bbox: [number, number, number, number] }> = [
  { name: 'Kaloum', bbox: [-13.726, 9.490, -13.685, 9.530] },
  { name: 'Dixinn', bbox: [-13.685, 9.520, -13.640, 9.575] },
  { name: 'Matam', bbox: [-13.660, 9.530, -13.620, 9.570] },
  { name: 'Ratoma', bbox: [-13.700, 9.580, -13.580, 9.690] },
  { name: 'Matoto', bbox: [-13.620, 9.560, -13.480, 9.650] },
];
export function communeFor(p: LatLng): string | null {
  for (const c of COMMUNES) {
    const [minLng, minLat, maxLng, maxLat] = c.bbox;
    if (p.lng >= minLng && p.lng <= maxLng && p.lat >= minLat && p.lat <= maxLat) return c.name;
  }
  return null;
}
