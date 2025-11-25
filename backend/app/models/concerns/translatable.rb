module Translatable
  extend ActiveSupport::Concern

  included do
    has_many :translations,
             as:         :translatable,
             dependent:  :destroy,
             inverse_of: :translatable
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
    record.meta  = meta if meta.present?
    record.save!
    record
  end

  def translations_for(locale = I18n.locale)
    translations.for_locale(locale.to_s).pluck(:key, :value).to_h
  end
end
