# == Schema Information
#
# Table name: pvp_seasons
# Database name: primary
#
#  id                     :bigint           not null, primary key
#  display_name           :string
#  end_time               :datetime
#  is_current             :boolean          default(FALSE)
#  start_time             :datetime
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  blizzard_id            :integer
#  live_pvp_sync_cycle_id :bigint
#
# Indexes
#
#  index_pvp_seasons_on_blizzard_id             (blizzard_id) UNIQUE
#  index_pvp_seasons_on_is_current              (is_current)
#  index_pvp_seasons_on_live_pvp_sync_cycle_id  (live_pvp_sync_cycle_id)
#  index_pvp_seasons_on_updated_at              (updated_at)
#
# Foreign Keys
#
#  fk_rails_...  (live_pvp_sync_cycle_id => pvp_sync_cycles.id)
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
