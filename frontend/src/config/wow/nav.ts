import { WOW_CLASSES, WowClassConfig } from "./classes";

export type NavMainItem = {
  id: number;
  title: string;
  url: string;
  slug: string;
  iconUrl: string;
  items: {
    id: number;
    title: string;
    url: string;
    iconUrl: string;
  }[];
};

export type NavMain = NavMainItem[];

export const navMain: NavMain = WOW_CLASSES.map((cls: WowClassConfig) => ({
  id: cls.id,
  title: cls.name,
  slug: cls.slug,
  url: cls.name.toLowerCase(),
  iconUrl: cls.iconUrl,
  items: cls.specs.map((spec) => ({
    id: spec.id,
    title: spec.name,
    url: spec.url,
    iconUrl: spec.iconUrl,
  })),
}));
