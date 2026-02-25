require "rails_helper"

RSpec.describe "Api::V1::Pvp::Meta::Enchants", type: :request do
  let!(:current_season) { create(:pvp_season, is_current: true) }
  let!(:enchantment) { create(:enchantment) }

  before do
    create(:translation,
      translatable: enchantment,
      key: "name",
      locale: "en_US",
      value: "Enchant Weapon - Dreaming Devotion",
      meta: { "source" => "test" }
    )
  end

  describe "GET /api/v1/pvp/meta/enchants" do
    context "with valid params" do
      let!(:enchant_popularity) do
        create(:pvp_meta_enchant_popularity,
          pvp_season: current_season,
          enchantment: enchantment,
          bracket: "3v3",
          spec_id: 62,
          slot: "main_hand",
          usage_count: 80,
          usage_pct: 90.0
        )
      end

      it "returns enchants meta for the spec and bracket" do
        get "/api/v1/pvp/meta/enchants", params: { bracket: "3v3", spec_id: 62 }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json).to be_an(Array)
        expect(json.first["enchantment"]["name"]).to eq("Enchant Weapon - Dreaming Devotion")
        expect(json.first["slot"]).to eq("main_hand")
        expect(json.first["usage_pct"]).to eq(90.0)
      end

      it "filters by slot when provided" do
        create(:pvp_meta_enchant_popularity,
          pvp_season: current_season,
          bracket: "3v3",
          spec_id: 62,
          slot: "legs"
        )

        get "/api/v1/pvp/meta/enchants", params: { bracket: "3v3", spec_id: 62, slot: "main_hand" }

        json = JSON.parse(response.body)
        expect(json.length).to eq(1)
        expect(json.first["slot"]).to eq("main_hand")
      end
    end

    context "with missing params" do
      it "returns error when bracket is missing" do
        get "/api/v1/pvp/meta/enchants", params: { spec_id: 62 }

        expect(response).to have_http_status(:bad_request)
      end

      it "returns error when spec_id is missing" do
        get "/api/v1/pvp/meta/enchants", params: { bracket: "3v3" }

        expect(response).to have_http_status(:bad_request)
      end
    end
  end
end

