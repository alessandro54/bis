class Avo::TranslationHealthController < Avo::ApplicationController
  SECTIONS = [
    { label: "Items & Gems", type: "Item" },
    { label: "Enchantments", type: "Enchantment" },
    { label: "Talents",      type: "Talent" }
  ].freeze

  def show
    @season   = PvpSeason.current
    @sections = @season ? SECTIONS.map { |s| build_section(s, @season) } : []
  end

  def backfill
    force = params[:force] == "true"
    EnsureMetaTranslationsJob.perform_later(force: force)
    redirect_to avo.translation_health_path,
                notice: "Backfill job enqueued#{' (force mode)' if force}"
  end

  private

    def build_section(config, season)
      ids     = meta_ids_for(config[:type], season)
      locales = Wow::Locales::SUPPORTED_LOCALES.map { |locale| locale_stats(config[:type], ids, locale) }
      { label: config[:label], total: ids.size, locales: locales }
    end

    def meta_ids_for(type, season)
      case type
      when "Item"
        (PvpMetaItemPopularity.where(pvp_season: season).distinct.pluck(:item_id) +
         PvpMetaGemPopularity.where(pvp_season: season).distinct.pluck(:item_id)).uniq
      when "Enchantment"
        PvpMetaEnchantPopularity.where(pvp_season: season).distinct.pluck(:enchantment_id)
      when "Talent"
        PvpMetaTalentPopularity.where(pvp_season: season).distinct.pluck(:talent_id)
      end
    end

    def locale_stats(type, ids, locale)
      present = ids.empty? ? 0 : Translation
        .where(translatable_type: type, translatable_id: ids, locale: locale, key: "name")
        .count
      missing = ids.size - present
      pct     = ids.size > 0 ? (present.to_f / ids.size * 100).round(1) : 100.0

      { locale: locale, present: present, missing: missing, pct: pct }
    end
end
