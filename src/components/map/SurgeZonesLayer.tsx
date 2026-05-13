import React from 'react';
import { Source, Layer } from 'react-map-gl';
export function SurgeZonesLayer({ data }: { data: GeoJSON.FeatureCollection }) {
  return (
    <Source id="surge" type="geojson" data={data}>
      <Layer id="surge-fill" type="fill"
        paint={{ 'fill-color': ['interpolate', ['linear'], ['get', 'level'],
          0, 'hsla(138,64%,39%,0.1)', 1, 'hsla(38,95%,52%,0.25)', 2, 'hsla(2,75%,56%,0.35)'],
          'fill-outline-color': 'hsla(0,0%,100%,0.6)' }} />
    </Source>
  );
}
