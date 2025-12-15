require "rails_helper"

RSpec.describe Pvp::Meta::ClassDistributionService do
  subject(:service_call) do
    described_class.new(
      season:  season,
      bracket: bracket,
      region:  region
    ).call
  end

  let(:season)  { create(:pvp_season, is_current: true) }
  let(:bracket) { "2v2" }
  let(:region)  { "us" }

  let(:leaderboard) do
    create(
      :pvp_leaderboard,
      pvp_season:    season,
      bracket:       bracket,
      region:        region,
      last_synced_at: Time.zone.parse("2024-01-01 12:00:00")
    )
  end

  let(:character) do
    create(
      :character,
      class_id:  1,
      class_slug: "warrior"
    )
  end

  before do
    create(
      :pvp_leaderboard_entry,
      pvp_leaderboard: leaderboard,
      character:       character,
      snapshot_at:     leaderboard.last_synced_at - 1.hour,
      spec_id:         71,
      rating:          2100
    )

    create(
      :pvp_leaderboard_entry,
      pvp_leaderboard: leaderboard,
      character:       character,
      snapshot_at:     leaderboard.last_synced_at,
      spec_id:         71,
      rating:          2400
    )
  end

  it "uses the latest snapshot scope so each character is counted once" do
    result = service_call

    expect(result.size).to eq(1)
    row = result.first
    expect(row[:count]).to eq(1)
    expect(row[:mean_rating]).to eq(2400.0)
    expect(row[:class]).to eq("warrior")
    expect(row[:spec]).to eq("arms_warrior")
  end
end
