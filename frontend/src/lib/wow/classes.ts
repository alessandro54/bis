import { WOW_CLASSES, type WowClassConfig, type WowClassSlug } from "@/config/wow/classes";

export function getWowClassBySlug(slug: WowClassSlug): WowClassConfig | null {
  return WOW_CLASSES.find((c) => c.slug === slug) ?? null;
}
