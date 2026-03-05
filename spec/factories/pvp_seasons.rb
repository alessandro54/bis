# == Schema Information
#
# Table name: pvp_seasons
# Database name: primary
#
#  id           :bigint           not null, primary key
#  display_name :string
#  end_time     :datetime
#  is_current   :boolean          default(FALSE)
#  start_time   :datetime
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  blizzard_id  :integer
#
# Indexes
#
#  index_pvp_seasons_on_blizzard_id  (blizzard_id) UNIQUE
#  index_pvp_seasons_on_is_current   (is_current)
#  index_pvp_seasons_on_updated_at   (updated_at)
#
FactoryBot.define do
  factory :pvp_season do
    sequence(:blizzard_id) { |n| n }
    display_name { "Season Test" }
    is_current   { false }
    start_time   { Time.current - 30.days }
    end_time     { Time.current + 30.days }
  end
end
