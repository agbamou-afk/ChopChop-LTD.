export type MarkerVariant =
  | 'moto' | 'toktok' | 'food' | 'wallet' | 'marche' | 'pickup' | 'dropoff';

export type MarkerState = 'online' | 'offline' | 'busy';

export function markerColor(variant: MarkerVariant, state: MarkerState = 'online'): string {
  if (state === 'offline') return 'hsl(0 0% 60%)';
  if (state === 'busy') return 'hsl(38 95% 52%)';
  switch (variant) {
    case 'moto':    return 'hsl(138 64% 39%)';
    case 'toktok':  return 'hsl(45 90% 55%)';
    case 'food':    return 'hsl(8 78% 55%)';
    case 'wallet':  return 'hsl(38 95% 52%)';
    case 'marche':  return 'hsl(142 55% 38%)';
    case 'pickup':  return 'hsl(138 64% 39%)';
    case 'dropoff': return 'hsl(2 75% 56%)';
  }
}

export const variantGlyph: Record<MarkerVariant, string> = {
  moto:   'M5 17a3 3 0 1 0 0-6 3 3 0 0 0 0 6Zm14 0a3 3 0 1 0 0-6 3 3 0 0 0 0 6ZM6 14h6l3-6h3l1 3',
  toktok: 'M3 13h13v4H3zM16 9h3l2 4v4h-5z M6 18a2 2 0 1 0 0-4 2 2 0 0 0 0 4Zm12 0a2 2 0 1 0 0-4 2 2 0 0 0 0 4Z',
  food:   'M4 4v8a4 4 0 0 0 4 4v4M14 4c0 4 6 4 6 0v8a4 4 0 0 1-4 4v4',
  wallet: 'M3 7h15a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7zM3 7l3-3h12v3 M16 13h2',
  marche: 'M4 7h16l-1 11H5L4 7zM8 7V5a4 4 0 0 1 8 0v2',
  pickup: 'M12 2a7 7 0 0 0-7 7c0 5 7 13 7 13s7-8 7-13a7 7 0 0 0-7-7zm0 9a2 2 0 1 1 0-4 2 2 0 0 1 0 4z',
  dropoff:'M12 2a7 7 0 0 0-7 7c0 5 7 13 7 13s7-8 7-13a7 7 0 0 0-7-7zm0 9a2 2 0 1 1 0-4 2 2 0 0 1 0 4z',
};