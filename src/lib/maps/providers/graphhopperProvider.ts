import type { RouteProvider } from './types';

export const graphhopperProvider: RouteProvider = {
  name: 'graphhopper',
  async route() { throw new Error('GraphHopper provider not configured'); },
  async eta() { throw new Error('GraphHopper provider not configured'); },
};