import { WowClassConfig } from "."

const DemonHunterConfig: WowClassConfig = {
  id: 12,
  name: "Demon Hunter",
  slug: "demon-hunter",
  iconUrl: "https://render.worldofwarcraft.com/us/icons/56/classicon_demonhunter.jpg",
  color: "#A330C9",
  colorOlkch: "oklch(0.4502 0.2343 306.19)",
  specs: [
    {
      id: 577,
      name: "havoc",
      url: "/demon-hunter/havoc",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/ability_demonhunter_specdps.jpg",
    },
    {
      id: 581,
      name: "vengeance",
      url: "/demon-hunter/vengeance",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/spell_demonhunter_spectank.jpg",
    },
  ],
}

export default DemonHunterConfig
