require "rails_helper"

RSpec.describe Pvp::Meta::EnchantVariantMerger do
  describe ".call" do
    context "when a group has only one variant" do
      let(:entries) do
        [
          {
            slot:           "MAIN_HAND",
            enchantment:    { name: "Swift Agility" },
            usage_count:    50,
            usage_pct:      40.0,
            prev_usage_pct: nil,
            trend:          "new"
          }
        ]
      end

      it "returns the entry unchanged" do
        result = described_class.call(entries)
        expect(result.size).to eq(1)
        expect(result.first[:usage_pct]).to eq(40.0)
      end
    end

    context "when a group has two rank variants" do
      let(:entries) do
        [
          {
            slot:           "MAIN_HAND",
            enchantment:    { name: "Swift Agility" },
            usage_count:    30,
            usage_pct:      25.0,
            prev_usage_pct: 20.0,
            trend:          "up"
          },
          {
            slot:           "MAIN_HAND",
            enchantment:    { name: "Swift Agility" },
            usage_count:    20,
            usage_pct:      15.0,
            prev_usage_pct: 12.0,
            trend:          "up"
          }
        ]
      end

      it "merges usage_count and usage_pct" do
        result = described_class.call(entries)
        expect(result.size).to eq(1)
        expect(result.first[:usage_count]).to eq(50)
        expect(result.first[:usage_pct]).to eq(40.0)
      end

      it "sums prev_usage_pct and recomputes trend" do
        result = described_class.call(entries)
        expect(result.first[:prev_usage_pct]).to eq(32.0)
        expect(result.first[:trend]).to eq("up") # 40 - 32 = 8 > 1.0
      end
    end

    context "when all variants have nil prev_usage_pct" do
      let(:entries) do
        [
          {
            slot:           "MAIN_HAND",
            enchantment:    { name: "Swift Agility" },
            usage_count:    30,
            usage_pct:      25.0,
            prev_usage_pct: nil,
            trend:          "new"
          },
          {
            slot:           "MAIN_HAND",
            enchantment:    { name: "Swift Agility" },
            usage_count:    20,
            usage_pct:      15.0,
            prev_usage_pct: nil,
            trend:          "new"
          }
        ]
      end

      it "sets prev_usage_pct to nil and trend to new" do
        result = described_class.call(entries)
        expect(result.first[:prev_usage_pct]).to be_nil
        expect(result.first[:trend]).to eq("new")
      end
    end

    context "when some variants have prev_usage_pct and some are nil" do
      let(:entries) do
        [
          {
            slot:           "MAIN_HAND",
            enchantment:    { name: "Swift Agility" },
            usage_count:    30,
            usage_pct:      25.0,
            prev_usage_pct: 20.0,
            trend:          "up"
          },
          {
            slot:           "MAIN_HAND",
            enchantment:    { name: "Swift Agility" },
            usage_count:    20,
            usage_pct:      15.0,
            prev_usage_pct: nil,
            trend:          "new"
          }
        ]
      end

      it "sums only the non-nil prev values and recomputes trend" do
        result = described_class.call(entries)
        expect(result.first[:prev_usage_pct]).to eq(20.0)
        expect(result.first[:trend]).to eq("up") # 40.0 - 20.0 = 20 > 1.0
      end
    end

    context "with multiple different enchants" do
      let(:entries) do
        [
          {
            slot:           "MAIN_HAND",
            enchantment:    { name: "Agility" },
            usage_count:    10,
            usage_pct:      10.0,
            prev_usage_pct: nil,
            trend:          "new"
          },
          {
            slot:           "MAIN_HAND",
            enchantment:    { name: "Haste" },
            usage_count:    40,
            usage_pct:      30.0,
            prev_usage_pct: 20.0,
            trend:          "up"
          }
        ]
      end

      it "sorts by usage_pct descending" do
        result = described_class.call(entries)
        expect(result.map { |e| e[:enchantment][:name] }).to eq([ "Haste", "Agility" ])
      end
    end
  end
end
