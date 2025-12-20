# == Schema Information
#
# Table name: translations
# Database name: primary
#
#  id                :bigint           not null, primary key
#  key               :string           not null
#  locale            :string           not null
#  meta              :jsonb            not null
#  translatable_type :string           not null
#  value             :text             not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  translatable_id   :bigint           not null
#
# Indexes
#
#  index_translations_on_key                              (key)
#  index_translations_on_locale                           (locale)
#  index_translations_on_translatable                     (translatable_type,translatable_id)
#  index_translations_on_translatable_and_locale_and_key  (translatable_type,translatable_id,locale,key) UNIQUE
#
class Translation < ApplicationRecord
  belongs_to :translatable, polymorphic: true

  validates :locale, :key, :value, :meta, presence: true

  scope :for_locale, ->(locale) { where(locale:) }
  scope :for_key,    ->(key)    { where(key:) }
  scope :for_translatable, ->(translatable) {
    where(translatable_type: translatable.class.name, translatable_id: translatable.id)
  }

  # Class methods for bulk operations
  def self.set_translation(translatable, key, locale, value, meta: {})
    find_or_initialize_by(
      translatable: translatable,
      locale:       locale.to_s,
      key:          key.to_s
    ).tap do |record|
      record.value = value
      record.meta = meta if meta.present?
      record.save!
    end
  end

  def self.get_translation(translatable, key, locale: I18n.locale)
    find_by(
      translatable: translatable,
      locale:       locale.to_s,
      key:          key.to_s
    )&.value
  end
end
