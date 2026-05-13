import { motion } from "framer-motion";
import motoIcon from "@/assets/icons/moto.png";
import toktokIcon from "@/assets/icons/toktok.png";
import repasIcon from "@/assets/icons/repas.png";
import marcheIcon from "@/assets/icons/marche.png";
import envoyerIcon from "@/assets/icons/envoyer.png";
import scannerIcon from "@/assets/icons/scanner.png";

interface QuickActionsProps {
  onActionClick: (action: string) => void;
}

const TILE_BG = "bg-[hsl(0_0%_94%)]";
const actions = [
  { id: "moto", img: motoIcon, label: "Moto", alt: "Réserver une moto-taxi", tint: TILE_BG },
  { id: "toktok", img: toktokIcon, label: "TokTok", alt: "Réserver un TokTok tricycle", tint: TILE_BG },
  { id: "food", img: repasIcon, label: "Repas", alt: "Commander un repas à domicile", tint: TILE_BG },
  { id: "market", img: marcheIcon, label: "Marché", alt: "Acheter au marché en ligne", tint: TILE_BG },
  { id: "send", img: envoyerIcon, label: "Envoyer", alt: "Envoyer de l'argent à un proche", tint: TILE_BG },
  { id: "scan", img: scannerIcon, label: "Scanner", alt: "Scanner un QR code marchand", tint: TILE_BG },
];

const container = {
  hidden: { opacity: 0 },
  show: {
    opacity: 1,
    transition: {
      staggerChildren: 0.05,
    },
  },
};

const item = {
  hidden: { opacity: 0, y: 20 },
  show: { opacity: 1, y: 0 },
};

export function QuickActions({ onActionClick }: QuickActionsProps) {
  return (
    <motion.div
      variants={container}
      initial="hidden"
      animate="show"
      className="grid grid-cols-3 gap-x-4 gap-y-3"
    >
      {actions.map((action) => (
        <motion.button
          key={action.id}
          variants={item}
          whileHover={{ scale: 1.05 }}
          whileTap={{ scale: 0.95 }}
          onClick={() => onActionClick(action.id)}
          className="flex flex-col items-center transition-transform"
        >
          <div className={`w-20 h-20 rounded-2xl ${action.tint} flex items-center justify-center mb-2 shadow-card overflow-hidden`}>
            <img
              src={action.img}
              alt={action.alt}
              loading="lazy"
              width={1024}
              height={1024}
              className="w-20 h-20 object-contain scale-150"
            />
          </div>
          <span className="text-xs font-semibold text-foreground">{action.label}</span>
        </motion.button>
      ))}
    </motion.div>
  );
}
