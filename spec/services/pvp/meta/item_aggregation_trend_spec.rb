require "rails_helper"

RSpec.describe Pvp::Meta::ItemAggregationService do
  subject(:service) { described_class.new(season: season) }

  let(:season) { create(:pvp_season) }
  let(:item)   { create(:item) }

  before do
    create(:pvp_meta_item_popularity,
      pvp_season:     season,
      bracket:        "3v3",
      spec_id:        256,
      slot:           "HEAD",
      item:           item,
      usage_pct:      42.0,
      prev_usage_pct: nil
    )
  end

  it "captures prev_usage_pct from the row that existed before the sync" do
    rows = [
      {
        "bracket" => "3v3",
        "spec_id" => 256,
        "slot" => "HEAD",
        "item_id" => item.id,
        "usage_count" => 80,
        "usage_pct" => "55.00",
        "snapshot_at" => Time.current.to_s
      }
    ]
    allow(service).to receive(:execute_query).and_return(rows)

    service.call

    record = PvpMetaItemPopularity.find_by!(
      pvp_season: season, bracket: "3v3", spec_id: 256, slot: "HEAD", item: item
    )
    expect(record.usage_pct.to_f).to eq(55.0)
    expect(record.prev_usage_pct.to_f).to eq(42.0)
  end

  it "sets prev_usage_pct to nil for a brand-new item that had no prior row" do
    new_item = create(:item)
    rows = [
      {
        "bracket" => "3v3",
        "spec_id" => 256,
        "slot" => "CHEST",
        "item_id" => new_item.id,
        "usage_count" => 30,
        "usage_pct" => "18.00",
        "snapshot_at" => Time.current.to_s
      }
    ]
    allow(service).to receive(:execute_query).and_return(rows)

    service.call

    record = PvpMetaItemPopularity.find_by!(
      pvp_season: season, bracket: "3v3", spec_id: 256, slot: "CHEST", item: new_item
    )
    expect(record.prev_usage_pct).to be_nil
  end
end
