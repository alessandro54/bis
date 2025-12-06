# spec/jobs/pvp/sync_character_job_spec.rb
require "rails_helper"

RSpec.describe Pvp::SyncCharacterJob, type: :job do
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

  subject(:perform_job) do
    described_class.perform_now(
      character_id: character.id,
      locale:       locale
    )
  end

  before { clear_enqueued_jobs }

  context "when a reusable snapshot exists" do
    let(:ttl_hours) { 24 }

    before do
      now = Time.zone.parse("2024-01-01 12:00:00")

      entry_2v2.update!(snapshot_at: now)
      entry_3v3.update!(snapshot_at: now)

      @snapshot_entry = create(
        :pvp_leaderboard_entry,
        character:                   character,
        pvp_leaderboard:             create(
          :pvp_leaderboard,
          pvp_season: create(:pvp_season),
          bracket:    "2v2",
          region:     character.region
        ),
        snapshot_at:                 now - 2.hours,
        raw_equipment:               { "foo" => "bar" },
        raw_specialization:          { "spec" => "data" },
        item_level:                  540,
        tier_set_id:                 999,
        tier_set_name:               "Gladiator Set",
        tier_set_pieces:             4,
        tier_4p_active:              true,
        equipment_processed_at:      now - 1.hour,
        specialization_processed_at: now - 1.hour
      )

      allow(Pvp::Characters::LastEquipmentSnapshotFinderService)
        .to receive(:call)
              .with(character_id: character.id, ttl_hours: ttl_hours)
              .and_return(@snapshot_entry)

      stub_const("Pvp::SyncCharacterJob::TTL_HOURS", ttl_hours)
    end

    it "reuses the snapshot for the latest entries and does not call Blizzard" do
      perform_job

      entry_2v2.reload
      entry_3v3.reload

      expect(entry_2v2.raw_equipment).to eq(@snapshot_entry.raw_equipment)
      expect(entry_3v3.raw_equipment).to eq(@snapshot_entry.raw_equipment)

      expect(entry_2v2.raw_specialization).to eq(@snapshot_entry.raw_specialization)
      expect(entry_3v3.raw_specialization).to eq(@snapshot_entry.raw_specialization)

      expect(entry_2v2.item_level).to eq(@snapshot_entry.item_level)
      expect(entry_3v3.item_level).to eq(@snapshot_entry.item_level)
    end

    it "does NOT enqueue processing jobs when snapshot is fully processed" do
      expect { perform_job }.not_to have_enqueued_job(Pvp::ProcessLeaderboardEntryJob)
    end
  end

  context "when Blizzard returns new data" do
    let(:equipment_json) do
      JSON.parse(File.read("spec/fixtures/files/manongauz_equipment.json"))
    end

    let(:talents_json) do
      JSON.parse(File.read("spec/fixtures/files/manongauz_specializations.json"))
    end

    let(:ttl_hours) { 24 }

    before do
      allow(Pvp::Characters::LastEquipmentSnapshotFinderService)
        .to receive(:call)
              .with(character_id: character.id, ttl_hours: ttl_hours)
              .and_return(nil)

      stub_const("Pvp::SyncCharacterJob::TTL_HOURS", ttl_hours)

      allow(Blizzard::Api::Profile::CharacterEquipmentSummary)
        .to receive(:fetch)
              .and_return(equipment_json)

      allow(Blizzard::Api::Profile::CharacterSpecializationSummary)
        .to receive(:fetch)
              .and_return(talents_json)
    end

    it "updates all latest entries with fresh raw data" do
      perform_job

      entry_2v2.reload
      entry_3v3.reload

      expect(entry_2v2.raw_equipment).to eq(equipment_json)
      expect(entry_3v3.raw_equipment).to eq(equipment_json)
    end

    it "enqueues a unified processing job for each latest entry" do
      expect { perform_job }
        .to have_enqueued_job(Pvp::ProcessLeaderboardEntryJob).exactly(2).times
    end
  end
end
