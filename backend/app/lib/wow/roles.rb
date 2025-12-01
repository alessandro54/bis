# app/lib/wow/roles.rb
module Wow
  module Roles
    ROLE_BY_CLASS_SPEC = {
      # Warrior
      [ 1, 71 ] => :dps,   # Arms
      [ 1, 72 ] => :dps,   # Fury
      [ 1, 73 ] => :tank,  # Protection

      # Paladin
      [ 2, 65 ] => :healer, # Holy
      [ 2, 66 ] => :tank,   # Protection
      [ 2, 70 ] => :dps,    # Retribution

      # Hunter
      [ 3, 253 ] => :dps,   # Beast Mastery
      [ 3, 254 ] => :dps,   # Marksmanship
      [ 3, 255 ] => :dps,   # Survival

      # Rogue
      [ 4, 259 ] => :dps,
      [ 4, 260 ] => :dps,
      [ 4, 261 ] => :dps,

      # Priest
      [ 5, 256 ] => :healer, # Discipline
      [ 5, 257 ] => :healer, # Holy
      [ 5, 258 ] => :dps,    # Shadow

      # DK
      [ 6, 250 ] => :tank,  # Blood
      [ 6, 251 ] => :dps,   # Frost
      [ 6, 252 ] => :dps,   # Unholy

      # Shaman
      [ 7, 262 ] => :dps,    # Elemental
      [ 7, 263 ] => :dps,    # Enhancement
      [ 7, 264 ] => :healer, # Restoration

      # Mage
      [ 8, 62 ] => :dps, # Arcane
      [ 8, 63 ] => :dps, # Fire
      [ 8, 64 ] => :dps, # Frost

      # Warlock
      [ 9, 265 ] => :dps,
      [ 9, 266 ] => :dps,
      [ 9, 267 ] => :dps,

      # Monk
      [ 10, 268 ] => :tank,   # Brewmaster
      [ 10, 269 ] => :dps,    # Windwalker
      [ 10, 270 ] => :healer, # Mistweaver

      # Druid
      [ 11, 102 ] => :dps,    # Balance
      [ 11, 103 ] => :dps,    # Feral
      [ 11, 104 ] => :tank,   # Guardian
      [ 11, 105 ] => :healer, # Restoration

      # DH
      [ 12, 577 ] => :dps,  # Havoc
      [ 12, 581 ] => :tank, # Vengeance

      # Evoker (ajusta si quieres tratar Aug diferente)
      [ 13, 1467 ] => :dps,    # Devastation
      [ 13, 1468 ] => :healer, # Preservation
      [ 13, 1473 ] => :dps     # Augmentation
    }.freeze

    def self.role_for(class_id:, spec_id:)
      ROLE_BY_CLASS_SPEC[[ class_id, spec_id ]]
    end
  end
end
