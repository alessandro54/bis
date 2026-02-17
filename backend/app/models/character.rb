# == Schema Information
#
# Table name: characters
# Database name: primary
#
#  id                         :bigint           not null, primary key
#  avatar_url                 :string
#  class_slug                 :string
#  equipment_fingerprint      :string
#  faction                    :integer
#  inset_url                  :string
#  is_private                 :boolean          default(FALSE)
#  last_equipment_snapshot_at :datetime
#  main_raw_url               :string
#  meta_synced_at             :datetime
#  name                       :string
#  race                       :string
#  realm                      :string
#  region                     :string
#  talent_loadout_code        :string
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  blizzard_id                :bigint
#  class_id                   :bigint
#  race_id                    :integer
#
# Indexes
#
#  index_characters_on_blizzard_id_and_region     (blizzard_id,region) UNIQUE
#  index_characters_on_equipment_fingerprint      (equipment_fingerprint)
#  index_characters_on_is_private                 (is_private) WHERE (is_private = true)
#  index_characters_on_name_and_realm_and_region  (name,realm,region)
#  index_characters_on_talent_loadout_code        (talent_loadout_code)
#
class Character < ApplicationRecord
  has_many :character_talents, dependent: :delete_all
  has_many :talents, through: :character_talents
  has_many :character_items, dependent: :delete_all
  has_many :items, through: :character_items

  validates :name, :realm, :region, presence: true
  validates :name, uniqueness: { scope: %i[realm region] }

  validates :blizzard_id,
            uniqueness:   { scope: :region },
            numericality: { only_integer: true }

  enum :faction, {
    alliance: 0,
    horde:    1
  }

  def enqueue_sync_meta_job
    return if meta_synced?

    Characters::SyncCharacterJob
      .set(queue: Characters::SyncCharacterJob.queue_for(id))
      .perform_later(
        region:,
        realm:,
        name:
      )
  end

  def display_name
    "#{name.capitalize}-#{realm.capitalize}"
  end

  def meta_synced?
    meta_synced_at&.> 1.week.ago
  end
end
