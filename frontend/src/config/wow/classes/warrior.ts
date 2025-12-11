import { WowClassConfig } from "."

const WarriorConfig: WowClassConfig = {
  id: 1,
  name: "Warrior",
  slug: "warrior",
  iconUrl: "https://render.worldofwarcraft.com/us/icons/56/classicon_warrior.jpg",
  color: "#C69B6D",
  colorOlkch: "oklch(0.6431 0.2243 37.45)",
  specs: [
    {
      id: 71,
      name: "arms",
      url: "/warrior/arms",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/ability_warrior_savageblow.jpg",
    },
    {
      id: 72,
      name: "fury",
      url: "/warrior/fury",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/ability_warrior_innerrage.jpg",
    },
    {
      id: 73,
      name: "protection",
      url: "/warrior/protection",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/ability_warrior_defensivestance.jpg",
    },
  ],
}

export default WarriorConfig
