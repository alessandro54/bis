class Character::TalentPrinter
  TALENT_TYPE_COLORS = {
    "class" => "\e[33m", # yellow
    "spec" => "\e[36m",  # cyan
    "hero" => "\e[35m",  # magenta
    "pvp" => "\e[31m" # red
  }.freeze

  def self.call(character) = new(character).call

  def initialize(character)
    @character = character
  end

  def call
    all = @character.character_talents
      .includes(talent: :translations)
      .order(:talent_type, :slot_number, :id)

    by_type = all.group_by(&:talent_type)

    puts "#{dim}┌─#{reset} #{bold}#{@character.display_name}#{reset} #{dim}(#{@character.region.upcase}) ─ Talents#{reset}"

    %w[class spec hero pvp].each do |type|
      entries = by_type[type]
      next unless entries&.any?

      color = TALENT_TYPE_COLORS[type]
      puts "#{dim}├─#{reset} #{color}#{bold}#{type.upcase}#{reset}"

      entries.each_with_index do |ct, idx|
        connector   = idx == entries.size - 1 ? "└─" : "├─"
        talent_name = ct.talent.t("name", locale: "en_US") || "?"
        rank_str    = ct.rank > 1 ? " #{dim}(rank #{ct.rank})#{reset}" : ""
        slot_str    = ct.slot_number ? "  #{dim}[slot #{ct.slot_number}]#{reset}" : ""
        puts "#{dim}│#{reset}    #{dim}#{connector}#{reset} #{color}#{talent_name}#{reset}#{rank_str}#{slot_str}"
      end
    end

    puts dim("└" + "─" * 64)
    nil
  end

  private

    def reset = "\e[0m"
    def bold  = "\e[1m"
    def dim(s = nil) = s ? "\e[2m#{s}\e[0m" : "\e[2m"
end
