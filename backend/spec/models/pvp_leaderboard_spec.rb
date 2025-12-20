require 'rails_helper'

RSpec.describe PvpLeaderboard, type: :model do
  describe 'associations' do
    it { should belong_to(:pvp_season) }
  end

  describe 'database constraints' do
    it 'enforces unique pvp_season_id and bracket combination' do
      season = create(:pvp_season)
      create(:pvp_leaderboard, pvp_season: season, bracket: '2v2')

      expect {
        create(:pvp_leaderboard, pvp_season: season, bracket: '2v2')
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows the same bracket for different seasons' do
      season1 = create(:pvp_season)
      season2 = create(:pvp_season)

      create(:pvp_leaderboard, pvp_season: season1, bracket: '2v2')
      new_leaderboard = build(:pvp_leaderboard, pvp_season: season2, bracket: '2v2')

      expect(new_leaderboard).to be_valid
    end
  end

  describe 'attributes' do
    let(:leaderboard) { build(:pvp_leaderboard) }

    it 'can store bracket' do
      leaderboard.bracket = '3v3'
      expect(leaderboard.bracket).to eq('3v3')
    end

    it 'can store region' do
      leaderboard.region = 'us'
      expect(leaderboard.region).to eq('us')
    end

    it 'can store last_synced_at' do
      time = 1.hour.ago
      leaderboard.last_synced_at = time
      expect(leaderboard.last_synced_at).to eq(time)
    end
  end

  describe 'valid brackets' do
    let(:season) { create(:pvp_season) }

    it 'accepts valid bracket types' do
      valid_brackets = [ '2v2', '3v3', 'rbg', 'shuffle' ]

      valid_brackets.each do |bracket|
        leaderboard = build(:pvp_leaderboard, pvp_season: season, bracket: bracket)
        expect(leaderboard).to be_valid
      end
    end
  end

  describe 'valid regions' do
    let(:season) { create(:pvp_season) }

    it 'accepts valid region codes' do
      valid_regions = [ 'us', 'eu', 'kr', 'tw', 'cn' ]

      valid_regions.each do |region|
        leaderboard = build(:pvp_leaderboard, pvp_season: season, region: region)
        expect(leaderboard).to be_valid
      end
    end
  end

  describe 'timestamps' do
    let(:leaderboard) { create(:pvp_leaderboard) }

    it 'sets created_at automatically' do
      expect(leaderboard.created_at).to be_within(5.seconds).of(Time.current)
    end

    it 'sets updated_at automatically' do
      expect(leaderboard.updated_at).to be_within(5.seconds).of(Time.current)
    end

    it 'updates updated_at on save' do
      original_updated_at = leaderboard.updated_at
      # Force a timestamp change by updating an attribute
      leaderboard.update!(bracket: '3v3')
      leaderboard.reload

      expect(leaderboard.updated_at).to be > original_updated_at
    end
  end

  describe 'last_synced_at functionality' do
    let(:leaderboard) { create(:pvp_leaderboard, last_synced_at: nil) }

    it 'can be nil initially' do
      expect(leaderboard.last_synced_at).to be_nil
    end

    it 'can be updated to a timestamp' do
      sync_time = Time.current
      leaderboard.update!(last_synced_at: sync_time)

      expect(leaderboard.last_synced_at).to be_within(1.second).of(sync_time)
    end
  end
end
