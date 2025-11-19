# == Schema Information
#
# Table name: pvp_seasons
#
#  id           :bigint           not null, primary key
#  display_name :string
#  end_time     :datetime
#  is_current   :boolean          default(FALSE)
#  start_time   :datetime
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  blizzard_id  :string
#
# Indexes
#
#  index_pvp_seasons_on_is_current  (is_current)
#  index_pvp_seasons_on_updated_at  (updated_at)
#
require 'rails_helper'

RSpec.describe PvpSeason, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
