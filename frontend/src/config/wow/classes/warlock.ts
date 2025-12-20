import {WowClassConfig} from "@/config/wow/classes/index";

const WarlockConfig: WowClassConfig = {
  id: 9,
  name: "Warlock",
  slug: "warlock",
  iconUrl: "https://render.worldofwarcraft.com/us/icons/56/classicon_warlock.jpg",
  color: "#9482C9",
  colorOlkch: "oklch(0.5902 0.1373 289.11)",
  specs: [
    {
      id: 265,
      name: "affliction",
      url: "/warlock/affliction",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/spell_shadow_deathcoil.jpg",
    },
    {
      id: 266,
      name: "demonology",
      url: "/warlock/demonology",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/spell_shadow_metamorphosis.jpg",
    },
    {
      id: 267,
      name: "destruction",
      url: "/warlock/destruction",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/spell_shadow_rainoffire.jpg",
    },
  ],
}

export default WarlockConfig
