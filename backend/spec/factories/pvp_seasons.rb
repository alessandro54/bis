FactoryBot.define do
  factory :pvp_season do
    display_name { "Season Test" }
    blizzard_id  { "40" }
    is_current   { true }
    start_time   { Time.current - 30.days }
    end_time     { Time.current + 30.days }
  end
end