import { Marker } from "react-map-gl";
import { Flame, TrendingUp } from "lucide-react";
import { Card } from "@/components/ui/card";
import { ChopMap, HeatmapLayer } from "@/components/map";

const CONAKRY_HOTSPOTS = [
  { name: "Kaloum", lng: -13.7100, lat: 9.5100, weight: 1.0 },
  { name: "Madina", lng: -13.6650, lat: 9.5550, weight: 0.92 },
  { name: "Hamdallaye", lng: -13.6450, lat: 9.5800, weight: 0.78 },
  { name: "Ratoma", lng: -13.6800, lat: 9.6300, weight: 0.7 },
  { name: "Kipé", lng: -13.6300, lat: 9.6500, weight: 0.55 },
  { name: "Aéroport", lng: -13.6120, lat: 9.5770, weight: 0.5 },
] as const;

interface Props {
  isOnline?: boolean;
  /** When true, fill the available height instead of a fixed map height. */
  full?: boolean;
}

export function DriverHotspotsCard({ isOnline = true, full = false }: Props) {
  const sorted = [...CONAKRY_HOTSPOTS].sort((a, b) => b.weight - a.weight);
  const top = sorted[0];
  return (
    <Card className={`overflow-hidden ${full ? "flex flex-col h-full" : ""}`}>
      <div className="px-4 pt-3 pb-2 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Flame className="w-4 h-4 text-destructive" />
          <p className="text-sm font-semibold text-foreground">Zones les plus actives</p>
        </div>
        <span className="text-[11px] text-muted-foreground">Conakry · temps réel</span>
      </div>
      <div className={`relative ${full ? "flex-1 min-h-[280px]" : "h-48"} bg-muted`}>
        <ChopMap
          className="absolute inset-0 w-full h-full"
          interactive={false}
          initialView={{ longitude: -13.6773, latitude: 9.5900, zoom: 11.2 }}
        >
          <HeatmapLayer points={CONAKRY_HOTSPOTS.map((h) => ({ lng: h.lng, lat: h.lat, weight: h.weight }))} />
          {sorted.slice(0, 3).map((h, i) => (
            <Marker key={h.name} longitude={h.lng} latitude={h.lat} anchor="bottom">
              <div className="flex flex-col items-center pointer-events-none">
                <div
                  className={`px-2 py-0.5 rounded-full text-[10px] font-bold shadow-card ${
                    i === 0
                      ? "bg-destructive text-destructive-foreground"
                      : "bg-card text-foreground border border-border"
                  }`}
                >
                  {h.name}
                </div>
                <div
                  className={`w-2 h-2 rounded-full mt-0.5 ${
                    i === 0 ? "bg-destructive" : "bg-foreground/60"
                  }`}
                />
              </div>
            </Marker>
          ))}
        </ChopMap>
        {!isOnline && (
          <div className="absolute inset-0 bg-background/70 backdrop-blur-[2px] flex items-center justify-center">
            <p className="text-xs text-muted-foreground px-3 text-center">
              Passez en ligne pour recevoir des demandes
            </p>
          </div>
        )}
      </div>
      <div className="px-4 py-3 border-t border-border/60 flex items-center gap-3">
        <div className="p-2 rounded-xl bg-destructive/10">
          <TrendingUp className="w-4 h-4 text-destructive" />
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Zone la plus active</p>
          <p className="text-sm font-semibold text-foreground truncate">
            {top.name} · forte demande
          </p>
        </div>
        <span className="text-[11px] font-bold text-destructive whitespace-nowrap">
          {Math.round(top.weight * 100)}%
        </span>
      </div>
    </Card>
  );
}
