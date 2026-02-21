# == Schema Information
#
# Table name: characters
# Database name: primary
#
#  id                         :bigint           not null, primary key
#  avatar_url                 :string
#  class_slug                 :string
#  equipment_fingerprint      :string
#  faction                    :integer
#  inset_url                  :string
#  is_private                 :boolean          default(FALSE)
#  last_equipment_snapshot_at :datetime
#  main_raw_url               :string
#  meta_synced_at             :datetime
#  name                       :string
#  race                       :string
#  realm                      :string
#  region                     :string
#  talent_loadout_code        :string
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  blizzard_id                :bigint
#  class_id                   :bigint
#  race_id                    :integer
#
# Indexes
#
#  index_characters_on_blizzard_id_and_region     (blizzard_id,region) UNIQUE
#  index_characters_on_equipment_fingerprint      (equipment_fingerprint)
#  index_characters_on_is_private                 (is_private) WHERE (is_private = true)
#  index_characters_on_name_and_realm_and_region  (name,realm,region)
#  index_characters_on_talent_loadout_code        (talent_loadout_code)
#
class Character < ApplicationRecord
  has_many :character_talents, dependent: :delete_all
  has_many :talents, through: :character_talents
  has_many :character_items, dependent: :delete_all
  has_many :items, through: :character_items

  validates :name, :realm, :region, presence: true
  validates :name, uniqueness: { scope: %i[realm region] }

  validates :blizzard_id,
            uniqueness:   { scope: :region },
            numericality: { only_integer: true }

  enum :faction, {
    alliance: 0,
    horde:    1
  }

  def enqueue_sync_meta_job
    return if meta_synced?

    Characters::SyncCharacterJob
      .set(queue: Characters::SyncCharacterJob.queue_for(id))
      .perform_later(
        region:,
        realm:,
        name:
      )
  end

  def display_name
    "#{name.capitalize}-#{realm.capitalize}"
  end

  def meta_synced?
    meta_synced_at&.> 1.week.ago
  end

  # Prints the full equipment loadout to stdout.
  # Example:
  #   character.print_loadout
  def print_loadout
    slots = character_items
      .includes(item: :translations, enchantment: :translations, enchantment_source_item: :translations)
      .order(:slot)
      .to_a

    avg_ilvl = slots.any? ? (slots.sum(&:item_level).to_f / slots.size).round : 0

    socket_item_ids = slots.flat_map { |ci| Array(ci.sockets).filter_map { |s| s["item_id"] } }.uniq
    gems_by_id = Item.includes(:translations).where(id: socket_item_ids).index_by(&:id)

    puts "#{dim}┌─#{reset} #{bold}#{display_name}#{reset} #{dim}(#{region.upcase}) ─ Loadout#{reset}"
    puts "#{dim}│#{reset} #{slots.size} slots  ·  avg ilvl #{bold}#{avg_ilvl}#{reset}"
    puts dim("├" + "─" * 64)

    slots.each do |ci|
      item_name = ci.item.t("name", locale: "en_US") || "?"
      label     = dim(ci.slot.upcase.ljust(10))
      colored   = quality_color(ci.item.quality) + item_name + reset

      puts "#{dim}│#{reset}  #{label}  #{cyan}[#{ci.item_level}]#{reset}  #{colored}"

      if ci.enchantment
        enc_name = ci.enchantment.t("name", locale: "en_US") || "?"
        source   = ci.enchantment_source_item ? "  #{dim}(#{ci.enchantment_source_item.t('name', locale: 'en_US')})#{reset}" : ""
        puts "#{dim}│#{reset}             #{teal}✦ #{enc_name}#{reset}#{source}"
      end

      Array(ci.sockets).each do |socket|
        gem_name = gems_by_id[socket["item_id"]]&.t("name", locale: "en_US") || "empty"
        puts "#{dim}│#{reset}             #{cyan}◈ #{socket['type']}  #{gem_name}#{reset}"
      end
    end

    puts dim("└" + "─" * 64)
    nil
  end

  def print_talents
    all = character_talents
      .includes(talent: :translations)
      .order(:talent_type, :slot_number, :id)

    by_type = all.group_by(&:talent_type)

    puts "#{dim}┌─#{reset} #{bold}#{display_name}#{reset} #{dim}(#{region.upcase}) ─ Talents#{reset}"

    %w[class spec hero pvp].each do |type|
      entries = by_type[type]
      next unless entries&.any?

      color = TALENT_TYPE_COLORS[type]
      puts "#{dim}├─#{reset} #{color}#{bold}#{type.upcase}#{reset}"

      entries.each do |ct|
        talent_name = ct.talent.t("name", locale: "en_US") || "?"
        rank_str    = ct.rank > 1 ? " #{dim}(rank #{ct.rank})#{reset}" : ""
        slot_str    = ct.slot_number ? "  #{dim}[slot #{ct.slot_number}]#{reset}" : ""
        puts "#{dim}│#{reset}    #{color}#{talent_name}#{reset}#{rank_str}#{slot_str}"
      end
    end

    puts dim("└" + "─" * 64)
    nil
  end

  private

    # ── ANSI helpers ──────────────────────────────────────────────────────
    def reset  = "\e[0m"
    def bold   = "\e[1m"
    def dim(s = nil) = s ? "\e[2m#{s}\e[0m" : "\e[2m"
    def cyan   = "\e[36m"
    def teal   = "\e[38;5;73m"

    TALENT_TYPE_COLORS = {
      "class" => "\e[33m",  # yellow
      "spec"  => "\e[36m",  # cyan
      "hero"  => "\e[35m",  # magenta
      "pvp"   => "\e[31m"   # red
    }.freeze

    QUALITY_COLORS = {
      "legendary" => "\e[38;5;208m",  # orange
      "epic"      => "\e[35m",         # purple
      "rare"      => "\e[34m",         # blue
      "uncommon"  => "\e[32m",         # green
      "common"    => "\e[37m",         # white
      "poor"      => "\e[90m"          # dark gray
    }.freeze

    def quality_color(quality)
      QUALITY_COLORS[quality.to_s.downcase] || "\e[37m"
    end
end
