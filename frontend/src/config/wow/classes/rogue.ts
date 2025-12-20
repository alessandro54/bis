import { WowClassConfig } from ".";

const RogueConfig: WowClassConfig = {
  id: 4,
  name: "Rogue",
  slug: "rogue",
  iconUrl: "https://render.worldofwarcraft.com/us/icons/56/classicon_rogue.jpg",
  color: "#FFF468",
  colorOlkch: "oklch(0.8471 0.2243 91.37)",
  specs: [
    {
      id: 259,
      name: "assassination",
      url: "/rogue/assassination",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/ability_rogue_deadlybrew.jpg",
    },
    {
      id: 260,
      name: "outlaw",
      url: "/rogue/outlaw",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/ability_rogue_rollthebones.jpg",
    },
    {
      id: 261,
      name: "subtlety",
      url: "/rogue/subtlety",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/ability_rogue_shadowdance.jpg",
    },
  ],
};

export default RogueConfig;
