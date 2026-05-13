import { useCallback } from "react";
import { useLocation, useNavigate } from "react-router-dom";
import { useAuth } from "@/contexts/AuthContext";
import { toast } from "@/hooks/use-toast";

/**
 * Returns auth status and a `requireAuth(fn)` helper backed by the global AuthContext.
 * If the user is signed in, runs `fn` and returns true. Otherwise pushes them to /auth
 * with a `next` param and returns false.
 */
export function useAuthGuard() {
  const { isLoggedIn, ready, isProfileComplete } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();

  const requireAuth = useCallback(
    (fn?: () => void) => {
      if (!ready) return false;
      if (!isLoggedIn) {
        const next = encodeURIComponent(location.pathname + location.search);
        toast({ title: "Connexion requise", description: "Connectez-vous pour continuer." });
        navigate(`/auth?next=${next}`);
        return false;
      }
      if (!isProfileComplete) {
        navigate("/complete-profile");
        return false;
      }
      fn?.();
      return true;
    },
    [ready, isLoggedIn, isProfileComplete, navigate, location.pathname, location.search],
  );

  return { isLoggedIn, ready, requireAuth };
}