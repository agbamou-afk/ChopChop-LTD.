import { useEffect, useRef, useState } from "react";
import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Sparkles, Send, Loader2, ArrowRight, ShieldCheck } from "lucide-react";
import { AIService } from "@/lib/ai";
import { motion, AnimatePresence } from "framer-motion";
import { useAuthGuard } from "@/hooks/useAuthGuard";

type Action = "moto" | "toktok" | "food" | "market" | "send" | "scan";

interface Turn {
  role: "user" | "assistant";
  text: string;
  suggestedAction?: Action | "none";
  suggestedLabel?: string;
  loading?: boolean;
  error?: boolean;
}

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onAction: (action: Action) => void;
  location?: string;
}

const QUICK_PROMPTS = [
  "Réserver une moto vers Madina",
  "Trouver à manger près de moi",
  "Envoyer 50 000 GNF à un ami",
  "Voir les annonces du Marché",
];

export function HomeAssistantSheet({ open, onOpenChange, onAction, location }: Props) {
  const [turns, setTurns] = useState<Turn[]>([]);
  const [input, setInput] = useState("");
  const [pending, setPending] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);
  const { requireAuth } = useAuthGuard();

  useEffect(() => {
    if (open) {
      setTimeout(() => scrollRef.current?.scrollTo({ top: 9e9, behavior: "smooth" }), 50);
    }
  }, [open, turns.length]);

  async function ask(prompt: string) {
    const text = prompt.trim();
    if (!text || pending) return;
    if (!requireAuth()) return;
    setInput("");
    setTurns((t) => [...t, { role: "user", text }, { role: "assistant", text: "", loading: true }]);
    setPending(true);
    const res = await AIService.askHome(text, { location });
    setPending(false);
    setTurns((t) => {
      const next = [...t];
      const last = next[next.length - 1];
      if (!last || last.role !== "assistant") return next;
      if (res.ok !== true) {
        next[next.length - 1] = {
          role: "assistant",
          text: (res as { error?: string }).error || "Désolé, l'assistant n'est pas disponible.",
          error: true,
        };
      } else {
        const j = res.json;
        next[next.length - 1] = {
          role: "assistant",
          text: j?.answer || res.text || "",
          suggestedAction: j?.suggested_action,
          suggestedLabel: j?.suggested_action_label,
        };
      }
      return next;
    });
  }

  function runSuggested(action: Action) {
    onOpenChange(false);
    setTimeout(() => onAction(action), 120);
  }

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="h-[88vh] p-0 flex flex-col rounded-t-3xl">
        <SheetHeader className="px-5 pt-5 pb-3 border-b border-border/60">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-2xl bg-primary/10 flex items-center justify-center">
              <Sparkles className="w-5 h-5 text-primary" />
            </div>
            <div className="text-left">
              <SheetTitle className="text-base">Assistant CHOP CHOP</SheetTitle>
              <p className="text-[11px] text-muted-foreground flex items-center gap-1">
                <ShieldCheck className="w-3 h-3" /> Sécurisé · ne valide jamais d'action sensible
              </p>
            </div>
          </div>
        </SheetHeader>

        <div ref={scrollRef} className="flex-1 overflow-y-auto px-4 py-4 space-y-3">
          {turns.length === 0 && (
            <div className="space-y-4 pt-4">
              <p className="text-sm text-muted-foreground text-center">
                Demandez ce que vous voulez : course, repas, paiement, marché.
              </p>
              <div className="flex flex-col gap-2">
                {QUICK_PROMPTS.map((q) => (
                  <button
                    key={q}
                    onClick={() => ask(q)}
                    className="w-full text-left px-4 py-3 bg-card border border-border/60 rounded-2xl text-sm hover:border-primary/40 transition-colors flex items-center justify-between gap-3"
                  >
                    <span>{q}</span>
                    <ArrowRight className="w-4 h-4 text-muted-foreground shrink-0" />
                  </button>
                ))}
              </div>
            </div>
          )}

          <AnimatePresence initial={false}>
            {turns.map((t, i) => (
              <motion.div
                key={i}
                initial={{ opacity: 0, y: 6 }}
                animate={{ opacity: 1, y: 0 }}
                className={t.role === "user" ? "flex justify-end" : "flex justify-start"}
              >
                <div
                  className={
                    t.role === "user"
                      ? "max-w-[85%] bg-primary text-primary-foreground rounded-2xl rounded-tr-sm px-4 py-2.5 text-sm"
                      : "max-w-[90%] bg-card border border-border/60 rounded-2xl rounded-tl-sm px-4 py-3 text-sm space-y-3"
                  }
                >
                  {t.loading ? (
                    <span className="inline-flex items-center gap-2 text-muted-foreground">
                      <Loader2 className="w-3.5 h-3.5 animate-spin" /> Réflexion…
                    </span>
                  ) : (
                    <>
                      <p className={t.error ? "text-destructive" : ""}>{t.text}</p>
                      {t.role === "assistant" &&
                        t.suggestedAction &&
                        t.suggestedAction !== "none" && (
                          <Button
                            size="sm"
                            onClick={() => runSuggested(t.suggestedAction as Action)}
                            className="w-full"
                          >
                            {t.suggestedLabel || "Continuer"}
                            <ArrowRight className="w-4 h-4 ml-1" />
                          </Button>
                        )}
                    </>
                  )}
                </div>
              </motion.div>
            ))}
          </AnimatePresence>
        </div>

        <form
          onSubmit={(e) => {
            e.preventDefault();
            ask(input);
          }}
          className="border-t border-border/60 p-3 flex items-center gap-2 bg-background"
        >
          <Input
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder="Posez votre question…"
            className="flex-1 h-11 rounded-xl"
            autoFocus
            disabled={pending}
          />
          <Button type="submit" size="icon" className="h-11 w-11 rounded-xl" disabled={pending || !input.trim()}>
            {pending ? <Loader2 className="w-4 h-4 animate-spin" /> : <Send className="w-4 h-4" />}
          </Button>
        </form>
      </SheetContent>
    </Sheet>
  );
}