require "rails_helper"

RSpec.describe Pvp::Meta::GemSerializer do
  let(:item) do
    instance_double("Item",
      id:          20,
      blizzard_id: 88_888,
      icon_url:    "https://cdn.example.com/gem.jpg",
      quality:     "RARE"
    ).tap { |d| allow(d).to receive(:t).with("name", locale: "en_US").and_return("Masterful Alexstraszite") }
  end

  let(:record) do
    instance_double("PvpMetaGemPopularity",
      id:             7,
      item:           item,
      slot:           "HEAD",
      socket_type:    "primordial",
      usage_count:    45,
      usage_pct:      35.0,
      prev_usage_pct: 36.5,
      snapshot_at:    Time.zone.parse("2026-01-01 00:00:00")
    )
  end

  subject(:result) { described_class.new(record, locale: "en_US").call }

  it "serializes all fields" do
    expect(result[:id]).to eq(7)
    expect(result[:slot]).to eq("HEAD")
    expect(result[:socket_type]).to eq("primordial")
    expect(result[:usage_count]).to eq(45)
    expect(result[:usage_pct]).to eq(35.0)
    expect(result[:prev_usage_pct]).to eq(36.5)
    expect(result[:snapshot_at]).to eq(Time.zone.parse("2026-01-01 00:00:00"))
  end

  it "serializes nested item ref" do
    expect(result[:item][:id]).to eq(20)
    expect(result[:item][:blizzard_id]).to eq(88_888)
    expect(result[:item][:name]).to eq("Masterful Alexstraszite")
    expect(result[:item][:icon_url]).to eq("https://cdn.example.com/gem.jpg")
    expect(result[:item][:quality]).to eq("RARE")
  end

  it "computes trend via TrendClassifier (down: 35 - 36.5 = -1.5)" do
    expect(result[:trend]).to eq("down")
  end

  context "when prev_usage_pct is nil" do
    let(:record) do
      instance_double("PvpMetaGemPopularity",
        id:             8,
        item:           item,
        slot:           "HEAD",
        socket_type:    "primordial",
        usage_count:    10,
        usage_pct:      8.0,
        prev_usage_pct: nil,
        snapshot_at:    Time.zone.parse("2026-01-01 00:00:00")
      )
    end

    it "returns trend: new" do
      expect(result[:trend]).to eq("new")
    end
  end
end
