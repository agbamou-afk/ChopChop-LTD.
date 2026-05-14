/**
 * Compatibility shim.
 *
 * The legacy Radix-based toast system has been retired in favor of Sonner
 * (see src/lib/toast.ts and src/components/ui/sonner.tsx). To avoid a
 * mass-refactor of every call site we keep the same `toast({ title,
 * description, variant })` signature and route everything through the
 * unified `chopToast` helper so we get one consistent toast stack.
 */
import * as React from "react";
import { chopToast } from "@/lib/toast";

type Variant = "default" | "destructive" | "success" | "warning" | "info";

type LegacyToastInput = {
  title?: React.ReactNode;
  description?: React.ReactNode;
  variant?: Variant;
  action?: React.ReactNode;
  duration?: number;
};

function nodeToString(n: React.ReactNode): string {
  if (n == null || n === false) return "";
  if (typeof n === "string" || typeof n === "number") return String(n);
  if (Array.isArray(n)) return n.map(nodeToString).join("");
  // Fallback: ignore React elements – titles/descriptions are strings in practice.
  return "";
}

export function toast(input: LegacyToastInput = {}) {
  const title = nodeToString(input.title) || nodeToString(input.description) || "";
  const description = input.title ? nodeToString(input.description) || undefined : undefined;
  const opts = { description, duration: input.duration } as const;

  let id: string | number;
  switch (input.variant) {
    case "destructive":
      id = chopToast.error(title, opts);
      break;
    case "success":
      id = chopToast.success(title, opts);
      break;
    case "warning":
      id = chopToast.warning(title, opts);
      break;
    case "info":
      id = chopToast.info(title, opts);
      break;
    default:
      id = chopToast.message(title, opts);
  }

  return {
    id: String(id),
    dismiss: () => chopToast.dismiss(id),
    update: (_next: LegacyToastInput) => {
      // Sonner doesn't expose a stable update API for this shim; no-op.
    },
  };
}

/**
 * Legacy hook kept for source-compat. The Radix viewport is gone, so the
 * `toasts` array is always empty – Sonner renders the actual UI.
 */
export function useToast() {
  return {
    toasts: [] as Array<{ id: string }>,
    toast,
    dismiss: (toastId?: string | number) => chopToast.dismiss(toastId),
  };
}
