/**
 * PrivacyConsentManager — single source of truth for user analytics consent.
 *
 * - Anonymous visitors get a sensible default (basic on, marketing off).
 * - Authenticated users have their preferences persisted in `user_consent`.
 * - Security/fraud signals are ALWAYS recorded for platform safety. This is
 *   stated transparently in the privacy screen.
 */
import { supabase } from "@/integrations/supabase/client";

export interface ConsentState {
  basic_analytics: boolean;
  personalization: boolean;
  location_improvements: boolean;
  marketing_analytics: boolean;
  security_fraud: true;
}

const STORAGE_KEY = "cc.consent.v1";

const DEFAULTS: ConsentState = {
  basic_analytics: true,
  personalization: true,
  location_improvements: false,
  marketing_analytics: false,
  security_fraud: true,
};

let cache: ConsentState = readLocal();
const listeners = new Set<(s: ConsentState) => void>();

function readLocal(): ConsentState {
  if (typeof window === "undefined") return DEFAULTS;
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return DEFAULTS;
    return { ...DEFAULTS, ...JSON.parse(raw), security_fraud: true };
  } catch {
    return DEFAULTS;
  }
}

function writeLocal(state: ConsentState) {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  } catch {
    /* ignore storage errors */
  }
}

export const Consent = {
  current(): ConsentState {
    return cache;
  },

  subscribe(fn: (s: ConsentState) => void) {
    listeners.add(fn);
    return () => {
      listeners.delete(fn);
    };
  },

  /** Load the latest consent for an authenticated user. Falls back silently. */
  async loadForUser(userId: string): Promise<ConsentState> {
    const { data } = await supabase
      .from("user_consent")
      .select("*")
      .eq("user_id", userId)
      .maybeSingle();
    if (data) {
      cache = {
        basic_analytics: data.basic_analytics,
        personalization: data.personalization,
        location_improvements: data.location_improvements,
        marketing_analytics: data.marketing_analytics,
        security_fraud: true,
      };
      writeLocal(cache);
      listeners.forEach((l) => l(cache));
    }
    return cache;
  },

  /** Persist a new consent state. */
  async save(userId: string | null, next: Partial<Omit<ConsentState, "security_fraud">>) {
    cache = { ...cache, ...next, security_fraud: true };
    writeLocal(cache);
    listeners.forEach((l) => l(cache));
    if (userId) {
      await supabase
        .from("user_consent")
        .upsert(
          {
            user_id: userId,
            basic_analytics: cache.basic_analytics,
            personalization: cache.personalization,
            location_improvements: cache.location_improvements,
            marketing_analytics: cache.marketing_analytics,
            security_fraud: true,
          },
          { onConflict: "user_id" },
        );
    }
    return cache;
  },
};

export type { ConsentState as TConsentState };