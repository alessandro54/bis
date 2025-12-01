# lib/wow/specs.rb
module Wow
  module Specs
    SPEC_IDS = {
      62 => "arcane_mage",
      63 => "fire_mage",
      64 => "frost_mage",

      65 => "holy_paladin",
      66 => "protection_paladin",
      70 => "retribution_paladin",

      71 => "arms_warrior",
      72 => "fury_warrior",
      73 => "protection_warrior",

      102 => "balance_druid",
      103 => "feral_druid",
      104 => "guardian_druid",
      105 => "restoration_druid",

      250 => "blood_death_knight",
      251 => "frost_death_knight",
      252 => "unholy_death_knight",

      253 => "beast_mastery_hunter",
      254 => "marksmanship_hunter",
      255 => "survival_hunter",

      256 => "discipline_priest",
      257 => "holy_priest",
      258 => "shadow_priest",

      259 => "assassination_rogue",
      260 => "outlaw_rogue",
      261 => "subtlety_rogue",

      262 => "elemental_shaman",
      263 => "enhancement_shaman",
      264 => "restoration_shaman",

      265 => "affliction_warlock",
      266 => "demonology_warlock",
      267 => "destruction_warlock",

      268 => "brewmaster_monk",
      269 => "windwalker_monk",
      270 => "mistweaver_monk",

      577 => "havoc_demon_hunter",
      581 => "vengeance_demon_hunter",

      1467 => "devastation_evoker",
      1468 => "preservation_evoker",
      1473 => "augmentation_evoker"
    }.freeze

    def self.slug_for(id)
      SPEC_IDS[id]
    end
  end
end
