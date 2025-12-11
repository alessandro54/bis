import DeathKnightConfig from "./death-knight";
import DemonHunterConfig from "./demon-hunter";
import DruidConfig from "./druid";
import EvokerConfig from "./evoker";
import MageConfig from "./mage";
import PaladinConfig from "./paladin";
import PriestConfig from "./priest";
import RogueConfig from "./rogue";
import WarriorConfig from "./warrior";

export type WowClassSlug = "death-knight" | "demon-hunter" | "druid"
  | "hunter" | "mage" | "monk" | "paladin" | "priest" | "rogue"
  | "shaman" | "warlock" | "warrior" | "evoker";

export type WowClassSpecSlug =
  | "frost" | "unholy" | "blood"
  | "havoc" | "vengeance"
  | "balance" | "feral" | "guardian" | "restoration"
  | "beast-mastery" | "marksmanship" | "survival"
  | "arcane" | "fire" | "frost-mage"
  | "windwalker" | "mistweaver" | "brewmaster"
  | "holy" | "protection" | "retribution"
  | "discipline" | "holy" | "shadow"
  | "assassination" | "outlaw" | "subtlety"
  | "elemental" | "enhancement" | "restoration"
  | "affliction" | "demonology" | "destruction"
  | "arms" | "fury" | "protection"
  | "devastation" | "preservation" | "augmentation";

export type WowClassSpec = {
  id: number;
  name: WowClassSpecSlug;
  url: string;
  iconUrl: string;
};

export type WowClassConfig = {
  id: number;
  name: string;
  slug: WowClassSlug;
  iconUrl: string;
  color: string;
  colorOlkch: string;
  bgGradient?: string;
  specs: WowClassSpec[];
}

export const WOW_CLASSES: WowClassConfig[] = [
  RogueConfig,
  PaladinConfig,
  DeathKnightConfig,
  DemonHunterConfig,
  DruidConfig,
  MageConfig,
  WarriorConfig,
  PriestConfig,
  EvokerConfig
]
