import { WowClassConfig } from ".";

const PaladinConfig: WowClassConfig = {
  id: 2,
  name: "Paladin",
  slug: "paladin",
  iconUrl: "https://render.worldofwarcraft.com/us/icons/56/classicon_paladin.jpg",
  color: "#F58CBA",
  colorOlkch: "oklch(0.765 0.1373 353.11)",
  specs: [
    {
      id: 21,
      name: "holy",
      url: "/paladin/holy-paladin",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/spell_holy_holybolt.jpg",
    },
    {
      id: 22,
      name: "protection",
      url: "/paladin/protection-paladin",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/spell_holy_devotionaura.jpg",
    },
    {
      id: 23,
      name: "retribution",
      url: "/paladin/retribution",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/spell_holy_auraoflight.jpg",
    },
  ],
}

export default PaladinConfig;
