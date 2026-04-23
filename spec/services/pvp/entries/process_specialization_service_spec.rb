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

  # fixture_talents is the normalized talent payload produced by
  # CharacterEquipmentSpecializationsService#talents — it contains
  # class_talents, spec_talents, hero_talents, pvp_talents, and
  # talent_loadout_code. This is what UpsertFromRawSpecializationService
  # consumes directly.
  let(:fixture_talents) do
    raw = JSON.parse(File.read(Rails.root.join("spec/fixtures/specialization/egirlbooster.json")))
    Blizzard::Data::CharacterEquipmentSpecializationsService.new(raw).talents
  end

  let(:spec_service_double) do
    instance_double(
      Blizzard::Data::CharacterEquipmentSpecializationsService,
      has_data?:             true,
      active_specialization: { "id" => 262 },
      active_hero_tree:      { "id" => 123, "name" => "Stormbringer" },
      talents:               fixture_talents,
      class_slug:            "Shaman",
      all_specializations:   [
        {
          spec_id:             262,
          hero_tree:           { "id" => 123, "name" => "Stormbringer" },
          talent_loadout_code: fixture_talents["talent_loadout_code"],
          talents:             fixture_talents.slice("class_talents", "spec_talents", "hero_talents"),
          pvp_talents:         fixture_talents["pvp_talents"],
          class_slug:          "shaman"
        }
      ]
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

      it "returns char_attrs with normalized class_slug and class_id" do
        char_attrs = result.context[:char_attrs]

        expect(char_attrs[:class_slug]).to eq("shaman")
        expect(char_attrs[:class_id]).to eq(7)
      end

      it "does not include class fields in char_attrs when class_slug is blank" do
        allow(spec_service_double).to receive(:class_slug).and_return(nil)

        char_attrs = result.context[:char_attrs]
        expect(char_attrs).not_to have_key(:class_slug)
        expect(char_attrs).not_to have_key(:class_id)
      end

      context "when talent_loadout_code has changed" do
        before { character.update_columns(spec_talent_loadout_codes: { "262" => "old_code" }) }

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

        it "returns spec_talent_loadout_codes in char_attrs" do
          expect(result.context[:char_attrs][:spec_talent_loadout_codes])
            .to eq({ "262" => fixture_talents["talent_loadout_code"] })
        end

        it "replaces stale character_talents" do
          stale = create(:talent, blizzard_id: 999_999, talent_type: "class")
          character.character_talents.create!(talent: stale, talent_type: "class", rank: 1, spec_id: 262)

          result

          expect(character.character_talents.where(talent_id: stale.id)).to be_empty
        end

        context "when insert_all! raises mid-rebuild" do
          before do
            allow(CharacterTalent).to receive(:insert_all!).and_raise(ActiveRecord::StatementInvalid,
"simulated failure")
          end

          it "returns a failure result" do
            expect(result).to be_failure
          end

          it "leaves character_talents unchanged on insert failure (transaction rollback)" do
            existing = create(:talent, blizzard_id: 888_000, talent_type: "class")
            character.character_talents.create!(talent: existing, talent_type: "class", rank: 1, spec_id: 262)
            count_before = character.character_talents.count

            result # triggers the service

            expect(character.character_talents.reload.count).to eq(count_before)
          end
        end
      end

      context "when talent_loadout_code is already current" do
        before {
 character.update_columns(spec_talent_loadout_codes: { "262" => fixture_talents["talent_loadout_code"] }) }

        it "does not rebuild character_talents" do
          expect { result }.not_to change { character.character_talents.count }
        end

        it "does not include spec_talent_loadout_codes in char_attrs" do
          expect(result.context[:char_attrs]).not_to have_key(:spec_talent_loadout_codes)
        end
      end
    end

    # Uses synthetic talent data with default_points to test per-spec storage.
    context "default_points on talent_spec_assignments" do
      let(:disc_talents) do
        {
          "class_talents" => [
            { "id" => 82_717, "name" => "Improved Flash Heal", "rank" => 1, "default_points" => 1 },
            { "id" => 82_713, "name" => "Mind Blast", "rank" => 1, "default_points" => 1 },
            { "id" => 82_700, "name" => "Shadow Word: Death", "rank" => 1, "default_points" => 0 }
          ],
          "spec_talents" => [
            { "id" => 83_001, "name" => "Atonement", "rank" => 1, "default_points" => 0 }
          ],
          "hero_talents" => [],
          "pvp_talents" => [
            {
              "selected" => {
                "talent" => { "id" => 5001, "name" => "Trinity" },
                "spell_tooltip" => { "spell" => { "id" => 9001 } }
              },
              "slot_number" => 2
            }
          ],
          "talent_loadout_code" => "disc_test_code"
        }
      end

      let(:disc_service_double) do
        instance_double(
          Blizzard::Data::CharacterEquipmentSpecializationsService,
          has_data?:             true,
          active_specialization: { "id" => 256 },
          active_hero_tree:      nil,
          talents:               disc_talents,
          class_slug:            "priest",
          all_specializations:   [
            {
              spec_id:             256,
              hero_tree:           nil,
              talent_loadout_code: "disc_test_code",
              talents:             disc_talents.slice("class_talents", "spec_talents", "hero_talents"),
              pvp_talents:         disc_talents["pvp_talents"],
              class_slug:          "priest"
            }
          ]
        )
      end

      before do
        allow(Blizzard::Data::CharacterEquipmentSpecializationsService)
          .to receive(:new).with(raw_specialization).and_return(disc_service_double)
        character.update_columns(spec_talent_loadout_codes: { "256" => "old_code" })

        # Pre-create canonical TalentSpecAssignment rows (normally done by SyncTalentTreesJob).
        # upsert_spec_default_points only updates existing rows, never creates new ones.
        { 82_717 => "class", 82_713 => "class", 82_700 => "class", 83_001 => "spec" }.each do |blz_id, type|
          talent = create(:talent, blizzard_id: blz_id, talent_type: type)
          TalentSpecAssignment.create!(talent_id: talent.id, spec_id: 256, default_points: 0)
        end
      end

      it "does not modify default_points (owned by SyncTalentTreesJob, not character sync)" do
        result

        assignments = TalentSpecAssignment.where(spec_id: 256).where("default_points > 0")
        expect(assignments.count).to eq(0)
      end

      it "does not create default_points entries for pvp talents" do
        result

        pvp_talent_ids = Talent.where(talent_type: "pvp").pluck(:id)
        pvp_with_dp = TalentSpecAssignment
          .where(talent_id: pvp_talent_ids, spec_id: 256)
          .where("default_points > 0")
        expect(pvp_with_dp).not_to exist
      end
    end

    context "when an unexpected error occurs" do
      before do
        allow(Blizzard::Data::Talents::UpsertFromRawSpecializationService)
          .to receive(:call).and_raise(StandardError.new("boom"))
      end

      it "propagates the exception instead of swallowing it" do
        expect { result }.to raise_error(StandardError, "boom")
      end
    end

    context "when an unexpected RuntimeError occurs" do
      before do
        allow(Blizzard::Data::CharacterEquipmentSpecializationsService)
          .to receive(:new).and_return(spec_service_double)
        allow_any_instance_of(Pvp::Entries::ProcessSpecializationService)
          .to receive(:process_all_specs_talents)
          .and_raise(RuntimeError, "unexpected db failure")
      end

      it "propagates the exception instead of swallowing it" do
        char = create(:character)
        raw  = { "active_specialization" => { "id" => 65 } }
        service = Pvp::Entries::ProcessSpecializationService.new(
          character:          char,
          raw_specialization: raw
        )
        expect { service.call }.to raise_error(RuntimeError, "unexpected db failure")
      end
    end
  end
end
