import { WowClassConfig } from "."

const PriestConfig: WowClassConfig = {
  id: 5,
  name: "Priest",
  slug: "priest",
  iconUrl: "https://render.worldofwarcraft.com/us/icons/56/classicon_priest.jpg",
  color: "#FFFFFF",
  colorOlkch: "oklch(0.9275 0.0 0.0)",
  specs: [
    {
      id: 256,
      name: "discipline",
      url: "/priest/discipline",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/spell_holy_powerwordshield.jpg",
    },
    {
      id: 257,
      name: "holy",
      url: "/priest/holy",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/spell_holy_guardianspirit.jpg",
    },
    {
      id: 258,
      name: "shadow",
      url: "/priest/shadow",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/spell_shadow_shadowwordpain.jpg",
    },
  ],
}

export default PriestConfig
