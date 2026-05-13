import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Bell, Check, Trash2, Wallet, Car, Package, ShoppingBag, Info } from "lucide-react";
import { AppShell } from "@/components/ui/AppShell";
import { PageHeader } from "@/components/ui/PageHeader";
import { EmptyState } from "@/components/ui/EmptyState";
import { notifications, type AppNotification } from "@/lib/notifications";
import { Seo } from "@/components/Seo";

const KIND_ICON: Record<AppNotification["kind"], typeof Bell> = {
  wallet: Wallet,
  ride: Car,
  delivery: Package,
  marche: ShoppingBag,
  system: Info,
};

const KIND_TINT: Record<AppNotification["kind"], string> = {
  wallet: "bg-brand-green-muted text-primary",
  ride: "bg-brand-yellow-muted text-secondary-foreground",
  delivery: "bg-brand-yellow-muted text-secondary-foreground",
  marche: "bg-brand-red-muted text-destructive",
  system: "bg-muted text-foreground",
};

function formatTime(iso: string) {
  const diff = Date.now() - new Date(iso).getTime();
  const m = Math.round(diff / 60000);
  if (m < 1) return "À l'instant";
  if (m < 60) return `Il y a ${m} min`;
  const h = Math.round(m / 60);
  if (h < 24) return `Il y a ${h} h`;
  return new Date(iso).toLocaleDateString("fr-FR", { day: "2-digit", month: "short" });
}

const NotificationsPage = () => {
  const navigate = useNavigate();
  const [items, setItems] = useState<AppNotification[]>([]);

  useEffect(() => {
    const refresh = () => setItems(notifications.list());
    refresh();
    window.addEventListener("chopchop:notifications:update", refresh);
    return () => window.removeEventListener("chopchop:notifications:update", refresh);
  }, []);

  return (
    <AppShell>
      <Seo title="Notifications — CHOP CHOP" description="Vos alertes courses, livraisons et portefeuille." canonical="/notifications" />
      <PageHeader
        title="Notifications"
        onBack={() => navigate(-1)}
        right={
          items.length > 0 ? (
            <div className="flex items-center gap-1">
              <button
                onClick={() => notifications.markAllRead()}
                className="p-2 rounded-full hover:bg-muted"
                aria-label="Tout marquer lu"
              >
                <Check className="w-5 h-5" />
              </button>
              <button
                onClick={() => notifications.clear()}
                className="p-2 rounded-full hover:bg-muted"
                aria-label="Tout supprimer"
              >
                <Trash2 className="w-5 h-5 text-destructive" />
              </button>
            </div>
          ) : null
        }
      />

      <div className="px-4 pt-2">
        {items.length === 0 ? (
          <EmptyState
            icon={Bell}
            title="Aucune notification"
            description="Vos alertes courses, livraisons, paiements et marché s'afficheront ici."
          />
        ) : (
          <ul className="space-y-2">
            {items.map((n) => {
              const Icon = KIND_ICON[n.kind];
              return (
                <li
                  key={n.id}
                  onClick={() => notifications.markRead(n.id)}
                  className={`flex gap-3 p-3 rounded-2xl cursor-pointer transition ${
                    n.read ? "bg-card" : "bg-card shadow-card border border-primary/20"
                  }`}
                >
                  <span className={`w-10 h-10 rounded-xl flex items-center justify-center shrink-0 ${KIND_TINT[n.kind]}`}>
                    <Icon className="w-5 h-5" />
                  </span>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center justify-between gap-2">
                      <p className="font-semibold text-sm text-foreground truncate">{n.title}</p>
                      {!n.read && <span className="w-2 h-2 rounded-full bg-primary shrink-0" />}
                    </div>
                    <p className="text-xs text-muted-foreground line-clamp-2">{n.body}</p>
                    <p className="text-[10px] text-muted-foreground mt-1">{formatTime(n.createdAt)}</p>
                  </div>
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </AppShell>
  );
};

export default NotificationsPage;
