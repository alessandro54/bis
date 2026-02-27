require "rails_helper"

RSpec.describe Pvp::Characters::SyncCharacterService do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  subject(:call_service) do
    described_class.call(
      character: character,
      locale:    locale
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

  let!(:entry_2v2) do
    next unless character

    create(
      :pvp_leaderboard_entry,
      character:       character,
      pvp_leaderboard: create(
                                  :pvp_leaderboard,
                                  pvp_season: create(:pvp_season),
                                  bracket:    "2v2",
                                  region:     character.region),
    )
  end

  let!(:entry_3v3) do
    next unless character

    create(
      :pvp_leaderboard_entry,
      character:       character,
      pvp_leaderboard: create(
                                  :pvp_leaderboard,
                                  pvp_season: create(:pvp_season),
                                  bracket:    "3v3",
                                  region:     character.region),
    )
  end

  # A previously processed entry — used as the source for 304 fallback attrs.
  let!(:processed_entry) do
    next unless character

    create(
      :pvp_leaderboard_entry,
      character:                   character,
      pvp_leaderboard:             create(
                                  :pvp_leaderboard,
                                  pvp_season: create(:pvp_season),
                                  bracket:    "shuffle",
                                  region:     character.region),
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
    # Blizzard API fetch helpers
    # -------------------------------------------------------------------------

    let(:equipment_json) do
      JSON.parse(File.read("spec/fixtures/equipment/jw.json"))
    end

    let(:talents_json) do
      JSON.parse(File.read("spec/fixtures/specialization/jw.json"))
    end

    let(:eq_last_modified_new)   { "Wed, 4 Feb 2026 03:31:52 GMT" }
    let(:spec_last_modified_new) { "Wed, 4 Feb 2026 04:00:00 GMT" }
    let(:eq_last_modified_new_utc)   { Time.parse(eq_last_modified_new).utc }
    let(:spec_last_modified_new_utc) { Time.parse(spec_last_modified_new).utc }

    # Stubs fetch_with_last_modified for equipment to return a 200 with new Last-Modified.
    def stub_equipment_changed
      allow(Blizzard::Api::Profile::CharacterEquipmentSummary)
        .to receive(:fetch_with_last_modified)
        .and_return([ equipment_json, eq_last_modified_new, true ])
    end

    # Stubs fetch_with_last_modified for equipment to return a 304 (unchanged).
    def stub_equipment_unchanged
      allow(Blizzard::Api::Profile::CharacterEquipmentSummary)
        .to receive(:fetch_with_last_modified)
        .and_return([ nil, character.equipment_last_modified&.httpdate, false ])
    end

    def stub_talents_changed
      allow(Blizzard::Api::Profile::CharacterSpecializationSummary)
        .to receive(:fetch_with_last_modified)
        .and_return([ talents_json, spec_last_modified_new, true ])
    end

    def stub_talents_unchanged
      allow(Blizzard::Api::Profile::CharacterSpecializationSummary)
        .to receive(:fetch_with_last_modified)
        .and_return([ nil, character.talents_last_modified&.httpdate, false ])
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
        expect(Pvp::Entries::ProcessEquipmentService).to receive(:call).once.and_call_original rescue nil
        expect(Pvp::Entries::ProcessSpecializationService).to receive(:call).once.and_call_original rescue nil
        stub_equipment_service_success
        stub_spec_service_success
        call_service
      end

      it "saves the new equipment Last-Modified on the character as UTC" do
        call_service
        expect(character.reload.equipment_last_modified).to be_within(1.second).of(eq_last_modified_new_utc)
      end

      it "saves the new talents Last-Modified on the character as UTC" do
        call_service
        expect(character.reload.talents_last_modified).to be_within(1.second).of(spec_last_modified_new_utc)
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

      it "does not overwrite the stored equipment Last-Modified" do
        original_etag = character.equipment_last_modified
        call_service
        expect(character.reload.equipment_last_modified).to eq(original_etag)
      end

      it "saves the new talents Last-Modified" do
        call_service
        expect(character.reload.talents_last_modified).to be_within(1.second).of(spec_last_modified_new_utc)
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

        expect(entry_2v2.reload.spec_id).to eq(processed_entry.spec_id)
        expect(entry_2v2.reload.hero_talent_tree_id).to    eq(processed_entry.hero_talent_tree_id)
        expect(entry_2v2.reload.hero_talent_tree_name).to  eq(processed_entry.hero_talent_tree_name)
        expect(entry_2v2.reload.specialization_processed_at).to be_present
      end

      it "saves the new equipment Last-Modified" do
        call_service
        expect(character.reload.equipment_last_modified).to be_within(1.second).of(eq_last_modified_new_utc)
      end

      it "does not overwrite the stored talents Last-Modified" do
        original_etag = character.talents_last_modified
        call_service
        expect(character.reload.talents_last_modified).to eq(original_etag)
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
    # Stale Last-Modified clearing (no processed entries to fall back on)
    # -------------------------------------------------------------------------

    context "when character has Last-Modified but no processed entries exist" do
      before do
        # Remove the processed entry so 304 fallback has no source
        processed_entry.destroy!

        character.update_columns(
          equipment_last_modified: 1.day.ago,
          talents_last_modified:   1.day.ago
        )
      end

      it "clears Last-Modified timestamps before fetching" do
        stub_equipment_changed
        stub_talents_changed
        stub_equipment_service_success
        stub_spec_service_success

        call_service

        # After a successful 200 fetch, new Last-Modified values are written
        character.reload
        expect(character.equipment_last_modified).to be_within(1.second).of(eq_last_modified_new_utc)
        expect(character.talents_last_modified).to be_within(1.second).of(spec_last_modified_new_utc)
      end

      it "sends nil Last-Modified to Blizzard (forces 200)" do
        stub_equipment_changed
        stub_talents_changed
        stub_equipment_service_success
        stub_spec_service_success

        expect(Blizzard::Api::Profile::CharacterEquipmentSummary)
          .to receive(:fetch_with_last_modified)
          .with(hash_including(last_modified: nil))
          .and_return([ equipment_json, eq_last_modified_new, true ])

        expect(Blizzard::Api::Profile::CharacterSpecializationSummary)
          .to receive(:fetch_with_last_modified)
          .with(hash_including(last_modified: nil))
          .and_return([ talents_json, spec_last_modified_new, true ])

        call_service
      end
    end

    # -------------------------------------------------------------------------
    # API errors
    # -------------------------------------------------------------------------

    context "when equipment fetch fails" do
      before do
        allow(Blizzard::Api::Profile::CharacterEquipmentSummary)
          .to receive(:fetch_with_last_modified)
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
          .to receive(:fetch_with_last_modified)
          .and_raise(Blizzard::Client::NotFoundError, "Blizzard API error: HTTP 404")

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
          .to receive(:fetch_with_last_modified)
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
