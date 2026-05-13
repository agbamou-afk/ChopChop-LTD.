import { WifiOff, RefreshCw } from "lucide-react";
import { Button } from "@/components/ui/button";

export default function OfflinePage() {
  return (
    <div className="min-h-[100dvh] flex flex-col items-center justify-center px-6 text-center bg-background">
      <div className="w-16 h-16 rounded-full bg-muted flex items-center justify-center mb-4">
        <WifiOff className="w-8 h-8 text-muted-foreground" />
      </div>
      <h1 className="text-xl font-bold text-foreground">Vous êtes hors ligne</h1>
      <p className="mt-2 max-w-sm text-sm text-muted-foreground">
        Connexion indisponible. Certaines fonctions seront limitées.
      </p>
      <Button className="mt-6" onClick={() => window.location.reload()}>
        <RefreshCw className="w-4 h-4 mr-2" /> Réessayer
      </Button>
    </div>
  );
}