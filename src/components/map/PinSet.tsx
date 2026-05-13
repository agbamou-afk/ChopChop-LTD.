import React from 'react';
import { Marker } from 'react-map-gl';
import { MapMarker } from './MapMarker';
import type { LatLng } from '@/lib/maps/geo';
export function PinSet({ pickup, dropoff, pulseActive }: { pickup?: LatLng | null; dropoff?: LatLng | null; pulseActive?: 'pickup' | 'dropoff' }) {
  return (
    <>
      {pickup && <Marker longitude={pickup.lng} latitude={pickup.lat} anchor="bottom"><MapMarker variant="pickup" pulse={pulseActive === 'pickup'} label="Départ" size={36} /></Marker>}
      {dropoff && <Marker longitude={dropoff.lng} latitude={dropoff.lat} anchor="bottom"><MapMarker variant="dropoff" pulse={pulseActive === 'dropoff'} label="Destination" size={36} /></Marker>}
    </>
  );
}
