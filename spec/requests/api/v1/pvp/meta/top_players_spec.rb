require "rails_helper"

RSpec.describe "Api::V1::Pvp::Meta::TopPlayers", type: :request do
  let!(:current_season) { create(:pvp_season, is_current: true) }
  let!(:leaderboard) do
    create(:pvp_leaderboard, pvp_season: current_season, bracket: "3v3", region: "us")
  end
  let!(:character) do
    create(
      :character,
      name:       "testplayer",
      realm:      "bleeding-hollow",
      region:     "us",
      avatar_url: "https://example.com/avatar.png",
      class_slug: "mage"
    )
  end
  let!(:entry) do
    create(
      :pvp_leaderboard_entry,
      pvp_leaderboard:        leaderboard,
      character:              character,
      spec_id:                62,
      rating:                 2400,
      wins:                   80,
      losses:                 20,
      rank:                   5,
      hero_talent_tree_name:  "Sunfury",
      equipment_processed_at: 1.day.ago,
      snapshot_at:            Time.current
    )
  end

  describe "GET /api/v1/pvp/meta/top_players" do
    it "returns display-friendly player data without hero talent" do
      get "/api/v1/pvp/meta/top_players", params: { bracket: "3v3", spec_id: 62, region: "us" }

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      player = json.fetch("players").first

      expect(player["name"]).to eq("testplayer")
      expect(player["realm"]).to eq("Bleeding Hollow")
      expect(player["region"]).to eq("US")
      expect(player["avatar_url"]).to eq("https://example.com/avatar.png")
      expect(player["class_slug"]).to eq("mage")
      expect(player).not_to have_key("hero_talent_tree_name")
    end
  end
end
