"use client";

import { useSyncExternalStore } from "react";
import { themeStorageKey } from "./theme";

type Theme = "light" | "dark";

const changeEvent = "mubangumi-theme-change";

function currentTheme(): Theme {
  const chosen = document.documentElement.dataset.theme;
  if (chosen === "light" || chosen === "dark") return chosen;
  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

function subscribe(onChange: () => void) {
  const media = window.matchMedia("(prefers-color-scheme: dark)");
  media.addEventListener("change", onChange);
  window.addEventListener(changeEvent, onChange);
  return () => {
    media.removeEventListener("change", onChange);
    window.removeEventListener(changeEvent, onChange);
  };
}

export function ThemeToggle() {
  const theme = useSyncExternalStore<Theme | null>(subscribe, currentTheme, () => null);
  const next: Theme = theme === "dark" ? "light" : "dark";

  const toggle = () => {
    document.documentElement.dataset.theme = next;
    try {
      localStorage.setItem(themeStorageKey, next);
    } catch {
      // Private browsing can refuse storage; the choice still applies now.
    }
    window.dispatchEvent(new Event(changeEvent));
  };

  return (
    <button
      type="button"
      className="theme-toggle"
      onClick={toggle}
      aria-label={next === "light" ? "切换到浅色主题" : "切换到深色主题"}
      title={next === "light" ? "切换到浅色主题" : "切换到深色主题"}
    >
      <svg viewBox="0 0 24 24" aria-hidden="true" className="theme-sun">
        <circle cx="12" cy="12" r="4" />
        <path d="M12 2.5v2M12 19.5v2M4.6 4.6 6 6M18 18l1.4 1.4M2.5 12h2M19.5 12h2M4.6 19.4 6 18M18 6l1.4-1.4" />
      </svg>
      <svg viewBox="0 0 24 24" aria-hidden="true" className="theme-moon">
        <path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5Z" />
      </svg>
    </button>
  );
}
