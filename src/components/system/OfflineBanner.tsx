import { useAppEnv } from "@/contexts/AppEnvContext";
import { WifiOff } from "lucide-react";

export function OfflineBanner() {
  const { online } = useAppEnv();
  if (online) return null;
  return (
    <div
      role="status"
      className="fixed top-0 inset-x-0 z-[60] bg-warning text-warning-foreground text-xs font-semibold px-4 py-1.5 flex items-center justify-center gap-2 shadow-soft"
    >
      <WifiOff className="w-3.5 h-3.5" />
      Connexion indisponible. Certaines fonctions seront limitées.
    </div>
  );
}