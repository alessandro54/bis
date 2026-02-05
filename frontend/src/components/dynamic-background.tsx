"use client";

import { useEffect, useState } from "react";
import { usePathname } from "next/navigation";
import { getWowClassBySlug } from "@/lib/wow/classes";
import type { WowClassSlug } from "@/config/wow/classes";
import { useHoverSlug } from "./wow/hover-provider";

const DEFAULT_BG = "#ec4899";

export default function DynamicBackground() {
  const { slug: hoverSlug } = useHoverSlug();
  const pathname = usePathname();

  const [baseSlug, setBaseSlug] = useState<WowClassSlug | null>(null);

  useEffect(() => {
    const segments = pathname.split("/").filter(Boolean);
    const first = segments[0] as WowClassSlug | undefined;
    setBaseSlug(first ?? null);
  }, [pathname]);

  const activeSlug = hoverSlug ?? baseSlug;
  const cls = activeSlug ? getWowClassBySlug(activeSlug) : null;
  const background = cls?.color ?? DEFAULT_BG;

  return (
    <div
      className="absolute left-1/2 -translate-x-1/2 w-[90vw] h-[50vw] rounded-full filter blur-3xl opacity-30 animate-blob animation-delay-6000 pointer-events-none overflow-hidden transition-all duration-700 ease-in-out"
      style={{
        zIndex: -1,
        bottom: "-45vw",
        background
      }}
    />
  );
}
