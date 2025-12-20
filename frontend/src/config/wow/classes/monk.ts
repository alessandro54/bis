import { WowClassConfig } from "@/config/wow/classes/index";

const MonkConfig: WowClassConfig = {
  id: 10,
  name: "Monk",
  slug: "monk",
  iconUrl: "https://render.worldofwarcraft.com/us/icons/56/classicon_monk.jpg",
  color: "#00FF96",
  colorOlkch: "oklch(0.8667 0.2535 155.19)",
  specs: [
    {
      id: 268,
      name: "brewmaster",
      url: "/monk/brewmaster",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/spell_monk_brewmaster_spec.jpg",
    },
    {
      id: 270,
      name: "mistweaver",
      url: "/monk/mistweaver",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/spell_monk_mistweaver_spec.jpg",
    },
    {
      id: 269,
      name: "windwalker",
      url: "/monk/windwalker",
      iconUrl: "https://render.worldofwarcraft.com/us/icons/56/spell_monk_windwalker_spec.jpg",
    },
  ],
}

export default MonkConfig