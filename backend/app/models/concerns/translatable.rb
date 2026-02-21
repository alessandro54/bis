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
  end

  def t(key, locale: I18n.locale, fallback: nil)
    rec = translations.find { |tr| tr.locale == locale.to_s && tr.key == key.to_s }
    rec ||= translations.for_locale(locale).find_by(key: key) if !association(:translations).loaded?

    return rec&.value if rec

    fallback
  end

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

  def inspect
    name_translation = t("name", locale: "en_US")
    return super unless name_translation

    super.sub(/^#<#{self.class.name}/, "#<#{self.class.name}[#{name_translation}]")
  end
end
