# db/seeds.rb
#
# Full data-flow seed: 1 season → 1 leaderboard → 1 character → 1 entry
# with complete equipment (items, enchantments, sockets) and talents.
#
# Run with: bundle exec rails db:seed
# Re-runnable: clears all rows in dependency order first.

puts "── Clearing existing seed data ──────────────────────────────"

# PvpLeaderboardEntry.delete_all
# PvpLeaderboard.delete_all
# PvpSyncCycle.delete_all
# PvpSeason.delete_all
# CharacterTalent.delete_all
# CharacterItem.delete_all
# Character.delete_all
# Translation.delete_all
# Enchantment.delete_all
# Item.delete_all
# Talent.delete_all

puts "── Season & Leaderboard ─────────────────────────────────────"

# The active PvP season. Every leaderboard belongs to a season.
season = PvpSeason.find_or_create_by!(blizzard_id: 40) do |s|
  s.display_name = "Season 3 - The War Within"
  s.is_current   = true
  s.start_time   = "2025-04-01".to_datetime
end

# One leaderboard per bracket + region combination.
# The entry will live inside this leaderboard.
leaderboard = PvpLeaderboard.create!(
  pvp_season:     season,
  bracket:        "2v2",
  region:         "us",
  last_synced_at: Time.current
)

puts "── Items ────────────────────────────────────────────────────"

# Each equipped slot needs a row in `items`.
# The service upserts items by blizzard_id, writing name into `translations`.
# blizzard_id → unique Blizzard item ID from their API.

SLOT_ITEMS = {
  #  slot key      blizzard_id   name                          quality   inventory_type  item_class  item_subclass  ilvl
  head:      [ 225_001, "Voidbound Helm",                   "epic",  "head",     "armor",   "plate",  639 ],
  neck:      [ 225_002, "Chain of Endless Conquest",        "epic",  "neck",     "armor",   "misc",   639 ],
  shoulder:  [ 225_003, "Pauldrons of Shattered Will",      "epic",  "shoulder", "armor",   "plate",  639 ],
  back:      [ 225_004, "Cloak of Darkened Skies",          "epic",  "back",     "armor",   "cloth",  639 ],
  chest:     [ 225_005, "Breastplate of the Warlord",       "epic",  "chest",    "armor",   "plate",  639 ],
  wrist:     [ 225_006, "Vambraces of the Fallen",          "epic",  "wrist",    "armor",   "plate",  639 ],
  hands:     [ 225_007, "Gauntlets of Ruin",                "epic",  "hands",    "armor",   "plate",  639 ],
  waist:     [ 225_008, "Girdle of the Warmonger",          "epic",  "waist",    "armor",   "plate",  639 ],
  legs:      [ 225_009, "Greaves of Undying Fury",          "epic",  "legs",     "armor",   "plate",  639 ],
  feet:      [ 225_010, "Sabatons of the Vanguard",         "epic",  "feet",     "armor",   "plate",  639 ],
  finger_1:  [ 225_011, "Ring of Blazing Conquest",         "epic",  "finger",   "armor",   "misc",   639 ],
  finger_2:  [ 225_012, "Band of the Endless Storm",        "epic",  "finger",   "armor",   "misc",   639 ],
  trinket_1: [ 225_013, "Sigil of Undying Resolve",         "epic",  "trinket",  "armor",   "misc",   639 ],
  trinket_2: [ 225_014, "Emblem of Furious Strikes",        "epic",  "trinket",  "armor",   "misc",   639 ],
  main_hand: [ 225_015, "Greatsword of Rampant Fury",       "epic",  "two_hand", "weapon",  "sword",  639 ]
}.freeze

items = SLOT_ITEMS.transform_values do |blizzard_id, name, quality, inv_type, item_class, item_subclass, _ilvl|
  item = Item.create!(
    blizzard_id:    blizzard_id,
    inventory_type: inv_type,
    item_class:     item_class,
    item_subclass:  item_subclass,
    quality:        quality
  )
  # Name stored as a translation — not a column on items.
  item.set_translation("name", "en_US", name, meta: { source: "seed" })
  puts "  item ##{blizzard_id} #{name}"
  item
end

# Socket gem — it is just a regular item in the WoW item ID space.
# Several characters can socket the same gem; it is upserted once.
socket_gem = Item.create!(
  blizzard_id:    213_746,
  inventory_type: "gem",
  item_class:     "gem",
  item_subclass:  "prismatic",
  quality:        "rare"
)
socket_gem.set_translation("name", "en_US", "Culminating Blasphemite", meta: { source: "seed" })
puts "  gem    #213746 Culminating Blasphemite"

# Enchantment source item — the scroll/reagent used to apply the weapon enchant.
# Stored as an Item stub; full metadata can be synced later.
enc_source = Item.create!(
  blizzard_id:    226_977,
  inventory_type: "enchantment",
  item_class:     "miscellaneous",
  item_subclass:  "other",
  quality:        "uncommon"
)
enc_source.set_translation("name", "en_US", "Enchant Weapon - Authority of Radiant Power", meta: { source: "seed" })
puts "  scroll #226977 Enchant Weapon - Authority of Radiant Power"

puts "── Enchantments ─────────────────────────────────────────────"

# Enchantments are spell effects (enchantment_id from Blizzard API), NOT items.
# They live in their own table so they can carry translations separately.
ENCHANTMENT_DEFS = {
  weapon: [ 7_534, "Authority of Radiant Power" ],
  cloak:  [ 7_358, "Chant of Winged Grace" ],
  chest:  [ 7_364, "Crystalline Radiance" ],
  wrist:  [ 7_384, "Chant of Armored Speed" ],
  legs:   [ 7_400, "Stormrider's Agility" ],
  ring:   [ 7_340, "Radiant Mastery" ]
}.freeze

enchantments = ENCHANTMENT_DEFS.transform_values do |blizzard_id, name|
  enc = Enchantment.create!(blizzard_id: blizzard_id)
  enc.set_translation("name", "en_US", name, meta: { source: "seed" })
  puts "  enchantment ##{blizzard_id} #{name}"
  enc
end

puts "── Talents ──────────────────────────────────────────────────"

# Talents have no name column — names live exclusively in translations.
# talent_type ∈ { class, spec, hero, pvp }
# spell_id is the underlying spell (used for pvp talents and tooltips).

def seed_talents(defs, type)
  defs.map do |blizzard_id, name, spell_id|
    talent = Talent.create!(blizzard_id: blizzard_id, talent_type: type, spell_id: spell_id)
    talent.set_translation("name", "en_US", name, meta: { source: "seed" })
    puts "  #{type} talent ##{blizzard_id} #{name}"
    talent
  end
end

# Arms Warrior class tree
class_talents = seed_talents([
  [ 188_076, "Heroic Leap",       6_544 ],
  [ 197_930, "Battle Stance",     2_457 ],
  [ 188_082, "Spell Reflection",  23_920 ],
  [ 262_161, "War Machine",       262_232 ],
  [ 206_333, "Enduring Alacrity", 201_900 ]
], "class")

# Arms Warrior spec tree
spec_talents = seed_talents([
  [ 260_708, "Mortal Strike", 12_294 ],
  [ 260_709, "Overpower",        7_384 ],
  [ 260_710, "Slam",             1_464 ],
  [ 260_711, "Bladestorm",     227_847 ],
  [ 260_712, "Colossus Smash", 167_105 ],
  [ 260_713, "Warbreaker",     262_161 ]
], "spec")

# Colossus hero talent tree
hero_talents = seed_talents([
  [ 453_288, "Colossal Might", 440_989 ],
  [ 453_289, "Boneshaker",     440_892 ],
  [ 453_290, "Mountain Thane", 440_999 ]
], "hero")

# PvP talents (slot_number starts at 2 per Blizzard convention)
pvp_talents = seed_talents([
  [ 202_751, "Sharpen Blade",  202_751 ],
  [ 202_573, "Death Sentence", 12_294 ],
  [ 236_289, "Disarm", 236_077 ]
], "pvp")

puts "── Character ────────────────────────────────────────────────"

character = Character.create!(
  blizzard_id:    234_567_890,
  region:         "us",
  realm:          "tichondrius",
  name:           "Valdris",
  faction:        :horde,
  class_id:       1, # Warrior
  class_slug:     "warrior",
  race_id:        2,
  race:           "orc",
  is_private:     false,
  meta_synced_at: Time.current
)
puts "  #{character.display_name} (#{character.region.upcase})"

puts "── Character Items ──────────────────────────────────────────"

# character_id + slot is UNIQUE — one item per slot per character.
# enchantment   → FK to enchantments (optional)
# enchantment_source_item → FK to items; the scroll used to apply the enchant (optional)
# sockets       → JSONB array of { type, item_id } where item_id → items.id

CharacterItem.create!(
  character:  character,
  item:       items[:head],
  slot:       "head",
  item_level: 639,
  context:    11,
  bonus_list: [ 10_299, 1_588 ],
  # Head has one prismatic socket — gem item_id is the DB id, not Blizzard id.
  sockets:    [ { "type" => "PRISMATIC", "item_id" => socket_gem.id } ]
)

CharacterItem.create!(
  character:  character,
  item:       items[:neck],
  slot:       "neck",
  item_level: 639,
  bonus_list: [ 10_299 ]
)

CharacterItem.create!(
  character:  character,
  item:       items[:shoulder],
  slot:       "shoulder",
  item_level: 639,
  bonus_list: [ 10_299 ]
)

CharacterItem.create!(
  character:   character,
  item:        items[:back],
  slot:        "back",
  item_level:  639,
  # Cloak enchant — no source item tracked for this slot
  enchantment: enchantments[:cloak]
)

CharacterItem.create!(
  character:   character,
  item:        items[:chest],
  slot:        "chest",
  item_level:  639,
  enchantment: enchantments[:chest]
)

CharacterItem.create!(
  character:   character,
  item:        items[:wrist],
  slot:        "wrist",
  item_level:  639,
  enchantment: enchantments[:wrist]
)

CharacterItem.create!(
  character:  character,
  item:       items[:hands],
  slot:       "hands",
  item_level: 639,
  bonus_list: [ 10_299 ]
)

CharacterItem.create!(
  character:  character,
  item:       items[:waist],
  slot:       "waist",
  item_level: 639,
  # Belt has a prismatic socket
  sockets:    [ { "type" => "PRISMATIC", "item_id" => socket_gem.id } ]
)

CharacterItem.create!(
  character:   character,
  item:        items[:legs],
  slot:        "legs",
  item_level:  639,
  enchantment: enchantments[:legs]
)

CharacterItem.create!(
  character:  character,
  item:       items[:feet],
  slot:       "feet",
  item_level: 639,
  bonus_list: [ 10_299 ]
)

CharacterItem.create!(
  character:   character,
  item:        items[:finger_1],
  slot:        "finger_1",
  item_level:  639,
  enchantment: enchantments[:ring]
)

CharacterItem.create!(
  character:   character,
  item:        items[:finger_2],
  slot:        "finger_2",
  item_level:  639,
  enchantment: enchantments[:ring]
)

CharacterItem.create!(
  character:  character,
  item:       items[:trinket_1],
  slot:       "trinket_1",
  item_level: 639,
  bonus_list: [ 10_299 ]
)

CharacterItem.create!(
  character:  character,
  item:       items[:trinket_2],
  slot:       "trinket_2",
  item_level: 639,
  bonus_list: [ 10_299 ]
)

CharacterItem.create!(
  character:               character,
  item:                    items[:main_hand],
  slot:                    "main_hand",
  item_level:              639,
  enchantment:             enchantments[:weapon],
  # source_item is the scroll used — tracked from the raw Blizzard API enchantment block
  enchantment_source_item: enc_source,
  embellishment_spell_id:  441_494,
  bonus_list:              [ 10_299 ]
)

puts "  #{character.character_items.count} slots equipped"

puts "── Character Talents ────────────────────────────────────────"

# character_id + talent_id is UNIQUE.
# talent_type is denormalized on the join so we can query by type without joining talents.
# slot_number is only set for pvp talents (Blizzard numbers them from 2).

class_talents.each do |talent|
  CharacterTalent.create!(character: character, talent: talent, talent_type: "class", rank: 1)
end

spec_talents.each do |talent|
  CharacterTalent.create!(character: character, talent: talent, talent_type: "spec", rank: 1)
end

hero_talents.each do |talent|
  CharacterTalent.create!(character: character, talent: talent, talent_type: "hero", rank: 1)
end

pvp_talents.each_with_index do |talent, idx|
  CharacterTalent.create!(
    character:   character,
    talent:      talent,
    talent_type: "pvp",
    rank:        1,
    slot_number: idx + 2 # Blizzard pvp slots start at 2
  )
end

puts "  #{character.character_talents.count} talents linked (class/spec/hero/pvp)"

puts "── PvP Leaderboard Entry ─────────────────────────────────────"

# raw_equipment and raw_specialization mirror the Blizzard API payload shape.
# CompressedJson compresses them transparently on write (~60% smaller).
# These are what UpsertFromRawEquipmentService / UpsertFromRawSpecializationService consume.

raw_equipment = {
  "equipped_items" => SLOT_ITEMS.map do |slot, (blizzard_id, name, quality, inv_type, item_class, item_subclass)|
    {
      "item" => { "id" => blizzard_id },
      "slot" => { "type" => slot.to_s.upcase },
      "level" => { "value" => 639 },
      "name" => name,
      "quality" => { "type" => quality.upcase },
      "context" => 11,
      "bonus_list" => [ 10_299 ],
      "inventory_type" => { "type" => inv_type.upcase },
      "item_class" => { "name" => item_class },
      "item_subclass" => { "name" => item_subclass },
      "media" => { "id" => blizzard_id }
    }
  end
}

raw_specialization = {
  "class_talents" => [
    { "id" => 188_076, "name" => "Heroic Leap", "rank" => 1 },
    { "id" => 197_930, "name" => "Battle Stance",      "rank" => 1 },
    { "id" => 188_082, "name" => "Spell Reflection",   "rank" => 1 },
    { "id" => 262_161, "name" => "War Machine",         "rank" => 1 },
    { "id" => 206_333, "name" => "Enduring Alacrity",   "rank" => 1 }
  ],
  "spec_talents" => [
    { "id" => 260_708, "name" => "Mortal Strike", "rank" => 1 },
    { "id" => 260_709, "name" => "Overpower",        "rank" => 1 },
    { "id" => 260_710, "name" => "Slam",             "rank" => 1 },
    { "id" => 260_711, "name" => "Bladestorm",       "rank" => 1 },
    { "id" => 260_712, "name" => "Colossus Smash",   "rank" => 1 },
    { "id" => 260_713, "name" => "Warbreaker",       "rank" => 1 }
  ],
  "hero_talents" => [
    { "id" => 453_288, "name" => "Colossal Might", "rank" => 1 },
    { "id" => 453_289, "name" => "Boneshaker",      "rank" => 1 },
    { "id" => 453_290, "name" => "Mountain Thane",  "rank" => 1 }
  ],
  # pvp_talents use the nested selected/spell_tooltip structure from the Blizzard API
  "pvp_talents" => [
    { "selected" => { "talent" => { "id" => 202_751, "name" => "Sharpen Blade"  },
                      "spell_tooltip" => { "spell" => { "id" => 202_751 } } } },
    { "selected" => { "talent" => { "id" => 202_573, "name" => "Death Sentence" },
                      "spell_tooltip" => { "spell" => { "id" => 12_294 } } } },
    { "selected" => { "talent" => { "id" => 236_289, "name" => "Disarm"         },
                      "spell_tooltip" => { "spell" => { "id" => 236_077 } } } }
  ]
}

entry = PvpLeaderboardEntry.create!(
  pvp_leaderboard:             leaderboard,
  character:                   character,
  rank:                        1,
  rating:                      2_847,
  wins:                        312,
  losses:                      198,
  spec_id:                     71, # Arms Warrior spec ID
  item_level:                  639,
  hero_talent_tree_id:         2_860,
  hero_talent_tree_name:       "Colossus",
  tier_4p_active:              false,
  snapshot_at:                 Time.current,
  equipment_processed_at:      Time.current,
  specialization_processed_at: Time.current,
  raw_equipment:               raw_equipment,
  raw_specialization:          raw_specialization
)

puts "  entry ##{entry.id} rank=#{entry.rank} rating=#{entry.rating} winrate=#{entry.winrate.round(1)}%"
puts "  raw_equipment compressed: #{entry.raw_equipment_compressed?}"

puts ""
puts "── Summary ──────────────────────────────────────────────────"
puts "  PvpSeason:         #{PvpSeason.count}"
puts "  PvpLeaderboard:    #{PvpLeaderboard.count}"
puts "  PvpLeaderboardEntry: #{PvpLeaderboardEntry.count}"
puts "  Character:         #{Character.count}"
puts "  Item:              #{Item.count}  (#{SLOT_ITEMS.count} slots + 1 gem + 1 scroll)"
puts "  Enchantment:       #{Enchantment.count}"
puts "  Talent:            #{Talent.count}  (#{class_talents.count} class / " \
     "#{spec_talents.count} spec / #{hero_talents.count} hero / #{pvp_talents.count} pvp)"
puts "  CharacterItem:     #{CharacterItem.count}"
puts "  CharacterTalent:   #{CharacterTalent.count}"
puts "  Translation:       #{Translation.count}"
puts "─────────────────────────────────────────────────────────────"
