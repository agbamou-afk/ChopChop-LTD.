import { useEffect, useRef } from "react";
import { toast } from "sonner";
import { Analytics } from "@/lib/analytics/AnalyticsService";

/**
 * Fires a calm, single "Connexion rétablie" toast whenever the browser
 * transitions from offline → online. Designed for trip-critical surfaces
 * (RealtimeTripScreen, DriverActiveTrip) where users need confidence that
 * the app reconnected after a brief network blip.
 *
 * - No toast on initial mount.
 * - Dedups bursts within 4s.
 * - Tracks `ride.connection.restored` for analytics.
 */
export function useConnectionRestored(opts?: { context?: string }) {
  const wasOffline = useRef<boolean>(
    typeof navigator !== "undefined" ? !navigator.onLine : false,
  );
  const lastFiredAt = useRef<number>(0);

  useEffect(() => {
    if (typeof window === "undefined") return;
    const onOnline = () => {
      if (!wasOffline.current) return;
      wasOffline.current = false;
      const now = Date.now();
      if (now - lastFiredAt.current < 4000) return;
      lastFiredAt.current = now;
      toast.success("Connexion rétablie", {
        description: "Suivi en direct repris.",
        id: "cc:connection-restored",
        duration: 2800,
      });
      try {
        Analytics.track("ride.connection.restored", {
          metadata: { context: opts?.context ?? "generic" },
        });
      } catch {}
    };
    const onOffline = () => {
      wasOffline.current = true;
    };
    window.addEventListener("online", onOnline);
    window.addEventListener("offline", onOffline);
    return () => {
      window.removeEventListener("online", onOnline);
      window.removeEventListener("offline", onOffline);
    };
  }, [opts?.context]);
}