import React from 'react';
import { Marker } from 'react-map-gl';
import { useDriverLocation } from '@/lib/maps';
import { MapMarker } from './MapMarker';
export function DriverMarker({ driverId, variant = 'moto' }: { driverId: string; variant?: 'moto' | 'toktok' }) {
  const pos = useDriverLocation(driverId);
  if (!pos) return null;
  return (
    <Marker longitude={pos.lng} latitude={pos.lat} anchor="center">
      <MapMarker variant={variant}
        state={pos.status === 'busy' ? 'busy' : pos.status === 'offline' ? 'offline' : 'online'}
        rotation={pos.heading} size={32} label="Chauffeur" />
    </Marker>
  );
}
