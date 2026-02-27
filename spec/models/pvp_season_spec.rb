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
require 'rails_helper'

RSpec.describe PvpSeason, type: :model do
  include_examples "has timestamps"
  include TestHelpers
  describe 'associations' do
    it { should have_many(:pvp_leaderboards).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:display_name) }
    it { should validate_presence_of(:blizzard_id) }
    it { should validate_uniqueness_of(:blizzard_id) }
    it { should validate_numericality_of(:blizzard_id).only_integer }
  end

  describe 'database constraints' do
    it 'enforces unique blizzard_id' do
      create(:pvp_season, blizzard_id: 123)

      expect {
        create(:pvp_season, blizzard_id: 123)
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe 'attributes' do
    let(:season) { build(:pvp_season) }

    it 'can store display_name' do
      season.display_name = 'Season 2'
      expect(season.display_name).to eq('Season 2')
    end

    it 'can store blizzard_id' do
      season.blizzard_id = 456
      expect(season.blizzard_id).to eq(456)
    end

    it 'can store start_time' do
      start_time = 1.month.ago
      season.start_time = start_time
      expect_timestamp_within_precision(season.start_time, start_time)
    end

    it 'can store end_time' do
      end_time = 1.month.from_now
      season.end_time = end_time
      expect_timestamp_within_precision(season.end_time, end_time)
    end

    it 'can store is_current' do
      season.is_current = true
      expect(season.is_current).to be true
    end
  end

  describe 'default values' do
    let(:season) { create(:pvp_season) }

    it 'sets default is_current to false' do
      expect(season.is_current).to be false
    end
  end

  describe '.current' do
    context 'when there is a current season' do
      let!(:current_season) { create(:pvp_season, is_current: true) }
      let!(:old_season) { create(:pvp_season, is_current: false, blizzard_id: 1) }

      it 'returns the current season' do
        expect(described_class.current).to eq(current_season)
      end
    end

    context 'when there is no current season' do
      let!(:season1) { create_test_season(is_current: false, blizzard_id: 1) }
      let!(:season2) { create_test_season(is_current: false, blizzard_id: 2) }
      let!(:season3) { create_test_season(is_current: false, blizzard_id: 3) }

      it 'returns the season with highest blizzard_id' do
        expect(described_class.current).to eq(season3)
      end
    end

    context 'when there are no seasons' do
      it 'returns nil' do
        expect(described_class.current).to be_nil
      end
    end

    context 'when there are multiple current seasons (edge case)' do
      let!(:current_season1) { create_test_season(is_current: true, blizzard_id: 1) }
      let!(:current_season2) { create_test_season(is_current: true, blizzard_id: 2) }

      it 'returns the current season (first found)' do
        result = described_class.current
        expect([ current_season1, current_season2 ]).to include(result)
        expect(result.is_current).to be true
      end
    end
  end


  describe 'season duration' do
    let(:season) do
      create_test_season(
        start_time: 2.months.ago,
        end_time:   1.month.from_now
      )
    end

    it 'can have both start_time and end_time' do
      expect(season.start_time).to be_present
      expect(season.end_time).to be_present
      expect(season.start_time).to be < season.end_time
    end

    it 'allows nil start_time' do
      season.update!(start_time: nil)
      expect(season.start_time).to be_nil
    end

    it 'allows nil end_time' do
      season.update!(end_time: nil)
      expect(season.end_time).to be_nil
    end
  end
end
