import { useEffect, useState } from "react";

/** Detects iOS-style camera island / notch via safe-area-inset CSS env. */
export function useHasNotch() {
  const [hasNotch, setHasNotch] = useState(false);
  useEffect(() => {
    const probe = document.createElement("div");
    probe.style.cssText = "position:absolute;top:0;left:0;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left);visibility:hidden;pointer-events:none;";
    document.body.appendChild(probe);
    const cs = getComputedStyle(probe);
    const top = parseInt(cs.paddingTop) || 0;
    const left = parseInt(cs.paddingLeft) || 0;
    document.body.removeChild(probe);
    setHasNotch(top >= 20 || left >= 20);
  }, []);
  return hasNotch;
}
