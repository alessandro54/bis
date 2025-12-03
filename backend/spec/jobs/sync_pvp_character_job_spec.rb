# spec/jobs/sync_pvp_character_job_spec.rb
require "rails_helper"

RSpec.describe SyncPvpCharacterJob, type: :job do
  include ActiveJob::TestHelper

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
    create(
      :pvp_leaderboard_entry,
      character:                   character,
      pvp_leaderboard:             create(
        :pvp_leaderboard,
        pvp_season: create(:pvp_season),
        bracket:    "2v2",
        region:     character.region
      ),
      raw_equipment:               nil,
      raw_specialization:          nil,
      equipment_processed_at:      nil,
      specialization_processed_at: nil
    )
  end

  let!(:entry_3v3) do
    create(
      :pvp_leaderboard_entry,
      character:                   character,
      pvp_leaderboard:             create(
        :pvp_leaderboard,
        pvp_season: create(:pvp_season),
        bracket:    "3v3",
        region:     character.region
      ),
      raw_equipment:               nil,
      raw_specialization:          nil,
      equipment_processed_at:      nil,
      specialization_processed_at: nil
    )
  end

  subject(:perform_job) do
    described_class.perform_now(
      character_id: character.id,
      locale:       locale
    )
  end

  before do
    clear_enqueued_jobs
  end

  context "when the character exists and Blizzard responds successfully" do
    let(:equipment_json) do
      JSON.parse(
        File.read("spec/fixtures/files/manongauz_equipment.json")
      )
    end

    let(:talents_json) do
      JSON.parse(
        File.read("spec/fixtures/files/manongauz_specializations.json")
      )
    end

    let(:ttl_hours) { 24 }

    before do
      # Force no reusable snapshot
      allow(Pvp::Characters::LastEquipmentSnapshotFinderService)
        .to receive(:call)
              .with(character_id: character.id, ttl_hours: ttl_hours)
              .and_return(nil)

      stub_const("SyncPvpCharacterJob::TTL_HOURS", ttl_hours)

      allow(Blizzard::Api::Profile::CharacterEquipmentSummary)
        .to receive(:fetch)
              .and_return(equipment_json)

      allow(Blizzard::Api::Profile::CharacterSpecializationSummary)
        .to receive(:fetch)
              .and_return(talents_json)
    end

    it "updates the latest entries per bracket with raw equipment and specialization data" do
      perform_job
      entry_2v2.reload
      entry_3v3.reload

      expect(entry_2v2.raw_equipment).to eq(equipment_json)
      expect(entry_2v2.raw_specialization).to eq(talents_json)

      expect(entry_3v3.raw_equipment).to eq(equipment_json)
      expect(entry_3v3.raw_specialization).to eq(talents_json)
    end

    it "enqueues a unified processing job for each latest entry" do
      expect do
        perform_job
      end.to have_enqueued_job(Pvp::ProcessLeaderboardEntryJob).exactly(2).times

      expect(Pvp::ProcessLeaderboardEntryJob)
        .to have_been_enqueued
              .with(entry_id: entry_2v2.id, locale: locale)

      expect(Pvp::ProcessLeaderboardEntryJob)
        .to have_been_enqueued
              .with(entry_id: entry_3v3.id, locale: locale)
    end
  end

  context "when Blizzard returns 404 (private or deleted profile)" do
    let(:ttl_hours) { 24 }

    before do
      allow(Pvp::Characters::LastEquipmentSnapshotFinderService)
        .to receive(:call)
              .with(character_id: character.id, ttl_hours: ttl_hours)
              .and_return(nil)

      stub_const("SyncPvpCharacterJob::TTL_HOURS", ttl_hours)

      allow(Blizzard::Api::Profile::CharacterEquipmentSummary)
        .to receive(:fetch)
              .and_raise(Blizzard::Client::Error.new("HTTP 404"))
    end

    it "does not update the entries" do
      expect do
        perform_job
      end.not_to change {
        [
          entry_2v2.reload.updated_at,
          entry_3v3.reload.updated_at
        ]
      }
    end

    it "does not enqueue processing jobs" do
      perform_job

      expect(Pvp::ProcessLeaderboardEntryJob).not_to have_been_enqueued
    end
  end
end