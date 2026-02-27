class Character::LoadoutPrinter
  def self.call(character) = new(character).call

  def initialize(character)
    @character = character
  end

  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  def call
    slots = @character.character_items
      .includes(item: :translations, enchantment: :translations, enchantment_source_item: :translations)
      .order(:slot)
      .to_a

    avg_ilvl = slots.any? ? (slots.sum(&:item_level).to_f / slots.size).round : 0

    socket_item_ids = slots.flat_map { |ci| Array(ci.sockets).filter_map { |s| s["item_id"] } }.uniq
    gems_by_id      = Item.includes(:translations).where(id: socket_item_ids).index_by(&:id)

    slot_w = [ slots.map { |ci| ci.slot.upcase.length }.max || 4, 4 ].max

    puts "#{dim}┌─#{reset} #{bold}#{@character.display_name}#{reset} " \
         "#{dim}(#{@character.region.upcase}) ─ Loadout#{reset}"
    puts "#{dim}│#{reset} #{@character.class_slug.upcase}: #{bold}#{@character.class_slug.upcase}#{reset}"
    puts "#{dim}│#{reset} #{slots.size} slots  ·  avg ilvl #{bold}#{avg_ilvl}#{reset}"
    puts dim("├" + "─" * 64)

    slots.each do |ci|
      colored_name = quality_color(ci.item.quality) + (ci.item.t("name", locale: "en_US") || "?") + reset
      puts "#{dim}│#{reset}  #{dim(ci.slot.upcase.ljust(slot_w))}  #{cyan}[#{ci.item_level}]#{reset}  #{colored_name}"

      children = build_children(ci, gems_by_id)
      indent   = " " * (slot_w + 4)
      children.each_with_index do |line, idx|
        connector = idx == children.size - 1 ? "└─" : "├─"
        puts "#{dim}│#{reset}  #{indent}#{dim}#{connector}#{reset} #{line}"
      end
    end

    puts dim("└" + "─" * 64)
    nil
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

  private

    # rubocop:disable Metrics/AbcSize
    def build_children(ci, gems_by_id)
      children = []

      if ci.enchantment
        enc_name = ci.enchantment.t("name", locale: "en_US") || "?"
        source   = ci.enchantment_source_item ? " #{dim}(#{ci.enchantment_source_item.t('name',
locale: 'en_US')})#{reset}" : ""
        children << "#{teal}✦ #{enc_name}#{reset}#{source}"
      end

      Array(ci.sockets).each do |socket|
        gem_name = gems_by_id[socket["item_id"]]&.t("name", locale: "en_US") || "empty"
        children << "#{cyan}◈ #{socket['type']}  #{gem_name}#{reset}"
      end

      children
    end
    # rubocop:enable Metrics/AbcSize

    def reset  = "\e[0m"
    def bold   = "\e[1m"
    def dim(s = nil) = s ? "\e[2m#{s}\e[0m" : "\e[2m"
    def cyan   = "\e[36m"
    def teal   = "\e[38;5;73m"

    QUALITY_COLORS = {
      "legendary" => "\e[38;5;208m",
      "epic" => "\e[35m",
      "rare" => "\e[34m",
      "uncommon" => "\e[32m",
      "common" => "\e[37m",
      "poor" => "\e[90m"
    }.freeze

    def quality_color(quality)
      QUALITY_COLORS[quality.to_s.downcase] || "\e[37m"
    end
end
