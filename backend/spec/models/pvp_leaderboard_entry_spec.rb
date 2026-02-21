# == Schema Information
#
# Table name: pvp_leaderboard_entries
# Database name: primary
#
#  id                          :bigint           not null, primary key
#  equipment_processed_at      :datetime
#  hero_talent_tree_name       :string
#  item_level                  :integer
#  losses                      :integer          default(0)
#  rank                        :integer
#  rating                      :integer
#  raw_equipment               :binary
#  raw_specialization          :binary
#  snapshot_at                 :datetime
#  specialization_processed_at :datetime
#  tier_4p_active              :boolean          default(FALSE)
#  tier_set_name               :string
#  tier_set_pieces             :integer
#  wins                        :integer          default(0)
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  character_id                :bigint           not null
#  hero_talent_tree_id         :integer
#  pvp_leaderboard_id          :bigint           not null
#  spec_id                     :integer
#  tier_set_id                 :integer
#
# Indexes
#
#  index_entries_for_batch_processing                      (id,equipment_processed_at)
#  index_entries_for_spec_meta                             (pvp_leaderboard_id,spec_id,rating)
#  index_entries_on_leaderboard_and_rating                 (pvp_leaderboard_id,rating)
#  index_entries_on_leaderboard_and_snapshot               (pvp_leaderboard_id,snapshot_at)
#  index_pvp_entries_on_character_and_equipment_processed  (character_id,equipment_processed_at) WHERE (equipment_processed_at IS NOT NULL)
#  index_pvp_entries_on_character_and_snapshot             (character_id,snapshot_at)
#  index_pvp_entries_on_snapshot_at                        (snapshot_at)
#  index_pvp_leaderboard_entries_on_character_id           (character_id)
#  index_pvp_leaderboard_entries_on_hero_talent_tree_id    (hero_talent_tree_id)
#  index_pvp_leaderboard_entries_on_pvp_leaderboard_id     (pvp_leaderboard_id)
#  index_pvp_leaderboard_entries_on_rank                   (rank)
#  index_pvp_leaderboard_entries_on_tier_set_id            (tier_set_id)
#
# Foreign Keys
#
#  fk_rails_...  (character_id => characters.id)
#  fk_rails_...  (pvp_leaderboard_id => pvp_leaderboards.id)
#
require 'rails_helper'

RSpec.describe PvpLeaderboardEntry, type: :model do
  describe 'associations' do
    it { should belong_to(:pvp_leaderboard) }
    it { should belong_to(:character) }
  end

  describe 'included modules' do
    it 'includes CompressedJson module' do
      expect(described_class.included_modules).to include(CompressedJson)
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

      context 'when latest snapshot has unprocessed entries' do
        let!(:new_snapshot_time) { 1.hour.from_now }

        before do
          leaderboard_current.update!(last_synced_at: new_snapshot_time)
        end

        let!(:unprocessed_entry) do
          create(:pvp_leaderboard_entry,
            character:       character,
            pvp_leaderboard: leaderboard_current,
            snapshot_at:     new_snapshot_time,
            spec_id:         nil
          )
        end

        it 'falls back to the previous processed snapshot' do
          results = described_class.latest_snapshot_for_bracket('2v2')
          expect(results).to include(entry_current_snapshot)
          expect(results).not_to include(unprocessed_entry)
        end
      end

      context 'when no entries have been processed' do
        before do
          PvpLeaderboardEntry.update_all(spec_id: nil) # rubocop:disable Rails/SkipsModelValidations
        end

        it 'returns no results' do
          results = described_class.latest_snapshot_for_bracket('2v2')
          expect(results).to be_empty
        end
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
