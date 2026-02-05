# == Schema Information
#
# Table name: pvp_leaderboard_entry_items
# Database name: primary
#
#  id                       :bigint           not null, primary key
#  context                  :string
#  item_level               :integer
#  raw                      :jsonb
#  slot                     :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  item_id                  :bigint           not null
#  pvp_leaderboard_entry_id :bigint           not null
#
# Indexes
#
#  index_entry_items_on_entry_and_slot                            (pvp_leaderboard_entry_id,slot) UNIQUE
#  index_pvp_leaderboard_entry_items_on_item_id                   (item_id)
#  index_pvp_leaderboard_entry_items_on_pvp_leaderboard_entry_id  (pvp_leaderboard_entry_id)
#
# Foreign Keys
#
#  fk_rails_...  (item_id => items.id)
#  fk_rails_...  (pvp_leaderboard_entry_id => pvp_leaderboard_entries.id)
#
require 'rails_helper'

RSpec.describe PvpLeaderboardEntryItem, type: :model do
  describe 'associations' do
    it { should belong_to(:pvp_leaderboard_entry) }
    it { should belong_to(:item) }
  end

  describe 'validations' do
    it 'validates uniqueness of slot scoped to pvp_leaderboard_entry_id' do
      entry = create(:pvp_leaderboard_entry)
      item = create(:item)
      create(:pvp_leaderboard_entry_item, pvp_leaderboard_entry: entry, slot: 'head')

      new_entry_item = build(:pvp_leaderboard_entry_item, pvp_leaderboard_entry: entry, slot: 'head')
      expect(new_entry_item).not_to be_valid
      expect(new_entry_item.errors[:slot]).to include('has already been taken')
    end

    it 'allows the same slot for different entries' do
      entry1 = create(:pvp_leaderboard_entry)
      entry2 = create(:pvp_leaderboard_entry)
      item = create(:item)

      create(:pvp_leaderboard_entry_item, pvp_leaderboard_entry: entry1, slot: 'head')
      new_entry_item = build(:pvp_leaderboard_entry_item, pvp_leaderboard_entry: entry2, slot: 'head')

      expect(new_entry_item).to be_valid
    end
  end

  describe 'database constraints' do
    it 'enforces unique pvp_leaderboard_entry_id and slot combination' do
      entry = create(:pvp_leaderboard_entry)
      item = create(:item)
      create(:pvp_leaderboard_entry_item, pvp_leaderboard_entry: entry, slot: 'head')

      expect {
        create(:pvp_leaderboard_entry_item, pvp_leaderboard_entry: entry, slot: 'head')
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe 'attributes' do
    let(:entry_item) { build(:pvp_leaderboard_entry_item) }

    it 'can store slot' do
      entry_item.slot = 'head'
      expect(entry_item.slot).to eq('head')
    end

    it 'can store item_level' do
      entry_item.item_level = 500
      expect(entry_item.item_level).to eq(500)
    end

    it 'can store context' do
      entry_item.context = 'pvp'
      expect(entry_item.context).to eq('pvp')
    end

    it 'can store raw JSON data' do
      raw_data = { 'property' => 'value', 'number' => 42 }
      entry_item.raw = raw_data
      expect(entry_item.raw).to eq(raw_data)
    end
  end

  describe 'JSONB handling' do
    let(:entry_item) { create(:pvp_leaderboard_entry_item) }

    it 'stores and retrieves JSON data correctly' do
      complex_data = {
        'stats' => { 'strength' => 100, 'agility' => 50 },
        'enchantments' => [ 'fire', 'ice' ],
        'level' => 80
      }

      entry_item.update!(raw: complex_data)
      entry_item.reload

      expect(entry_item.raw).to eq(complex_data)
      expect(entry_item.raw['stats']['strength']).to eq(100)
    end
  end
end
