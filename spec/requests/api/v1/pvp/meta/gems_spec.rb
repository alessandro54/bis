require "rails_helper"

RSpec.describe "Api::V1::Pvp::Meta::Gems", type: :request do
  let!(:current_season) { create(:pvp_season, is_current: true) }
  let!(:gem_item) { create(:item, quality: "rare") }

  before do
    create(:translation,
      translatable: gem_item,
      key:          "name",
      locale:       "en_US",
      value:        "Deadly Sapphire",
      meta:         { "source" => "test" }
    )
  end

  describe "GET /api/v1/pvp/meta/gems" do
    context "with valid params" do
      let!(:gem_popularity) do
        create(:pvp_meta_gem_popularity,
          pvp_season:  current_season,
          item:        gem_item,
          bracket:     "3v3",
          spec_id:     62,
          slot:        "head",
          socket_type: "primordial",
          usage_count: 45,
          usage_pct:   65.0
        )
      end

      it "returns gems meta for the spec and bracket" do
        get "/api/v1/pvp/meta/gems", params: { bracket: "3v3", spec_id: 62 }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json).to be_an(Array)
        expect(json.first["item"]["name"]).to eq("Deadly Sapphire")
        expect(json.first["slot"]).to eq("head")
        expect(json.first["socket_type"]).to eq("primordial")
        expect(json.first["usage_pct"]).to eq(65.0)
      end

      it "filters by slot when provided" do
        create(:pvp_meta_gem_popularity,
          pvp_season:  current_season,
          bracket:     "3v3",
          spec_id:     62,
          slot:        "chest",
          socket_type: "primordial"
        )

        get "/api/v1/pvp/meta/gems", params: { bracket: "3v3", spec_id: 62, slot: "head" }

        json = JSON.parse(response.body)
        expect(json.length).to eq(1)
        expect(json.first["slot"]).to eq("head")
      end

      it "filters by socket_type when provided" do
        create(:pvp_meta_gem_popularity,
          pvp_season:  current_season,
          bracket:     "3v3",
          spec_id:     62,
          slot:        "head",
          socket_type: "regular"
        )

        get "/api/v1/pvp/meta/gems", params: { bracket: "3v3", spec_id: 62, socket_type: "primordial" }

        json = JSON.parse(response.body)
        expect(json.length).to eq(1)
        expect(json.first["socket_type"]).to eq("primordial")
      end
    end

    context "with missing params" do
      it "returns error when bracket is missing" do
        get "/api/v1/pvp/meta/gems", params: { spec_id: 62 }

        expect(response).to have_http_status(:bad_request)
      end

      it "returns error when spec_id is missing" do
        get "/api/v1/pvp/meta/gems", params: { bracket: "3v3" }

        expect(response).to have_http_status(:bad_request)
      end
    end
  end
end
