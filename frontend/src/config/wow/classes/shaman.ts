import { WowClassConfig } from "@/config/wow/classes/index";

const ShamanConfig: WowClassConfig = {
  id: 7,
  name: "Shaman",
  slug: "shaman",
  iconUrl: "https://render.worldofwarcraft.com/us/icons/56/classicon_shaman.jpg",
  color: "#0070DE",
  colorOlkch: "oklch(0.5373 0.2243 255.11)",
  specs: [
    {
      id: 262,
      name: "elemental",
      url: "/shaman/elemental",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/spell_nature_lightning.jpg",
    },
    {
      id: 263,
      name: "enhancement",
      url: "/shaman/enhancement",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/spell_shaman_improvedstormstrike.jpg",
    },
    {
      id: 264,
      name: "restoration",
      url: "/shaman/restoration",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/spell_nature_magicimmunity.jpg",
    },
  ],
}

export default ShamanConfig