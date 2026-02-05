import { WowClassConfig } from "."

const EvokerConfig: WowClassConfig = {
  id: 13,
  name: "Evoker",
  slug: "evoker",
  iconUrl: "https://render.worldofwarcraft.com/us/icons/56/classicon_evoker.jpg",
  color: "#33937F",
  colorOlkch: "oklch(0.4353 0.2535 162.19)",
  specs: [
    {
      id: 1467,
      name: "devastation",
      url: "/evoker/devastation",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/classicon_evoker_devastation.jpg",
    },
    {
      id: 1468,
      name: "preservation",
      url: "/evoker/preservation",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/classicon_evoker_preservation.jpg",
    },
    {
      id: 1473,
      name: "augmentation",
      url: "/evoker/augmentation",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/classicon_evoker_augmentation.jpg",
    },
  ],
}

export default EvokerConfig
