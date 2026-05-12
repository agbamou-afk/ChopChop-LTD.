import { motion } from "framer-motion";
import { Bell, Menu, Wallet, ChevronRight } from "lucide-react";
import { WalletCard } from "@/components/home/WalletCard";
import { QuickActions } from "@/components/home/QuickActions";
import { PromoCarousel } from "@/components/home/PromoCarousel";
import { RestaurantCard } from "@/components/food/RestaurantCard";
import logo from "@/assets/logo.png";

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
  const formattedBalance = new Intl.NumberFormat("fr-GN").format(walletBalance);
  return (
    <div className="max-w-md mx-auto">
      {/* Header card */}
      <div className="px-4 pt-4">
        <motion.header
          initial={{ opacity: 0, y: -20 }}
          animate={{ opacity: 1, y: 0 }}
          className="bg-card rounded-3xl shadow-card px-5 pt-4 pb-5"
        >
          {/* Top row: menu / logo / bell */}
          <div className="flex items-center justify-between">
            <button
              onClick={onToggleDriverMode}
              className="p-2 -ml-2 rounded-full hover:bg-muted transition-colors"
              title="Menu"
              aria-label="Menu"
            >
              <Menu className="w-6 h-6 text-foreground" />
            </button>
            <img
              src={logo}
              alt="CHOP CHOP"
              className="h-20 w-auto object-contain"
            />
            <button
              className="p-2 -mr-2 rounded-full hover:bg-muted transition-colors relative"
              aria-label="Notifications"
            >
              <Bell className="w-6 h-6 text-foreground" />
              <span className="absolute top-1.5 right-1.5 w-2 h-2 bg-destructive rounded-full" />
            </button>
          </div>

          {/* Greeting + wallet pill */}
          <div className="mt-4 flex items-center gap-3">
            <div className="w-14 h-14 rounded-full bg-muted flex items-center justify-center text-xl font-bold text-primary shrink-0">
              A
            </div>
            <div className="flex-1 min-w-0">
              <h1 className="text-base font-bold text-foreground truncate">
                Bonjour, Alpha ! 👋
              </h1>
              <p className="text-sm text-muted-foreground truncate">
                Prêt à vous déplacer ?
              </p>
            </div>
            <button
              onClick={() => onActionClick("send")}
              className="flex items-center gap-2 bg-primary/10 hover:bg-primary/15 transition-colors rounded-2xl pl-3 pr-2 py-2"
            >
              <Wallet className="w-5 h-5 text-primary" />
              <div className="text-left">
                <p className="text-sm font-bold text-foreground leading-tight">
                  {formattedBalance} GNF
                </p>
                <p className="text-[10px] text-muted-foreground leading-tight">
                  Solde portefeuille
                </p>
              </div>
              <ChevronRight className="w-4 h-4 text-primary" />
            </button>
          </div>
        </motion.header>
      </div>

      {/* Content */}
      <div className="px-4 mt-6 space-y-6">
        {/* Quick Actions */}
        <section>
          <h2 className="text-lg font-semibold text-foreground mb-4">Services</h2>
          <QuickActions onActionClick={onActionClick} />
        </section>

        {/* Promos */}
        <section>
          <h2 className="text-lg font-semibold text-foreground mb-4">Offres spéciales</h2>
          <PromoCarousel />
        </section>

        {/* Popular restaurants */}
        <section className="pb-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-semibold text-foreground">Restaurants populaires</h2>
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
