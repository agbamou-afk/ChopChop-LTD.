import { QuickActions } from "@/components/home/QuickActions";
import { MapPin, Search, Home as HomeIcon, Briefcase, Clock } from "lucide-react";
import { PromoCarousel } from "@/components/home/PromoCarousel";
import { RestaurantCard } from "@/components/food/RestaurantCard";
import { AppHeader } from "@/components/ui/AppHeader";

interface UserHomeProps {
  onActionClick: (action: string) => void;
  onToggleDriverMode: () => void;
}

const popularRestaurants = [
  {
    name: "Chez Mama Fatoumata",
    image: "https://images.unsplash.com/photo-1555939594-58d7cb561ad1?w=400&h=300&fit=crop",
    rating: 4.8,
    deliveryTime: "20-30 min",
    distance: "1.2 km",
    category: "Cuisine locale",
  },
  {
    name: "Grillades du Port",
    image: "https://images.unsplash.com/photo-1544025162-d76694265947?w=400&h=300&fit=crop",
    rating: 4.6,
    deliveryTime: "25-35 min",
    distance: "2.1 km",
    category: "Grillades",
  },
];

export function UserHome({ onActionClick, onToggleDriverMode }: UserHomeProps) {
  const walletBalance = 2500000;
  const userLocation = "Kaloum";
  const recents = [
    { icon: HomeIcon, label: "Maison", sub: "Ratoma" },
    { icon: Briefcase, label: "Travail", sub: "Kaloum" },
    { icon: Clock, label: "Madina", sub: "Récent" },
    { icon: Clock, label: "Aéroport", sub: "Récent" },
  ];
  return (
    <div className="max-w-md mx-auto">
      <AppHeader
        isDriverMode={false}
        onToggleDriverMode={onToggleDriverMode}
        amountLabel="Solde portefeuille"
        amountValue={walletBalance}
        notificationCount={1}
        onAmountClick={() => onActionClick("send")}
      />

      {/* Content */}
      <div className="px-4 mt-6 space-y-6">
        {/* Universal search */}
        <button
          onClick={() => onActionClick("moto")}
          className="w-full flex items-center gap-3 px-4 py-3.5 bg-card rounded-2xl shadow-card text-left hover:bg-muted/50 transition-colors"
        >
          <Search className="w-5 h-5 text-muted-foreground shrink-0" />
          <span className="text-sm text-muted-foreground">
            Où allez-vous ? Que voulez-vous faire ?
          </span>
        </button>

        {/* Quick Actions */}
        <section>
          <h2 className="text-lg font-semibold text-foreground mb-4">Services</h2>
          <div className="bg-card rounded-3xl shadow-card p-4">
            <QuickActions onActionClick={onActionClick} />
          </div>
        </section>

        {/* Recent destinations */}
        <section>
          <h2 className="text-lg font-semibold text-foreground mb-3">Récents</h2>
          <div className="flex gap-2 overflow-x-auto pb-1 -mx-4 px-4 scrollbar-none">
            {recents.map((r) => (
              <button
                key={r.label}
                onClick={() => onActionClick("moto")}
                className="shrink-0 flex items-center gap-2 px-3 py-2.5 bg-card rounded-2xl shadow-card hover:bg-muted/50 transition-colors"
              >
                <div className="w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center">
                  <r.icon className="w-4 h-4 text-primary" />
                </div>
                <div className="text-left">
                  <p className="text-sm font-medium text-foreground leading-tight">{r.label}</p>
                  <p className="text-[10px] text-muted-foreground leading-tight">{r.sub}</p>
                </div>
              </button>
            ))}
          </div>
        </section>

        {/* Promos */}
        <section>
          <h2 className="text-lg font-semibold text-foreground mb-4">Offres spéciales</h2>
          <PromoCarousel />
        </section>

        {/* Popular restaurants */}
        <section className="pb-6">
          <div className="flex items-center justify-between mb-4">
            <div>
              <h2 className="text-lg font-semibold text-foreground">Restaurants populaires</h2>
              <div className="flex items-center gap-1 text-xs text-muted-foreground mt-0.5">
                <MapPin className="w-3 h-3 text-primary" />
                <span>Proche de {userLocation}</span>
              </div>
            </div>
            <button 
              onClick={() => onActionClick("food")}
              className="text-sm font-medium text-primary"
            >
              Voir tout
            </button>
          </div>
          <div className="grid grid-cols-2 gap-3">
            {popularRestaurants.map((restaurant) => (
              <RestaurantCard
                key={restaurant.name}
                {...restaurant}
                onClick={() => onActionClick("food")}
              />
            ))}
          </div>
        </section>
      </div>
    </div>
  );
}
