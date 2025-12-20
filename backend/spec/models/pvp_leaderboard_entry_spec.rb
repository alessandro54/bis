require 'rails_helper'

RSpec.describe PvpLeaderboardEntry, type: :model do
  describe 'associations' do
    it { should belong_to(:pvp_leaderboard) }
    it { should belong_to(:character) }
    it { should have_many(:pvp_leaderboard_entry_items).dependent(:destroy) }
    it { should have_many(:items).through(:pvp_leaderboard_entry_items) }
  end

  describe 'included modules' do
    it 'includes Translatable module' do
      expect(described_class.included_modules).to include(Translatable)
    end
  end

  describe 'filter_attributes' do
    it 'filters sensitive attributes' do
      expect(described_class.filter_attributes).to include(:raw_equipment, :raw_specialization)
    end
  end

  describe '#winrate' do
    context 'with wins and losses' do
      let(:entry) { build(:pvp_leaderboard_entry, wins: 15, losses: 5) }

      it 'calculates winrate correctly' do
        expect(entry.winrate).to eq(75.0)
      end
    end

    context 'with only wins' do
      let(:entry) { build(:pvp_leaderboard_entry, wins: 20, losses: 0) }

      it 'calculates winrate correctly' do
        expect(entry.winrate).to eq(100.0)
      end
    end

    context 'with only losses' do
      let(:entry) { build(:pvp_leaderboard_entry, wins: 0, losses: 10) }

      it 'calculates winrate correctly' do
        expect(entry.winrate).to eq(0.0)
      end
    end

    context 'with no games played' do
      let(:entry) { build(:pvp_leaderboard_entry, wins: 0, losses: 0) }

      it 'returns 0.0' do
        expect(entry.winrate).to eq(0.0)
      end
    end

    context 'with nil values' do
      let(:entry) { build(:pvp_leaderboard_entry, wins: nil, losses: nil) }

      it 'handles nil values gracefully' do
        expect(entry.winrate).to eq(0.0)
      end
    end
  end

  describe 'scopes' do
    describe '.latest_snapshot_for_bracket' do
      let!(:current_season) { create(:pvp_season, is_current: true) }
      let!(:old_season) { create(:pvp_season, is_current: false) }
      let!(:leaderboard_current) { create(:pvp_leaderboard, pvp_season: current_season, bracket: '2v2') }
      let!(:leaderboard_old) { create(:pvp_leaderboard, pvp_season: old_season, bracket: '2v2') }
      let!(:character) { create(:character) }

      let!(:entry_current_snapshot) do
        create(:pvp_leaderboard_entry,
          character:       character,
          pvp_leaderboard: leaderboard_current,
          snapshot_at:     leaderboard_current.last_synced_at
        )
      end

      let!(:entry_old_snapshot) do
        create(:pvp_leaderboard_entry,
          character:       character,
          pvp_leaderboard: leaderboard_old,
          snapshot_at:     leaderboard_old.last_synced_at
        )
      end

      let!(:entry_non_snapshot) do
        create(:pvp_leaderboard_entry,
          character:       character,
          pvp_leaderboard: leaderboard_current,
          snapshot_at:     1.day.ago
        )
      end

      it 'returns entries for current season by default' do
        results = described_class.latest_snapshot_for_bracket('2v2')
        expect(results).to include(entry_current_snapshot)
        expect(results).not_to include(entry_old_snapshot)
        expect(results).not_to include(entry_non_snapshot)
      end

      it 'returns entries for specified season' do
        results = described_class.latest_snapshot_for_bracket('2v2', season_id: old_season.id)
        expect(results).to include(entry_old_snapshot)
        expect(results).not_to include(entry_current_snapshot)
        expect(results).not_to include(entry_non_snapshot)
      end
    end
  end

  describe 'JSONB handling' do
    let(:entry) { create(:pvp_leaderboard_entry) }

    it 'stores and retrieves raw_equipment correctly' do
      equipment_data = {
        'head' => { 'item_id' => 12_345, 'name' => 'Helm of Valor' },
        'chest' => { 'item_id' => 67_890, 'name' => 'Breastplate of Might' }
      }

      entry.update!(raw_equipment: equipment_data)
      entry.reload

      expect(entry.raw_equipment).to eq(equipment_data)
      expect(entry.raw_equipment['head']['item_id']).to eq(12_345)
    end

    it 'stores and retrieves raw_specialization correctly' do
      spec_data = {
        'talents' => [ 'fireball', 'frostbolt' ],
        'specialization_name' => 'Frost',
        'class' => 'Mage'
      }

      entry.update!(raw_specialization: spec_data)
      entry.reload

      expect(entry.raw_specialization).to eq(spec_data)
      expect(entry.raw_specialization['specialization_name']).to eq('Frost')
    end
  end

  describe 'default values' do
    let(:entry) { create(:pvp_leaderboard_entry) }

    it 'sets default wins to 0' do
      expect(entry.wins).to eq(0)
    end

    it 'sets default losses to 0' do
      expect(entry.losses).to eq(0)
    end

    it 'sets default tier_4p_active to false' do
      expect(entry.tier_4p_active).to be false
    end
  end
end
