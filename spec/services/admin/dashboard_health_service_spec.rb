require "rails_helper"

RSpec.describe Admin::DashboardHealthService, type: :service do
  subject(:result) { described_class.call(season: season) }

  let(:season) { create(:pvp_season, is_current: true, display_name: "Season 1") }
  let(:leaderboard) { create(:pvp_leaderboard, pvp_season: season, bracket: "3v3", region: "us") }

  describe "#call" do
    it "returns a successful result" do
      expect(result).to be_success
    end

    context "with no data" do
      it "returns empty brackets" do
        expect(result.context[:brackets]).to eq([])
      end

      it "returns nil characters" do
        expect(result.context[:characters]).to be_nil
      end

      it "returns nil freshness" do
        expect(result.context[:freshness]).to be_nil
      end
    end

    context "with entries in various processing states" do
      let!(:char_processed) { create(:character) }
      let!(:char_eq_only)   { create(:character) }
      let!(:char_spec_only) { create(:character) }
      let!(:char_none)      { create(:character) }

      let!(:entry_processed) do
        create(:pvp_leaderboard_entry,
               pvp_leaderboard: leaderboard, character: char_processed,
               equipment_processed_at: 30.minutes.ago, specialization_processed_at: 30.minutes.ago)
      end

      let!(:entry_eq_only) do
        create(:pvp_leaderboard_entry,
               pvp_leaderboard: leaderboard, character: char_eq_only,
               equipment_processed_at: 2.hours.ago, specialization_processed_at: nil)
      end

      let!(:entry_spec_only) do
        create(:pvp_leaderboard_entry,
               pvp_leaderboard: leaderboard, character: char_spec_only,
               equipment_processed_at: nil, specialization_processed_at: 10.hours.ago)
      end

      let!(:entry_none) do
        create(:pvp_leaderboard_entry,
               pvp_leaderboard: leaderboard, character: char_none,
               equipment_processed_at: nil, specialization_processed_at: nil)
      end

      describe "brackets" do
        it "returns one bracket with correct counts" do
          brackets = result.context[:brackets]

          expect(brackets.size).to eq(1)

          bracket = brackets.first
          expect(bracket[:label]).to eq("3v3")
          expect(bracket[:regions]).to eq("US")
          expect(bracket[:total]).to eq(4)

          rows = bracket[:rows]
          expect(rows[0]).to include(label: "Fully processed", count: 1, pct: 25.0)
          expect(rows[1]).to include(label: "Equipment only",  count: 1, pct: 25.0)
          expect(rows[2]).to include(label: "Talents only",    count: 1, pct: 25.0)
          expect(rows[3]).to include(label: "Unprocessed",     count: 1, pct: 25.0)
        end
      end

      describe "characters" do
        it "counts all as available when no flags set" do
          chars = result.context[:characters]

          expect(chars[:total]).to eq(4)
          expect(chars[:rows][0]).to include(label: "Available", count: 4)
          expect(chars[:rows][1]).to include(label: "Not found (404)", count: 0)
          expect(chars[:rows][2]).to include(label: "Private", count: 0)
        end
      end

      describe "freshness" do
        it "buckets processed entries by age" do
          freshness = result.context[:freshness]

          expect(freshness[:total]).to eq(2)

          labels = freshness[:rows].map { |r| r[:label] }
          expect(labels).to eq([ "< 1h ago", "1-6h ago", "6-24h ago", "> 24h ago" ])

          h1  = freshness[:rows].find { |r| r[:label] == "< 1h ago" }
          h6  = freshness[:rows].find { |r| r[:label] == "1-6h ago" }
          expect(h1[:count]).to eq(1)
          expect(h6[:count]).to eq(1)
        end
      end
    end

    context "with private and unavailable characters" do
      let!(:available_char)   { create(:character) }
      let!(:private_char)     { create(:character, is_private: true) }
      let!(:unavailable_char) { create(:character, unavailable_until: 1.week.from_now) }

      before do
        [ available_char, private_char, unavailable_char ].each do |char|
          create(:pvp_leaderboard_entry,
                 pvp_leaderboard: leaderboard, character: char,
                 equipment_processed_at: Time.current, specialization_processed_at: Time.current)
        end
      end

      it "breaks down character availability" do
        chars = result.context[:characters]

        expect(chars[:total]).to eq(3)
        expect(chars[:rows][0]).to include(label: "Available", count: 1)
        expect(chars[:rows][1]).to include(label: "Not found (404)", count: 1)
        expect(chars[:rows][2]).to include(label: "Private", count: 1)
      end
    end

    context "with multiple brackets" do
      let(:leaderboard_eu) { create(:pvp_leaderboard, pvp_season: season, bracket: "3v3", region: "eu") }
      let(:leaderboard_2v2) { create(:pvp_leaderboard, pvp_season: season, bracket: "2v2", region: "us") }

      before do
        create(:pvp_leaderboard_entry, pvp_leaderboard: leaderboard,
               equipment_processed_at: Time.current, specialization_processed_at: Time.current)
        create(:pvp_leaderboard_entry, pvp_leaderboard: leaderboard_eu,
               equipment_processed_at: Time.current, specialization_processed_at: Time.current)
        create(:pvp_leaderboard_entry, pvp_leaderboard: leaderboard_2v2,
               equipment_processed_at: nil, specialization_processed_at: nil)
      end

      it "groups entries by bracket with regions merged" do
        brackets = result.context[:brackets]

        bracket_3v3 = brackets.find { |b| b[:label] == "3v3" }
        bracket_2v2 = brackets.find { |b| b[:label] == "2v2" }

        expect(bracket_3v3[:regions]).to eq("EU + US")
        expect(bracket_3v3[:total]).to eq(2)
        expect(bracket_3v3[:rows][0]).to include(label: "Fully processed", count: 2)

        expect(bracket_2v2[:regions]).to eq("US")
        expect(bracket_2v2[:total]).to eq(1)
        expect(bracket_2v2[:rows][3]).to include(label: "Unprocessed", count: 1)
      end
    end

    context "with translation data" do
      let(:item)        { create(:item) }
      let(:enchantment) { create(:enchantment) }
      let(:talent)      { create(:talent) }

      before do
        create(:pvp_meta_item_popularity, pvp_season: season, item: item)
        create(:pvp_meta_enchant_popularity, pvp_season: season, enchantment: enchantment)
        PvpMetaTalentPopularity.create!(
          pvp_season: season, talent: talent, bracket: "3v3", spec_id: 62,
          talent_type: "class", usage_count: 10, snapshot_at: Time.current
        )

        create(:translation, translatable: item, locale: "en_US", key: "name", value: "Sword")
      end

      it "returns translation sections with coverage stats" do
        translations = result.context[:translations]

        expect(translations.size).to eq(3)
        expect(translations.map { |t| t[:label] }).to eq([ "Items & Gems", "Enchantments", "Talents" ])

        items_section = translations[0]
        expect(items_section[:total]).to eq(1)

        en_locale = items_section[:locales].find { |l| l[:locale] == "en_US" }
        expect(en_locale[:present]).to eq(1)
        expect(en_locale[:missing]).to eq(0)
        expect(en_locale[:pct]).to eq(100.0)

        es_locale = items_section[:locales].find { |l| l[:locale] == "es_MX" }
        expect(es_locale[:present]).to eq(0)
        expect(es_locale[:missing]).to eq(1)
        expect(es_locale[:pct]).to eq(0.0)
      end
    end

    describe "last_cycle" do
      it "returns nil when no sync cycles exist" do
        expect(result.context[:last_cycle]).to be_nil
      end

      it "returns the most recent cycle" do
        old_cycle = PvpSyncCycle.create!(
          pvp_season: season, status: "completed", snapshot_at: 2.days.ago,
          regions: [ "us" ], completed_at: 2.days.ago
        )
        new_cycle = PvpSyncCycle.create!(
          pvp_season: season, status: "syncing_characters", snapshot_at: 1.hour.ago,
          regions: [ "us", "eu" ]
        )

        expect(result.context[:last_cycle]).to eq(new_cycle)
      end
    end
  end
end
