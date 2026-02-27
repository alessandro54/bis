class Character::SyncStatusPrinter
  def self.call(character) = new(character).call

  def initialize(character)
    @character = character
  end

  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  def call
    c = @character

    entries = PvpLeaderboardEntry
      .joins(:pvp_leaderboard)
      .where(character_id: c.id)
      .select("pvp_leaderboard_entries.*, pvp_leaderboards.bracket")
      .order(snapshot_at: :desc)
      .limit(10)

    puts "#{dim}┌─#{reset} #{bold}#{c.display_name}#{reset} #{dim}(#{c.region.upcase}) — Sync Status#{reset}"
    puts "#{dim}│#{reset}"

    # Identity
    row "ID",          c.id
    row "Private",     c.is_private ? "#{red}yes#{reset}" : "no"
    row "Fingerprint",
c.equipment_fingerprint.present? ? dim(c.equipment_fingerprint[0, 40] + "…") : "#{red}none#{reset}"

    # Snapshot timestamps
    puts "#{dim}│#{reset}"
    row "Last equipment snapshot", fmt_time(c.last_equipment_snapshot_at)
    row "Meta synced at",          fmt_time(c.meta_synced_at)

    # Items / talents in DB
    puts "#{dim}│#{reset}"
    item_count   = c.character_items.count
    talent_count = c.character_talents.count
    row "character_items",   item_count.zero?   ? "#{red}0 ← never processed#{reset}" : item_count
    row "character_talents", talent_count.zero? ? "#{yellow}0#{reset}" : talent_count

    # PvP entries
    puts "#{dim}│#{reset}"
    if entries.empty?
      row "PvP entries", "#{red}none#{reset}"
    else
      puts "#{dim}│#{reset}  #{bold}PvP entries#{reset} #{dim}(latest 10):#{reset}"
      entries.each do |e|
        eq_ok   = e.equipment_processed_at       ? "#{green}eq ✓#{reset}"   : "#{red}eq ✗#{reset}"
        spec_ok = e.specialization_processed_at  ? "#{green}spec ✓#{reset}" : "#{red}spec ✗#{reset}"
        snap    = e.snapshot_at ? e.snapshot_at.strftime("%m/%d %H:%M") : "?"
        bracket = e.respond_to?(:bracket) ? e.bracket.ljust(20) : "?".ljust(20)

        puts "#{dim}│#{reset}    #{dim}#{bracket}#{reset}  snap #{snap}" \
             "  #{eq_ok}  #{spec_ok}  rating #{bold}#{e.rating}#{reset}"
      end

      puts "#{dim}│#{reset}"
      puts "#{dim}│#{reset}  #{bold}Diagnosis:#{reset}"

      latest = entries.first
      if latest.equipment_processed_at.nil?
        puts "#{dim}│#{reset}    #{red}✗ equipment never processed#{reset}"
        puts "#{dim}│#{reset}      #{dim}→ API unavailable, spec unavailable, or service error#{reset}"
        puts "#{dim}│#{reset}      #{dim}→ retry: result = " \
             "Pvp::Characters::SyncCharacterService.call(character: Character.find(#{c.id}))#{reset}"
        puts "#{dim}│#{reset}      #{dim}         result.context[:status]  " \
             "# :synced / :equipment_unavailable / etc.#{reset}"
        puts "#{dim}│#{reset}      #{dim}         result.error             # exception if failed#{reset}"
      else
        puts "#{dim}│#{reset}    #{green}✓ last entry processed successfully#{reset}"
      end
    end

    puts "#{dim}│#{reset}"
    puts dim("└" + "─" * 64)
    nil
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

  private

    def row(label, value)
      puts "#{dim}│#{reset}  #{dim(label.ljust(26))}  #{value}"
    end

    def fmt_time(t)
      return "#{red}never#{reset}" unless t

      age = (Time.current - t).to_i
      str = t.strftime("%Y-%m-%d %H:%M:%S")
      age < 1.hour   ? "#{green}#{str} (#{age / 60}m ago)#{reset}" :
      age < 24.hours ? "#{yellow}#{str} (#{age / 3600}h ago)#{reset}" :
                       "#{red}#{str} (#{age / 86_400}d ago)#{reset}"
    end

    def reset  = "\e[0m"
    def bold   = "\e[1m"
    def dim(s = nil) = s ? "\e[2m#{s}\e[0m" : "\e[2m"
    def red    = "\e[31m"
    def green  = "\e[32m"
    def yellow = "\e[33m"
end
