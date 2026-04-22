require "rails_helper"

RSpec.describe Pvp::Meta::EnchantSerializer do
  let(:enchantment) do
    instance_double("Enchantment",
      id:          5,
      blizzard_id: 7777
    ).tap { |d| allow(d).to receive(:t).with("name", locale: "en_US").and_return("Stormrider's Agility") }
  end

  let(:record) do
    instance_double("PvpMetaEnchantPopularity",
      id:             3,
      enchantment:    enchantment,
      slot:           "MAIN_HAND",
      usage_count:    60,
      usage_pct:      45.0,
      prev_usage_pct: 30.0,
      snapshot_at:    Time.zone.parse("2026-01-01 00:00:00")
    )
  end

  subject(:result) { described_class.new(record, locale: "en_US").call }

  it "serializes all fields" do
    expect(result[:id]).to eq(3)
    expect(result[:slot]).to eq("MAIN_HAND")
    expect(result[:usage_count]).to eq(60)
    expect(result[:usage_pct]).to eq(45.0)
    expect(result[:prev_usage_pct]).to eq(30.0)
    expect(result[:snapshot_at]).to eq(Time.zone.parse("2026-01-01 00:00:00"))
  end

  it "serializes nested enchantment ref" do
    expect(result[:enchantment][:id]).to eq(5)
    expect(result[:enchantment][:blizzard_id]).to eq(7777)
    expect(result[:enchantment][:name]).to eq("Stormrider's Agility")
  end

  it "computes trend via TrendClassifier" do
    expect(result[:trend]).to eq("up")
  end

  context "when prev_usage_pct is nil" do
    let(:record) do
      instance_double("PvpMetaEnchantPopularity",
        id:             4,
        enchantment:    enchantment,
        slot:           "MAIN_HAND",
        usage_count:    20,
        usage_pct:      15.0,
        prev_usage_pct: nil,
        snapshot_at:    Time.zone.parse("2026-01-01 00:00:00")
      )
    end

    it "returns trend: new" do
      expect(result[:trend]).to eq("new")
      expect(result[:prev_usage_pct]).to be_nil
    end
  end
end
