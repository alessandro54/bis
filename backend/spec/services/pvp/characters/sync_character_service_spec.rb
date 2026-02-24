require "rails_helper"

RSpec.describe Pvp::Characters::SyncCharacterService do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

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

  let(:locale)    { "en_US" }
  let(:ttl_hours) { 24 }

  let!(:entry_2v2) do
    next unless character

    create(
      :pvp_leaderboard_entry,
      character:          character,
      pvp_leaderboard:    create(:pvp_leaderboard, pvp_season: create(:pvp_season), bracket: "2v2", region: character.region),
      raw_equipment:      nil,
      raw_specialization: nil
    )
  end

  let!(:entry_3v3) do
    next unless character

    create(
      :pvp_leaderboard_entry,
      character:          character,
      pvp_leaderboard:    create(:pvp_leaderboard, pvp_season: create(:pvp_season), bracket: "3v3", region: character.region),
      raw_equipment:      nil,
      raw_specialization: nil
    )
  end

  # A previously processed entry — used as the source for 304 fallback attrs.
  let!(:processed_entry) do
    next unless character

    create(
      :pvp_leaderboard_entry,
      character:                   character,
      pvp_leaderboard:             create(:pvp_leaderboard, pvp_season: create(:pvp_season), bracket: "shuffle", region: character.region),
      snapshot_at:                 2.hours.ago,
      item_level:                  540,
      tier_set_id:                 999,
      tier_set_name:               "Gladiator Set",
      tier_set_pieces:             4,
      tier_4p_active:              true,
      spec_id:                     71,
      hero_talent_tree_id:         1,
      hero_talent_tree_name:       "slayer",
      equipment_processed_at:      2.hours.ago,
      specialization_processed_at: 2.hours.ago
    )
  end

  before { clear_enqueued_jobs }

  # ---------------------------------------------------------------------------
  # Early exits
  # ---------------------------------------------------------------------------

  describe "#call" do
    context "when character does not exist" do
      let(:character) { nil }

      it "returns success with :not_found" do
        expect(call_service).to be_success
        expect(call_service.context[:status]).to eq(:not_found)
      end
    end

    context "when character is private" do
      before { character.update!(is_private: true) }

      it "returns success with :skipped_private" do
        expect(call_service).to be_success
        expect(call_service.context[:status]).to eq(:skipped_private)
      end
    end

    context "when character has no leaderboard entries" do
      before do
        character.pvp_leaderboard_entries.delete_all
      end

      it "returns success with :no_entries" do
        expect(call_service).to be_success
        expect(call_service.context[:status]).to eq(:no_entries)
      end
    end

    # -------------------------------------------------------------------------
    # TTL cache hit
    # -------------------------------------------------------------------------

    context "when a reusable snapshot exists (TTL hit)" do
      before do
        character.update_columns(last_equipment_snapshot_at: 2.hours.ago)
      end

      it "returns :reused_cache" do
        expect(call_service.context[:status]).to eq(:reused_cache)
      end

      it "propagates equipment and spec attrs to current entries" do
        call_service

        expect(entry_2v2.reload.item_level).to eq(processed_entry.item_level)
        expect(entry_2v2.reload.spec_id).to    eq(processed_entry.spec_id)
        expect(entry_3v3.reload.item_level).to eq(processed_entry.item_level)
      end

      it "does not call the Blizzard API" do
        expect(Blizzard::Api::Profile::CharacterEquipmentSummary).not_to     receive(:fetch_with_etag)
        expect(Blizzard::Api::Profile::CharacterSpecializationSummary).not_to receive(:fetch_with_etag)

        call_service
      end
    end

    # -------------------------------------------------------------------------
    # Blizzard API fetch helpers
    # -------------------------------------------------------------------------

    let(:equipment_json) do
      JSON.parse(File.read("spec/fixtures/files/manongauz_equipment.json"))
    end

    let(:talents_json) do
      JSON.parse(File.read("spec/fixtures/files/manongauz_specializations.json"))
    end

    let(:eq_etag_new)   { "etag-equipment-new" }
    let(:spec_etag_new) { "etag-talents-new" }

    # Stubs fetch_with_etag for equipment to return a 200 with a new ETag.
    def stub_equipment_changed
      allow(Blizzard::Api::Profile::CharacterEquipmentSummary)
        .to receive(:fetch_with_etag)
        .and_return([ equipment_json, eq_etag_new, true ])
    end

    # Stubs fetch_with_etag for equipment to return a 304 (unchanged).
    def stub_equipment_unchanged
      allow(Blizzard::Api::Profile::CharacterEquipmentSummary)
        .to receive(:fetch_with_etag)
        .and_return([ nil, character.equipment_etag, false ])
    end

    def stub_talents_changed
      allow(Blizzard::Api::Profile::CharacterSpecializationSummary)
        .to receive(:fetch_with_etag)
        .and_return([ talents_json, spec_etag_new, true ])
    end

    def stub_talents_unchanged
      allow(Blizzard::Api::Profile::CharacterSpecializationSummary)
        .to receive(:fetch_with_etag)
        .and_return([ nil, character.talents_etag, false ])
    end

    # Shared service stubs (used when the service is expected to be called).
    def stub_equipment_service_success
      allow(Pvp::Entries::ProcessEquipmentService).to receive(:call).and_return(
        ServiceResult.success(nil, context: {
          entry_attrs: { equipment_processed_at: Time.current, item_level: 610 }
        })
      )
    end

    def stub_spec_service_success
      allow(Pvp::Entries::ProcessSpecializationService).to receive(:call).and_return(
        ServiceResult.success(nil, context: {
          entry_attrs: { specialization_processed_at: Time.current, spec_id: 71 },
          char_attrs:  {}
        })
      )
    end

    # -------------------------------------------------------------------------
    # Both changed (normal 200/200 path)
    # -------------------------------------------------------------------------

    context "when both endpoints return 200 (new data)" do
      before do
        stub_equipment_changed
        stub_talents_changed
        stub_equipment_service_success
        stub_spec_service_success
      end

      it "returns :synced" do
        expect(call_service.context[:status]).to eq(:synced)
      end

      it "calls both processing services" do
        expect(Pvp::Entries::ProcessEquipmentService).to       receive(:call).once.and_call_original rescue nil
        expect(Pvp::Entries::ProcessSpecializationService).to receive(:call).once.and_call_original rescue nil
        stub_equipment_service_success
        stub_spec_service_success
        call_service
      end

      it "saves the new equipment ETag on the character" do
        call_service
        expect(character.reload.equipment_etag).to eq(eq_etag_new)
      end

      it "saves the new talents ETag on the character" do
        call_service
        expect(character.reload.talents_etag).to eq(spec_etag_new)
      end

      it "sets last_equipment_snapshot_at" do
        expect { call_service }
          .to change { character.reload.last_equipment_snapshot_at }
          .from(nil)
      end

      it "updates entry equipment_processed_at and spec_id" do
        call_service

        expect(entry_2v2.reload.equipment_processed_at).to be_present
        expect(entry_2v2.reload.spec_id).to eq(71)
        expect(entry_3v3.reload.equipment_processed_at).to be_present
        expect(entry_3v3.reload.spec_id).to eq(71)
      end
    end

    # -------------------------------------------------------------------------
    # Equipment unchanged (304), talents changed (200)
    # -------------------------------------------------------------------------

    context "when equipment returns 304 but talents return 200" do
      before do
        stub_equipment_unchanged
        stub_talents_changed
        stub_spec_service_success
      end

      it "returns :synced" do
        expect(call_service.context[:status]).to eq(:synced)
      end

      it "does not call ProcessEquipmentService" do
        expect(Pvp::Entries::ProcessEquipmentService).not_to receive(:call)
        call_service
      end

      it "copies equipment attrs from the latest processed entry" do
        call_service

        expect(entry_2v2.reload.item_level).to       eq(processed_entry.item_level)
        expect(entry_2v2.reload.tier_set_id).to      eq(processed_entry.tier_set_id)
        expect(entry_2v2.reload.equipment_processed_at).to be_present
      end

      it "does not overwrite the stored equipment ETag" do
        original_etag = character.equipment_etag
        call_service
        expect(character.reload.equipment_etag).to eq(original_etag)
      end

      it "saves the new talents ETag" do
        call_service
        expect(character.reload.talents_etag).to eq(spec_etag_new)
      end
    end

    # -------------------------------------------------------------------------
    # Equipment changed (200), talents unchanged (304)
    # -------------------------------------------------------------------------

    context "when equipment returns 200 but talents return 304" do
      before do
        stub_equipment_changed
        stub_talents_unchanged
        stub_equipment_service_success
      end

      it "returns :synced" do
        expect(call_service.context[:status]).to eq(:synced)
      end

      it "does not call ProcessSpecializationService" do
        expect(Pvp::Entries::ProcessSpecializationService).not_to receive(:call)
        call_service
      end

      it "copies spec attrs from the latest processed entry" do
        call_service

        expect(entry_2v2.reload.spec_id).to               eq(processed_entry.spec_id)
        expect(entry_2v2.reload.hero_talent_tree_id).to    eq(processed_entry.hero_talent_tree_id)
        expect(entry_2v2.reload.hero_talent_tree_name).to  eq(processed_entry.hero_talent_tree_name)
        expect(entry_2v2.reload.specialization_processed_at).to be_present
      end

      it "saves the new equipment ETag" do
        call_service
        expect(character.reload.equipment_etag).to eq(eq_etag_new)
      end

      it "does not overwrite the stored talents ETag" do
        original_etag = character.talents_etag
        call_service
        expect(character.reload.talents_etag).to eq(original_etag)
      end
    end

    # -------------------------------------------------------------------------
    # Both unchanged (304/304)
    # -------------------------------------------------------------------------

    context "when both endpoints return 304 (nothing changed)" do
      before do
        stub_equipment_unchanged
        stub_talents_unchanged
      end

      it "returns :synced" do
        expect(call_service.context[:status]).to eq(:synced)
      end

      it "does not call either processing service" do
        expect(Pvp::Entries::ProcessEquipmentService).not_to       receive(:call)
        expect(Pvp::Entries::ProcessSpecializationService).not_to  receive(:call)
        call_service
      end

      it "copies equipment attrs from the latest processed entry" do
        call_service
        expect(entry_2v2.reload.item_level).to eq(processed_entry.item_level)
      end

      it "copies spec attrs from the latest processed entry" do
        call_service
        expect(entry_2v2.reload.spec_id).to eq(processed_entry.spec_id)
      end

      it "still updates last_equipment_snapshot_at" do
        expect { call_service }
          .to change { character.reload.last_equipment_snapshot_at }
          .from(nil)
      end
    end

    # -------------------------------------------------------------------------
    # API errors
    # -------------------------------------------------------------------------

    context "when equipment fetch fails" do
      before do
        allow(Blizzard::Api::Profile::CharacterEquipmentSummary)
          .to receive(:fetch_with_etag)
          .and_raise(Blizzard::Client::Error, "timeout")

        stub_talents_changed
      end

      it "returns :equipment_unavailable" do
        expect(call_service.context[:status]).to eq(:equipment_unavailable)
      end

      it "does not set unavailable_until for non-404 errors" do
        call_service
        expect(character.reload.unavailable_until).to be_nil
      end
    end

    context "when equipment fetch returns 404" do
      before do
        allow(Blizzard::Api::Profile::CharacterEquipmentSummary)
          .to receive(:fetch_with_etag)
          .and_raise(Blizzard::Client::Error, "Blizzard API error: HTTP 404")

        stub_talents_changed
      end

      it "returns :equipment_unavailable" do
        expect(call_service.context[:status]).to eq(:equipment_unavailable)
      end

      it "sets unavailable_until 2 weeks from now" do
        freeze_time do
          call_service
          expect(character.reload.unavailable_until).to be_within(1.second).of(2.weeks.from_now)
        end
      end
    end

    context "when talents fetch fails" do
      before do
        stub_equipment_changed

        allow(Blizzard::Api::Profile::CharacterSpecializationSummary)
          .to receive(:fetch_with_etag)
          .and_raise(Blizzard::Client::Error, "timeout")
      end

      it "returns :talents_unavailable" do
        expect(call_service.context[:status]).to eq(:talents_unavailable)
      end
    end

    context "when a previously unavailable character syncs successfully" do
      before do
        character.update!(unavailable_until: 1.day.ago)
        stub_equipment_changed
        stub_talents_changed
        stub_equipment_service_success
        stub_spec_service_success
      end

      it "clears unavailable_until on success" do
        call_service
        expect(character.reload.unavailable_until).to be_nil
      end
    end
  end
end
