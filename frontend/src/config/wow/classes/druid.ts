import { WowClassConfig } from "."

const DruidConfig: WowClassConfig = {
  id: 11,
  name: "Druid",
  slug: "druid",
  iconUrl: "https://render.worldofwarcraft.com/us/icons/56/classicon_druid.jpg",
  color: "#FF7D0A",
  colorOlkch: "oklch(0.6031 0.2533 64.27)",
  specs: [
    {
      id: 102,
      name: "balance",
      url: "/druid/balance",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/spell_nature_starfall.jpg",
    },
    {
      id: 103,
      name: "feral",
      url: "/druid/feral",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/ability_druid_catform.jpg",
    },
    {
      id: 104,
      name: "guardian",
      url: "/druid/guardian",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/ability_druid_bearform.jpg",
    },
    {
      id: 105,
      name: "restoration",
      url: "/druid/restoration",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/spell_nature_healingtouch.jpg",
    },
  ],
}

export default DruidConfig
