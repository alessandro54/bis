"use client";

import { createContext, useContext, useState } from "react";
import type { WowClassSlug } from "@/config/wow/classes";

type HoverContextValue = {
  slug: WowClassSlug | null;
  setSlug: (slug: WowClassSlug | null) => void;
};

const HoverContext = createContext<HoverContextValue | null>(null);

export function HoverProvider({ children }: { children: React.ReactNode }) {
  const [slug, setSlug] = useState<WowClassSlug | null>(null);

  const value: HoverContextValue = {
    slug,
    setSlug,
  };

  return (
    <HoverContext.Provider value={value}>
      {children}
    </HoverContext.Provider>
  );
}

export function useHoverSlug() {
  const ctx = useContext(HoverContext);
  if (!ctx) {
    throw new Error("useHoverSlug must be used within HoverProvider");
  }
  return ctx;
}
