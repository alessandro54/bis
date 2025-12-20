import { WowClassConfig } from "@/config/wow/classes/index";

const HunterConfig: WowClassConfig = {
  id: 3,
  name: "Hunter",
  slug: "hunter",
  iconUrl: "https://render.worldofwarcraft.com/us/icons/56/classicon_hunter.jpg",
  color: "#AAD372",
  colorOlkch: "oklch(0.7843 0.1373 125.11)",
  specs: [
    {
      id: 253,
      name: "beast-mastery",
      url: "/hunter/beast-mastery",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/ability_hunter_bestialdiscipline.jpg",
    },
    {
      id: 254,
      name: "marksmanship",
      url: "/hunter/marksmanship",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/ability_hunter_focusedaim.jpg",
    },
    {
      id: 255,
      name: "survival",
      url: "/hunter/survival",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/ability_hunter_camouflage.jpg",
    },
  ],
}

export default HunterConfig