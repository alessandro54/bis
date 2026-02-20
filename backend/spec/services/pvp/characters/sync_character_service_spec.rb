require "rails_helper"

RSpec.describe Pvp::Characters::SyncCharacterService do
  include ActiveJob::TestHelper

  subject(:call_service) do
    described_class.call(
      character: character,
      locale:    locale,
      ttl_hours: ttl_hours
    )
  end

  let(:character) do
    create(
      :character,
      region: "us",
      realm:  "illidan",
      name:   "manongauz"
    )
  end

  let(:locale) { "en_US" }
  let(:ttl_hours) { 24 }

  let!(:entry_2v2) do
    next unless character

    create(
      :pvp_leaderboard_entry,
      character:          character,
      pvp_leaderboard:    create(
        :pvp_leaderboard,
        pvp_season: create(:pvp_season),
        bracket:    "2v2",
        region:     character.region
      ),
      raw_equipment:      nil,
      raw_specialization: nil
    )
  end

  let!(:entry_3v3) do
    next unless character

    create(
      :pvp_leaderboard_entry,
      character:          character,
      pvp_leaderboard:    create(
        :pvp_leaderboard,
        pvp_season: create(:pvp_season),
        bracket:    "3v3",
        region:     character.region
      ),
      raw_equipment:      nil,
      raw_specialization: nil
    )
  end

  before { clear_enqueued_jobs }

  describe "#call" do
    context "when character does not exist" do
      let(:character) { nil }

      it "returns a success result with not_found context" do
        result = call_service

        expect(result).to be_success
        expect(result.context[:status]).to eq(:not_found)
      end
    end

    context "when a reusable snapshot exists" do
      # A previously processed entry serves as the metadata source
      let(:snapshot_entry) do
        create(
          :pvp_leaderboard_entry,
          character:                   character,
          pvp_leaderboard:             create(
            :pvp_leaderboard,
            pvp_season: create(:pvp_season),
            bracket:    "shuffle",
            region:     character.region
          ),
          snapshot_at:                 Time.current - 2.hours,
          item_level:                  540,
          tier_set_id:                 999,
          tier_set_name:               "Gladiator Set",
          tier_set_pieces:             4,
          tier_4p_active:              true,
          equipment_processed_at:      Time.current - 1.hour,
          specialization_processed_at: Time.current - 1.hour
        )
      end

      before do
        snapshot_entry  # force creation before service call
        character.update_columns(last_equipment_snapshot_at: 2.hours.ago)
      end

      it "reuses the snapshot for the latest entries" do
        result = call_service

        expect(result).to be_success
        expect(result.context[:status]).to eq(:reused_cache)

        expect(entry_2v2.reload.item_level).to eq(snapshot_entry.item_level)
        expect(entry_3v3.reload.item_level).to eq(snapshot_entry.item_level)
        expect(entry_2v2.reload.spec_id).to eq(snapshot_entry.spec_id)
      end

      it "does not call the Blizzard APIs" do
        expect(Blizzard::Api::Profile::CharacterEquipmentSummary).not_to receive(:fetch)
        expect(Blizzard::Api::Profile::CharacterSpecializationSummary).not_to receive(:fetch)

        call_service
      end

      it "does not enqueue any background jobs" do
        expect { call_service }.not_to have_enqueued_job
      end
    end

    context "when new data must be fetched" do
      let(:equipment_json) do
        JSON.parse(File.read("spec/fixtures/files/manongauz_equipment.json"))
      end

      let(:talents_json) do
        JSON.parse(File.read("spec/fixtures/files/manongauz_specializations.json"))
      end

      before do
        allow(Blizzard::Api::Profile::CharacterEquipmentSummary)
          .to receive(:fetch)
          .with(
            region: character.region,
            realm:  character.realm,
            name:   character.name,
            locale: Blizzard::Client.default_locale_for(character.region)
          )
          .and_return(equipment_json)

        allow(Blizzard::Api::Profile::CharacterSpecializationSummary)
          .to receive(:fetch)
          .with(
            region: character.region,
            realm:  character.realm,
            name:   character.name,
            locale: Blizzard::Client.default_locale_for(character.region)
          )
          .and_return(talents_json)

        allow(Pvp::Entries::ProcessEquipmentService).to receive(:call).and_return(
          ServiceResult.success(nil, context: {
            entry_attrs: { equipment_processed_at: Time.current, item_level: 540 }
          })
        )

        allow(Pvp::Entries::ProcessSpecializationService).to receive(:call).and_return(
          ServiceResult.success(nil, context: {
            entry_attrs: { specialization_processed_at: Time.current, spec_id: 71 }
          })
        )
      end

      it "fetches data and processes inline" do
        result = call_service

        expect(result).to be_success
        expect(result.context[:status]).to eq(:synced)

        expect(entry_2v2.reload.equipment_processed_at).to be_present
        expect(entry_3v3.reload.equipment_processed_at).to be_present
        expect(entry_2v2.reload.spec_id).to eq(71)
        expect(entry_3v3.reload.spec_id).to eq(71)
      end

      it "updates character last_equipment_snapshot_at" do
        expect { call_service }
          .to change { character.reload.last_equipment_snapshot_at }
          .from(nil)
      end
    end
  end
end
