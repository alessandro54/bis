# lib/wow/classes.rb
module Wow
  module Classes
    CLASS_IDS = {
      1 => "warrior",
      2 => "paladin",
      3 => "hunter",
      4 => "rogue",
      5 => "priest",
      6 => "death_knight",
      7 => "shaman",
      8 => "mage",
      9 => "warlock",
      10 => "monk",
      11 => "druid",
      12 => "demon_hunter",
      13 => "evoker"
    }.freeze

    def self.slug_for(id)
      CLASS_IDS[id]
    end
  end
end
