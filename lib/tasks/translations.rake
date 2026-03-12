namespace :translations do
  # Runs the full translation pipeline inline (no queue):
  #   1. SyncTalentTreesJob with the target locale — extracts names directly
  #      from the talent tree API response where the individual talent endpoint
  #      doesn't return localized names (e.g. es_MX).
  #   2. EnsureMetaTranslationsJob — fetches item/gem/enchant names via the
  #      Blizzard Item API for all locales missing a "name" translation.
  # Prints a health report when done.
  #
  # Usage:
  #   bundle exec rails translations:sync_all              # es_MX, skip existing
  #   bundle exec rails translations:sync_all FORCE=1      # re-fetch everything
  #   bundle exec rails translations:sync_all LOCALE=fr_FR # different locale
  desc "Run all translation syncs inline: talent trees + item/enchant/gem backfill (FORCE=1 to re-fetch all)"
  task sync_all: :environment do
    force  = ENV["FORCE"] == "1"
    locale = ENV.fetch("LOCALE", "es_MX")

    puts "==> Syncing talent trees (locale: #{locale})..."
    SyncTalentTreesJob.perform_now(locale: locale)
    puts "    Done."

    puts "==> Running translation backfill (force: #{force})..."
    EnsureMetaTranslationsJob.perform_now(force: force)
    puts "    Done."

    Rake::Task["translations:health"].invoke
  end

  # Enqueues EnsureMetaTranslationsJob to fill missing "name" translations for
  # all items, gems, enchantments, and talents referenced in the current season
  # meta. Skips records that already have translations for all supported locales.
  # Jobs run asynchronously via SolidQueue — use sync_all for inline execution.
  desc "Enqueue translation backfill for all meta items, enchantments, and talents (skips already complete)"
  task backfill: :environment do
    EnsureMetaTranslationsJob.perform_later
    puts "Enqueued EnsureMetaTranslationsJob."
  end

  # Like backfill but passes force: true, which re-fetches translations from
  # Blizzard even for records that already have all locales. Use after Blizzard
  # updates names (e.g. item renames, patch localization fixes).
  # Optional: LOCALE=es_MX targets a single locale (not yet implemented in job).
  desc "Force re-fetch translations for all meta records in every supported locale"
  task force: :environment do
    EnsureMetaTranslationsJob.perform_later(force: true)
    puts "Enqueued EnsureMetaTranslationsJob (force mode)."
  end

  # Enqueues SyncTalentTreesJob for the given locale. Talent names are embedded
  # in the talent tree API response — this is the only reliable source for
  # locales like es_MX where the individual /talent/{id} endpoint returns no name.
  #
  # Usage:
  #   bundle exec rails translations:sync_talent_trees              # defaults to es_MX
  #   bundle exec rails translations:sync_talent_trees LOCALE=fr_FR
  desc "Backfill talent names for a given locale via SyncTalentTreesJob (LOCALE=es_MX)"
  task sync_talent_trees: :environment do
    locale = ENV.fetch("LOCALE", "es_MX")
    SyncTalentTreesJob.perform_later(locale: locale)
    puts "Enqueued SyncTalentTreesJob(locale: #{locale})."
  end

  # Queries the translations table against the current season's meta records
  # and prints per-model, per-locale coverage as a progress bar.
  # Models checked: Items & Gems, Enchantments, Talents (key: "name" only).
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
