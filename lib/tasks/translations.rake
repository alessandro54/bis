namespace :translations do
  desc "Enqueue translation backfill for all meta items, enchantments, and talents (skips already complete)"
  task backfill: :environment do
    EnsureMetaTranslationsJob.perform_later
    puts "Enqueued EnsureMetaTranslationsJob."
  end

  desc "Force re-fetch translations for all meta records in every supported locale (LOCALE=es_MX to target one)"
  task force: :environment do
    EnsureMetaTranslationsJob.perform_later(force: true)
    puts "Enqueued EnsureMetaTranslationsJob (force mode)."
  end

  desc "Backfill talent names/descriptions for a given locale via SyncTalentTreesJob (LOCALE=es_MX)"
  task sync_talent_trees: :environment do
    locale = ENV.fetch("LOCALE", "es_MX")
    SyncTalentTreesJob.perform_later(locale: locale)
    puts "Enqueued SyncTalentTreesJob(locale: #{locale})."
  end

  desc "Print translation coverage for the current meta season"
  task health: :environment do
    season = PvpSeason.current
    abort "No active season found." unless season

    puts "\nTranslation Health — #{season.display_name}"
    puts "Supported locales: #{Wow::Locales::SUPPORTED_LOCALES.join(', ')}\n\n"

    {
      "Items & Gems" => -> {
        (PvpMetaItemPopularity.where(pvp_season: season).distinct.pluck(:item_id) +
         PvpMetaGemPopularity.where(pvp_season: season).distinct.pluck(:item_id)).uniq
      },
      "Enchantments" => -> { PvpMetaEnchantPopularity.where(pvp_season: season).distinct.pluck(:enchantment_id) },
      "Talents" => -> { PvpMetaTalentPopularity.where(pvp_season: season).distinct.pluck(:talent_id) }
    }.each do |label, ids_fn|
      ids  = ids_fn.call
      type = label == "Enchantments" ? "Enchantment" : label == "Talents" ? "Talent" : "Item"

      puts "#{label} (#{ids.size} in meta):"

      Wow::Locales::SUPPORTED_LOCALES.each do |locale|
        present = ids.empty? ? 0 : Translation
          .where(translatable_type: type, translatable_id: ids, locale: locale, key: "name")
          .count
        missing = ids.size - present
        pct     = ids.size > 0 ? (present.to_f / ids.size * 100).round(1) : 100.0
        bar     = ("█" * (pct / 5).round).ljust(20)
        status  = missing.zero? ? "✓" : "✗"

        puts "  #{status} #{locale.ljust(8)} #{bar} #{pct.to_s.rjust(5)}%  " \
             "(#{present}/#{ids.size}, missing: #{missing})"
      end

      puts
    end
  end
end
