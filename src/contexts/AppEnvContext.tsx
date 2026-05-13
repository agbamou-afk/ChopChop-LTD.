import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";

const LS_LOW_DATA = "cc:low_data_mode";

type Ctx = {
  online: boolean;
  lowDataMode: boolean;
  setLowDataMode: (v: boolean) => void;
};

const AppEnvContext = createContext<Ctx | null>(null);

export function AppEnvProvider({ children }: { children: React.ReactNode }) {
  const [online, setOnline] = useState<boolean>(typeof navigator === "undefined" ? true : navigator.onLine);
  const [lowDataMode, setLowDataModeState] = useState<boolean>(() => {
    if (typeof window === "undefined") return false;
    const saved = localStorage.getItem(LS_LOW_DATA);
    if (saved !== null) return saved === "1";
    // Auto-enable if browser advertises Save-Data
    const conn = (navigator as Navigator & { connection?: { saveData?: boolean; effectiveType?: string } }).connection;
    if (conn?.saveData) return true;
    if (conn?.effectiveType && ["slow-2g", "2g"].includes(conn.effectiveType)) return true;
    return false;
  });

  useEffect(() => {
    const onUp = () => {
      setOnline(true);
      window.dispatchEvent(new CustomEvent("cc:online"));
    };
    const onDown = () => {
      setOnline(false);
      window.dispatchEvent(new CustomEvent("cc:offline_event"));
    };
    window.addEventListener("online", onUp);
    window.addEventListener("offline", onDown);
    return () => {
      window.removeEventListener("online", onUp);
      window.removeEventListener("offline", onDown);
    };
  }, []);

  const setLowDataMode = useCallback((v: boolean) => {
    setLowDataModeState(v);
    try { localStorage.setItem(LS_LOW_DATA, v ? "1" : "0"); } catch { /* ignore */ }
    window.dispatchEvent(new CustomEvent("cc:low_data_mode_enabled", { detail: { enabled: v } }));
  }, []);

  const value = useMemo(() => ({ online, lowDataMode, setLowDataMode }), [online, lowDataMode, setLowDataMode]);

  return <AppEnvContext.Provider value={value}>{children}</AppEnvContext.Provider>;
}

export function useAppEnv(): Ctx {
  const ctx = useContext(AppEnvContext);
  if (!ctx) {
    // Sensible fallback when used outside provider (tests, isolated stories)
    return { online: true, lowDataMode: false, setLowDataMode: () => {} };
  }
  return ctx;
}

/**
 * Guard for any action that touches money / state-changing flows.
 * Returns false (and emits an offline event) when the device is offline.
 */
export function ensureOnlineForFinancialAction(): boolean {
  const isOnline = typeof navigator === "undefined" ? true : navigator.onLine;
  if (!isOnline) {
    window.dispatchEvent(new CustomEvent("cc:offline_event", { detail: { blocked: "financial" } }));
  }
  return isOnline;
}