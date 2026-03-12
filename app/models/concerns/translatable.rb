module Translatable
  extend ActiveSupport::Concern

  included do
    has_many :translations,
             as:         :translatable,
             dependent:  :destroy,
             inverse_of: :translatable

    scope :with_translations, ->(*locales) {
      rel = includes(:translations)
      locales.any? ? rel.where(translations: { locale: locales }) : rel
    }
  end

  class_methods do
    # Item.translations, Talent.translations, Enchantment.translations
    def translations
      Translation.where(translatable_type: name)
    end

    # Declares locale-aware accessor methods for translation keys.
    #
    #   translation_accessor :name, :description
    #
    # Generates methods that accept an optional locale: keyword:
    #   item.name              # => { "en_US" => "...", "es_MX" => "..." }
    #   item.name(locale: "es_MX")  # => "..."
    def translation_accessor(*keys)
      keys.each do |key|
        define_method(key) do |locale: nil|
          locale ? t(key, locale: locale) : t_map(key)
        end
      end
    end
  end

  # rubocop:disable Metrics/AbcSize
  def t(key, locale: I18n.locale, fallback: nil)
    locale_s = locale.to_s
    rec = translations.find { |tr| tr.locale == locale_s && tr.key == key.to_s }
    rec ||= translations.for_locale(locale_s).find_by(key: key) if !association(:translations).loaded?
    return rec.value if rec

    if locale_s != "en_US"
      fallback_rec = translations.find { |tr| tr.locale == "en_US" && tr.key == key.to_s }
      fallback_rec ||= translations.for_locale("en_US").find_by(key: key) if !association(:translations).loaded?
      return fallback_rec.value if fallback_rec
    end

    fallback
  end
  # rubocop:enable Metrics/AbcSize

  def set_translation(key, locale, value, meta: {})
    record = translations.find_or_initialize_by(
      locale: locale.to_s,
      key:    key.to_s
    )

    record.value = value
    record.meta  = meta
    record.save!
    record
  end

  def translations_for(locale = I18n.locale)
    translations.for_locale(locale.to_s).pluck(:key, :value).to_h
  end

  def t_map(key)
    if association(:translations).loaded?
      translations.select { |tr| tr.key == key.to_s }.to_h { |tr| [ tr.locale, tr.value ] }
    else
      translations.for_key(key).pluck(:locale, :value).to_h
    end
  end

  def inspect
    name_translation = t("name", locale: "en_US")
    return super unless name_translation

    super.sub(/^#<#{self.class.name}/, "#<#{self.class.name}[#{name_translation}]")
  end
end
