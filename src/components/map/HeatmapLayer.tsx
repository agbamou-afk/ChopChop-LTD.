import React from 'react';
import { Source, Layer } from 'react-map-gl';
import type { LatLng } from '@/lib/maps/geo';
export function HeatmapLayer({ points }: { points: Array<LatLng & { weight?: number }> }) {
  const data = { type: 'FeatureCollection' as const, features: points.map(p => ({
    type: 'Feature' as const, properties: { mag: p.weight ?? 1 },
    geometry: { type: 'Point' as const, coordinates: [p.lng, p.lat] },
  })) };
  return (
    <Source id="heat" type="geojson" data={data}>
      <Layer id="heat-layer" type="heatmap"
        paint={{ 'heatmap-weight': ['get', 'mag'], 'heatmap-intensity': 1, 'heatmap-radius': 30, 'heatmap-opacity': 0.7 }} />
    </Source>
  );
}
