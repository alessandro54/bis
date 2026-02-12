# == Schema Information
#
# Table name: pvp_meta_talent_picks
# Database name: primary
#
#  id            :bigint           not null, primary key
#  avg_rating    :decimal(7, 2)
#  bracket       :string           not null
#  pick_rate     :decimal(5, 4)
#  snapshot_at   :datetime         not null
#  talent_type   :string           not null
#  usage_count   :integer          default(0), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  pvp_season_id :bigint           not null
#  spec_id       :integer          not null
#  talent_id     :bigint           not null
#
# Indexes
#
#  idx_talent_picks_lookup                       (pvp_season_id,bracket,spec_id,talent_type)
#  index_pvp_meta_talent_picks_on_pvp_season_id  (pvp_season_id)
#  index_pvp_meta_talent_picks_on_talent_id      (talent_id)
#
# Foreign Keys
#
#  fk_rails_...  (pvp_season_id => pvp_seasons.id)
#  fk_rails_...  (talent_id => talents.id)
#
class PvpMetaTalentPick < ApplicationRecord
  belongs_to :pvp_season
  belongs_to :talent
end
