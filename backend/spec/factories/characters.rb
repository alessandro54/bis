# == Schema Information
#
# Table name: characters
# Database name: primary
#
#  id           :bigint           not null, primary key
#  avatar_url   :string
#  class_slug   :string
#  faction      :integer
#  inset_url    :string
#  is_private   :boolean          default(FALSE)
#  main_raw_url :string
#  name         :string
#  race         :string
#  realm        :string
#  region       :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  blizzard_id  :bigint
#  class_id     :string
#  race_id      :integer
#
# Indexes
#
#  index_characters_on_blizzard_id_and_region     (blizzard_id,region) UNIQUE
#  index_characters_on_name_and_realm_and_region  (name,realm,region)
#
FactoryBot.define do
  factory :character do
    name       { Faker::Name.middle_name }
    realm      { Faker::Games::WorldOfWarcraft.hero.split(" ").first.downcase }
    region     { %w[us eu kr tw].sample }
    race       { Faker::Games::WorldOfWarcraft.race.downcase }
    class_slug { Faker::Games::WorldOfWarcraft.class_name.downcase }
    blizzard_id { Faker::Number.number(digits: 8).to_s }
    faction { [ 0, 1 ].sample }
  end
end
