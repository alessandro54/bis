require "rails_helper"

RSpec.describe "Api::V1::Pvp::Meta::Specs", type: :request do
  let!(:current_season) { create(:pvp_season, is_current: true) }
  let!(:leaderboard) { create(:pvp_leaderboard, pvp_season: current_season, bracket: "3v3") }
  let(:snapshot_time) { Time.current }

  describe "GET /api/v1/pvp/meta/specs" do
    context "with valid params" do
      let!(:character1) { create(:character, talent_loadout_code: "ABC123") }
      let!(:character2) { create(:character, talent_loadout_code: "XYZ789") }
      let!(:entry1) do
        create(:pvp_leaderboard_entry,
          pvp_leaderboard: leaderboard,
          character:       character1,
          spec_id:         62,
          snapshot_at:     snapshot_time
        )
      end
      let!(:entry2) do
        create(:pvp_leaderboard_entry,
          pvp_leaderboard: leaderboard,
          character:       character2,
          spec_id:         63,
          snapshot_at:     snapshot_time
        )
      end

      it "returns spec distribution for the bracket" do
        get "/api/v1/pvp/meta/specs", params: { bracket: "3v3" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["bracket"]).to eq("3v3")
        expect(json["specs"]).to be_an(Array)
        expect(json["specs"].length).to eq(2)
        expect(json["specs"].map { |s| s["spec_id"] }).to contain_exactly(62, 63)
      end
    end

    context "with missing params" do
      it "returns error when bracket is missing" do
        get "/api/v1/pvp/meta/specs"

        expect(response).to have_http_status(:bad_request)
      end
    end
  end

  describe "GET /api/v1/pvp/meta/specs/:id" do
    let!(:character1) { create(:character, talent_loadout_code: "ABC123") }
    let!(:character2) { create(:character, talent_loadout_code: "ABC123") }
    let!(:character3) { create(:character, talent_loadout_code: "XYZ789") }

    let!(:entry1) do
      create(:pvp_leaderboard_entry,
        pvp_leaderboard:       leaderboard,
        character:             character1,
        spec_id:               62,
        hero_talent_tree_id:   1,
        hero_talent_tree_name: "Sunfury",
        tier_set_id:           100,
        tier_set_name:         "Mage Tier",
        tier_set_pieces:       4,
        tier_4p_active:        true,
        snapshot_at:           snapshot_time
      )
    end

    let!(:entry2) do
      create(:pvp_leaderboard_entry,
        pvp_leaderboard:       leaderboard,
        character:             character2,
        spec_id:               62,
        hero_talent_tree_id:   1,
        hero_talent_tree_name: "Sunfury",
        tier_set_id:           100,
        tier_set_name:         "Mage Tier",
        tier_set_pieces:       4,
        tier_4p_active:        true,
        snapshot_at:           snapshot_time
      )
    end

    let!(:entry3) do
      create(:pvp_leaderboard_entry,
        pvp_leaderboard:       leaderboard,
        character:             character3,
        spec_id:               62,
        hero_talent_tree_id:   2,
        hero_talent_tree_name: "Spellslinger",
        snapshot_at:           snapshot_time
      )
    end

    it "returns detailed meta for a specific spec" do
      get "/api/v1/pvp/meta/specs/62", params: { bracket: "3v3" }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)

      expect(json["spec_id"]).to eq(62)
      expect(json["bracket"]).to eq("3v3")
      expect(json["total_players"]).to eq(3)
    end

    it "returns popular talent builds" do
      get "/api/v1/pvp/meta/specs/62", params: { bracket: "3v3" }

      json = JSON.parse(response.body)
      talent_builds = json["talent_builds"]

      expect(talent_builds).to be_an(Array)
      expect(talent_builds.first["loadout_code"]).to eq("ABC123")
      expect(talent_builds.first["count"]).to eq(2)
    end

    it "returns hero talent distribution" do
      get "/api/v1/pvp/meta/specs/62", params: { bracket: "3v3" }

      json = JSON.parse(response.body)
      hero_talents = json["hero_talents"]

      expect(hero_talents).to be_an(Array)
      sunfury = hero_talents.find { |h| h["hero_talent_tree_name"] == "Sunfury" }
      expect(sunfury["count"]).to eq(2)
    end

    it "returns tier set distribution" do
      get "/api/v1/pvp/meta/specs/62", params: { bracket: "3v3" }

      json = JSON.parse(response.body)
      tier_sets = json["tier_sets"]

      expect(tier_sets).to be_an(Array)
    end

    context "with limit param" do
      before do
        # Create more entries with different loadout codes
        5.times do |i|
          char = create(:character, talent_loadout_code: "UNIQUE#{i}")
          create(:pvp_leaderboard_entry,
            pvp_leaderboard: leaderboard,
            character:       char,
            spec_id:         62,
            snapshot_at:     snapshot_time
          )
        end
      end

      it "limits talent builds results" do
        get "/api/v1/pvp/meta/specs/62", params: { bracket: "3v3", limit: 3 }

        json = JSON.parse(response.body)
        expect(json["talent_builds"].length).to be <= 3
      end
    end
  end
end
