# == Schema Information
#
# Table name: pvp_leaderboards.rb
#
#  id             :bigint           not null, primary key
#  bracket        :string
#  last_synced_at :datetime
#  region         :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  pvp_season_id  :bigint           not null
#
# Indexes
#
#  index_pvp_leaderboards_on_pvp_season_id              (pvp_season_id)
#  index_pvp_leaderboards_on_pvp_season_id_and_bracket  (pvp_season_id,bracket) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (pvp_season_id => pvp_seasons.id)
#
require 'rails_helper'

RSpec.describe PvpLeaderboard, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
