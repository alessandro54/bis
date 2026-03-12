require "rails_helper"

RSpec.describe Blizzard::Api::Profile::CharacterStatisticsSummary do
  SPEC_SECONDARY_STATS = %w[HASTE_RATING CRIT_RATING MASTERY_RATING VERSATILITY].freeze

  describe ".extract_stat_pcts" do
    subject(:result) { described_class.extract_stat_pcts(raw) }

    # Build a statistics-shaped payload from the real jw equipment fixture.
    # Sums secondary stats across all equipped items (skipping negated entries)
    # to produce realistic rating values, then adds plausible rating_bonus %.
    let(:raw) do
      items = JSON.parse(File.read(Rails.root.join("spec/fixtures/equipment/jw.json")))["equipped_items"]

      totals = items.each_with_object(Hash.new(0)) do |item, h|
        Array(item["stats"]).each do |s|
          type = s.dig("type", "type")
          h[type] += s["value"].to_i if SPEC_SECONDARY_STATS.include?(type) && !s["is_negated"]
        end
      end

      {
        "melee_crit" => { "rating" => totals["CRIT_RATING"], "rating_bonus" => 14.0 },
        "melee_haste" => { "rating" => totals["HASTE_RATING"], "rating_bonus" => 11.18 },
        "mastery" => { "rating" => totals["MASTERY_RATING"], "rating_bonus" => 9.7 },
        "versatility" => totals["VERSATILITY"],
        "versatility_damage_done_bonus" => 14.5
      }
    end

    it "extracts all four secondary stats" do
      expect(result.keys).to match_array(%w[CRIT_RATING HASTE_RATING MASTERY_RATING VERSATILITY])
    end

    it "extracts ratings from the equipment fixture totals" do
      expect(result.transform_values { |v| v["rating"] }).to eq(
        "CRIT_RATING" => 118,
        "HASTE_RATING" => 19,
        "MASTERY_RATING" => 379,
        "VERSATILITY" => 310
      )
    end

    it "extracts percentages" do
      expect(result.transform_values { |v| v["pct"] }).to eq(
        "CRIT_RATING" => 14.0,
        "HASTE_RATING" => 11.18,
        "MASTERY_RATING" => 9.7,
        "VERSATILITY" => 14.5
      )
    end

    context "with nil input" do
      let(:raw) { nil }

      it { is_expected.to eq({}) }
    end

    context "with empty hash" do
      let(:raw) { {} }

      it { is_expected.to eq({}) }
    end
  end
end
