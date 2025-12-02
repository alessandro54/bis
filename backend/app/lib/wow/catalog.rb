module Wow
  module Catalog
    SPECS = {
      62 => { spec_slug: "arcane_mage",        class_id: 8,  class_slug: "mage",         role: :dps },
      63 => { spec_slug: "fire_mage",          class_id: 8,  class_slug: "mage",         role: :dps },
      64 => { spec_slug: "frost_mage",         class_id: 8,  class_slug: "mage",         role: :dps },

      65 => { spec_slug: "holy_paladin",       class_id: 2,  class_slug: "paladin",      role: :healer },
      66 => { spec_slug: "protection_paladin", class_id: 2,  class_slug: "paladin",      role: :tank },
      70 => { spec_slug: "retribution_paladin",class_id: 2,  class_slug: "paladin",      role: :dps },

      71 => { spec_slug: "arms_warrior",       class_id: 1,  class_slug: "warrior",      role: :dps },
      72 => { spec_slug: "fury_warrior",       class_id: 1,  class_slug: "warrior",      role: :dps },
      73 => { spec_slug: "protection_warrior", class_id: 1,  class_slug: "warrior",      role: :tank },

      102 => { spec_slug: "balance_druid",     class_id: 11, class_slug: "druid",        role: :dps },
      103 => { spec_slug: "feral_druid",       class_id: 11, class_slug: "druid",        role: :dps },
      104 => { spec_slug: "guardian_druid",    class_id: 11, class_slug: "druid",        role: :tank },
      105 => { spec_slug: "restoration_druid", class_id: 11, class_slug: "druid",        role: :healer },

      250 => { spec_slug: "blood_death_knight",  class_id: 6, class_slug: "death_knight", role: :tank },
      251 => { spec_slug: "frost_death_knight",  class_id: 6, class_slug: "death_knight", role: :dps },
      252 => { spec_slug: "unholy_death_knight", class_id: 6, class_slug: "death_knight", role: :dps },

      253 => { spec_slug: "beast_mastery_hunter", class_id: 3, class_slug: "hunter",     role: :dps },
      254 => { spec_slug: "marksmanship_hunter",  class_id: 3, class_slug: "hunter",     role: :dps },
      255 => { spec_slug: "survival_hunter",      class_id: 3, class_slug: "hunter",     role: :dps },

      256 => { spec_slug: "discipline_priest",  class_id: 5, class_slug: "priest",       role: :healer },
      257 => { spec_slug: "holy_priest",        class_id: 5, class_slug: "priest",       role: :healer },
      258 => { spec_slug: "shadow_priest",      class_id: 5, class_slug: "priest",       role: :dps },

      259 => { spec_slug: "assassination_rogue", class_id: 4, class_slug: "rogue",       role: :dps },
      260 => { spec_slug: "outlaw_rogue",        class_id: 4, class_slug: "rogue",       role: :dps },
      261 => { spec_slug: "subtlety_rogue",      class_id: 4, class_slug: "rogue",       role: :dps },

      262 => { spec_slug: "elemental_shaman",    class_id: 7, class_slug: "shaman",      role: :dps },
      263 => { spec_slug: "enhancement_shaman",  class_id: 7, class_slug: "shaman",      role: :dps },
      264 => { spec_slug: "restoration_shaman",  class_id: 7, class_slug: "shaman",      role: :healer },

      265 => { spec_slug: "affliction_warlock",  class_id: 9, class_slug: "warlock",     role: :dps },
      266 => { spec_slug: "demonology_warlock",  class_id: 9, class_slug: "warlock",     role: :dps },
      267 => { spec_slug: "destruction_warlock", class_id: 9, class_slug: "warlock",     role: :dps },

      268 => { spec_slug: "brewmaster_monk",   class_id: 10, class_slug: "monk",         role: :tank },
      269 => { spec_slug: "windwalker_monk",   class_id: 10, class_slug: "monk",         role: :dps },
      270 => { spec_slug: "mistweaver_monk",   class_id: 10, class_slug: "monk",         role: :healer },

      577 => { spec_slug: "havoc_demon_hunter",    class_id: 12, class_slug: "demon_hunter", role: :dps },
      581 => { spec_slug: "vengeance_demon_hunter",class_id: 12, class_slug: "demon_hunter", role: :tank },

      1467 => { spec_slug: "devastation_evoker",  class_id: 13, class_slug: "evoker",    role: :dps },
      1468 => { spec_slug: "preservation_evoker", class_id: 13, class_slug: "evoker",    role: :healer },
      1473 => { spec_slug: "augmentation_evoker", class_id: 13, class_slug: "evoker",    role: :dps }
    }.freeze

    CLASS_INDEX = SPECS.values
                       .uniq { |data| data[:class_id] }
                       .map { |data| [data[:class_id], data[:class_slug]] }
                       .to_h
                       .freeze

    def self.spec_slug(spec_id)
      SPECS[spec_id]&.fetch(:spec_slug, nil)
    end

    def self.class_id_for_spec(spec_id)
      SPECS[spec_id]&.fetch(:class_id, nil)
    end

    def self.class_slug_for_spec(spec_id)
      SPECS[spec_id]&.fetch(:class_slug, nil)
    end

    def self.role_for_spec(spec_id)
      SPECS[spec_id]&.fetch(:role, nil)
    end

    def self.class_slug(class_id)
      CLASS_INDEX[class_id]
    end
  end
end