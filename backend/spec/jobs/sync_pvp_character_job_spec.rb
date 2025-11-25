# spec/jobs/sync_pvp_character_job_spec.rb
require "rails_helper"

RSpec.describe SyncPvpCharacterJob, type: :job do
  include ActiveJob::TestHelper

  let(:entry)     { create("pvp_leaderboard_entry") }
  let(:character) { entry.character }

  let(:region)    { "us" }
  let(:realm)     { "illidan" }
  let(:name)      { "manongauz" }
  let(:locale)    { "en_US" }

  subject(:perform_job) do
    described_class.perform_now(
      region:   region,
      realm:    realm,
      name:     name,
      entry_id: entry.id,
      locale:   locale
    )
  end

  context "when the character exists (valid profile)" do
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

    before do
      allow(Blizzard::Api::Profile::CharacterEquipmentSummary)
        .to receive(:fetch)
              .and_return(equipment_json)

      allow(Blizzard::Api::Profile::CharacterSpecializationSummary)
        .to receive(:fetch)
              .and_return(talents_json)

      clear_enqueued_jobs
    end

    it "updates the entry with raw equipment and specialization data" do
      perform_job
      entry.reload

      expect(entry.raw_equipment).to eq(equipment_json)
      expect(entry.raw_specialization).to eq(talents_json)
    end

    it "enqueues the equipment processing job" do
      expect do
        perform_job
      end.to have_enqueued_job(Pvp::ProcessLeaderboardEntryEquipmentJob).with(
        entry_id: entry.id,
        locale:   locale
      )
    end

    it "enqueues the specialization processing job" do
      expect do
        perform_job
      end.to have_enqueued_job(Pvp::ProcessLeaderboardEntrySpecializationJob).with(
        entry_id: entry.id,
        locale:   locale
      )
    end
  end

  context "when the character is private or deleted (404s)" do
    before do
      allow(Blizzard::Api::Profile::CharacterEquipmentSummary)
        .to receive(:fetch)
              .and_raise(Blizzard::Client::Error.new("HTTP 404"))

      clear_enqueued_jobs
    end

    it "does not update the entry" do
      expect do
        perform_job
      end.not_to change { entry.reload.updated_at }
    end

    it "does not enqueue processing jobs" do
      perform_job

      expect(Pvp::ProcessLeaderboardEntryEquipmentJob).not_to have_been_enqueued
      expect(Pvp::ProcessLeaderboardEntrySpecializationJob).not_to have_been_enqueued
    end
  end
end
