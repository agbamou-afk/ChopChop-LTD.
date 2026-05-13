import React, { useMemo } from 'react';
import { Source, Layer } from 'react-map-gl';
import { decodePolyline } from '@/lib/maps/geo';
export function RoutePolyline({ encoded, id = 'chop-route' }: { encoded: string; id?: string }) {
  const geojson = useMemo(() => {
    const coords = decodePolyline(encoded).map(p => [p.lng, p.lat]);
    return { type: 'FeatureCollection' as const, features: [{ type: 'Feature' as const, properties: {}, geometry: { type: 'LineString' as const, coordinates: coords } }] };
  }, [encoded]);
  return (
    <Source id={id} type="geojson" data={geojson}>
      <Layer id={`${id}-casing`} type="line" paint={{ 'line-color': '#ffffff', 'line-width': 8, 'line-opacity': 0.9 }} layout={{ 'line-cap': 'round', 'line-join': 'round' }} />
      <Layer id={`${id}-line`} type="line" paint={{ 'line-color': 'hsl(138, 64%, 42%)', 'line-width': 5 }} layout={{ 'line-cap': 'round', 'line-join': 'round' }} />
    </Source>
  );
}
