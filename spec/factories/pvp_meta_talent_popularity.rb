FactoryBot.define do
  factory :pvp_meta_talent_popularity do
    pvp_season
    talent
    bracket     { "2v2" }
    spec_id     { 71 }
    talent_type { "spec" }
    usage_count { 50 }
    usage_pct   { 50.0 }
    in_top_build { true }
    top_build_rank { 1 }
    tier        { "bis" }
    snapshot_at { Time.current }
  end
end
