# spec/services/pvp/entries/process_specialization_service_spec.rb
require "rails_helper"

RSpec.describe Pvp::Entries::ProcessSpecializationService, type: :service do
  include_examples "service result interface"

  let(:character) { create(:character) }
  let(:locale)    { "en_US" }

  # raw_specialization is the raw Blizzard API response — its shape doesn't
  # matter here because CharacterEquipmentSpecializationsService is mocked.
  let(:raw_specialization) { { "raw" => "blizzard_api_response" } }

  subject(:result) do
    described_class.call(character: character, raw_specialization: raw_specialization, locale: locale)
  end

  # talents_raw_1.json is the normalized talent payload produced by
  # CharacterEquipmentSpecializationsService#talents — it contains
  # class_talents, spec_talents, hero_talents, pvp_talents, and
  # talent_loadout_code. This is what UpsertFromRawSpecializationService
  # consumes directly.
  let(:fixture_talents) do
    JSON.parse(File.read(Rails.root.join("spec/fixtures/pvp_leaderboard_entries/talents_raw_1.json")))
  end

  let(:spec_service_double) do
    instance_double(
      Blizzard::Data::CharacterEquipmentSpecializationsService,
      has_data?:             true,
      active_specialization: { "id" => 262 },
      active_hero_tree:      { "id" => 123, "name" => "Stormbringer" },
      talents:               fixture_talents,
      class_slug:            "Shaman"
    )
  end

  before do
    character.update!(class_slug: "warrior", class_id: 1)
    allow(Blizzard::Data::CharacterEquipmentSpecializationsService)
      .to receive(:new).with(raw_specialization)
      .and_return(spec_service_double)
  end

  describe "#call" do
    context "when there is no specialization data" do
      before { allow(spec_service_double).to receive(:has_data?).and_return(false) }

      it "returns a failure" do
        expect(result).to be_failure
        expect(result.error).to eq("No specialization data")
      end
    end

    context "when spec_id is unknown" do
      before do
        allow(spec_service_double).to receive(:active_specialization).and_return({ "id" => 99_999 })
      end

      it "returns a failure" do
        expect(result).to be_failure
        expect(result.error).to match(/Unknown spec id/)
      end
    end

    context "when everything is valid" do
      it "returns success" do
        expect(result).to be_success
      end

      it "returns entry_attrs with specialization metadata" do
        attrs = result.context[:entry_attrs]

        expect(attrs[:spec_id]).to eq(262)
        expect(attrs[:hero_talent_tree_id]).to eq(123)
        expect(attrs[:hero_talent_tree_name]).to eq("stormbringer")
        expect(attrs[:specialization_processed_at]).to be_present
      end

      it "normalizes and updates character class_slug and class_id" do
        expect { result; character.reload }
          .to change(character, :class_slug).to("shaman")
          .and change(character, :class_id).to(7)
      end

      it "does not update class fields when class_slug is blank" do
        allow(spec_service_double).to receive(:class_slug).and_return(nil)

        expect { result; character.reload }
          .not_to change { [ character.class_slug, character.class_id ] }
      end

      context "when talent_loadout_code has changed" do
        before { character.update_columns(talent_loadout_code: "old_code") }

        it "creates character_talents for all talent types" do
          result; character.reload

          types = character.character_talents.pluck(:talent_type).uniq.sort
          expect(types).to contain_exactly("class", "hero", "pvp", "spec")
        end

        it "saves pvp talents with slot_number" do
          result

          pvp = character.character_talents.where(talent_type: "pvp")
          expect(pvp.count).to eq(3)
          expect(pvp.pluck(:slot_number).compact).not_to be_empty
        end

        it "updates talent_loadout_code on the character" do
          expect { result }
            .to change { character.reload.talent_loadout_code }
            .to(fixture_talents["talent_loadout_code"])
        end

        it "replaces stale character_talents" do
          stale = create(:talent, blizzard_id: 999_999, talent_type: "class")
          character.character_talents.create!(talent: stale, talent_type: "class", rank: 1)

          result

          expect(character.character_talents.where(talent_id: stale.id)).to be_empty
        end
      end

      context "when talent_loadout_code is already current" do
        before { character.update_columns(talent_loadout_code: fixture_talents["talent_loadout_code"]) }

        it "does not rebuild character_talents" do
          expect { result }.not_to change { character.character_talents.count }
        end

        it "does not update talent_loadout_code" do
          expect { result }.not_to change { character.reload.talent_loadout_code }
        end
      end
    end

    context "when an unexpected error occurs" do
      before do
        allow(Blizzard::Data::Talents::UpsertFromRawSpecializationService)
          .to receive(:call).and_raise(StandardError.new("boom"))
      end

      it "returns a failure wrapping the exception" do
        expect(result).to be_failure
        expect(result.error).to be_a(StandardError)
        expect(result.error.message).to eq("boom")
      end
    end
  end
end
