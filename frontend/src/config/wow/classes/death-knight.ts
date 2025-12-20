import { WowClassConfig } from "."

const DeathKnightConfig: WowClassConfig = {
  id: 6,
  name: "Death Knight",
  slug: "death-knight",
  iconUrl: "https://render.worldofwarcraft.com/us/icons/56/spell_deathknight_classicon.jpg",
  color: "#C41E3A",
  colorOlkch: "oklch(0.5308 0.1969 19.54)",
  specs: [
    {
      id: 251,
      name: "frost",
      url: "/death-knight/frost",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/spell_deathknight_frostpresence.jpg",
    },
    {
      id: 252,
      name: "unholy",
      url: "/death-knight/unholy",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/spell_deathknight_unholypresence.jpg",
    },
    {
      id: 250,
      name: "blood",
      url: "/death-knight/blood",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/spell_deathknight_bloodpresence.jpg",
    },
  ],
}

export default DeathKnightConfig
