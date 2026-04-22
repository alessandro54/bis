# == Schema Information
#
# Table name: pvp_meta_talent_popularity
# Database name: primary
#
#  id                :bigint           not null, primary key
#  bracket           :string           not null
#  in_top_build      :boolean          default(FALSE), not null
#  snapshot_at       :datetime         not null
#  talent_type       :string           not null
#  tier              :string           default("common"), not null
#  top_build_rank    :integer          default(0), not null
#  usage_count       :integer          default(0), not null
#  usage_pct         :decimal(8, 4)
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  pvp_season_id     :bigint           not null
#  pvp_sync_cycle_id :bigint
#  spec_id           :integer          not null
#  talent_id         :bigint           not null
#
# Indexes
#
#  idx_meta_talent_lookup                                 (pvp_season_id,bracket,spec_id,talent_type)
#  idx_meta_talent_unique_cycle                           (pvp_sync_cycle_id,bracket,spec_id,talent_id) UNIQUE WHERE (pvp_sync_cycle_id IS NOT NULL)
#  idx_meta_talent_unique_no_cycle                        (pvp_season_id,bracket,spec_id,talent_id) UNIQUE WHERE (pvp_sync_cycle_id IS NULL)
#  index_pvp_meta_talent_popularity_on_pvp_season_id      (pvp_season_id)
#  index_pvp_meta_talent_popularity_on_pvp_sync_cycle_id  (pvp_sync_cycle_id)
#  index_pvp_meta_talent_popularity_on_talent_id          (talent_id)
#
# Foreign Keys
#
#  fk_rails_...  (pvp_season_id => pvp_seasons.id)
#  fk_rails_...  (pvp_sync_cycle_id => pvp_sync_cycles.id)
#  fk_rails_...  (talent_id => talents.id)
#
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
