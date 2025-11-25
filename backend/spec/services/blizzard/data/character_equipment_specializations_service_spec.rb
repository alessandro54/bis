# spec/jobs/sync_pvp_character_job_spec.rb
require "rails_helper"

RSpec.describe SyncPvpCharacterJob do
  let(:entry)     { create(:pvp_leaderboard_entry) }
  let(:character) { entry.character }

  let(:region)    { "us" }
  let(:realm)     { "illidan" }
  let(:name)      { "manongauz" }
  let(:locale)    { "en_US" }

  subject(:job) do
    described_class.perform_now(
      region:, realm:, name:, entry_id: entry.id, locale:
    )
  end

  context "when the character exists (valid profile)" do
    let(:equipment_json) { JSON.parse(File.read("spec/fixtures/files/manongauz_equipment.json")) }
    let(:talents_json)   { JSON.parse(File.read("spec/fixtures/files/manongauz_specializations.json")) }

    before do
      allow(Blizzard::Api::Profile::CharacterEquipmentSummary)
        .to receive(:fetch).and_return(equipment_json)

      allow(Blizzard::Api::Profile::CharacterSpecializationSummary)
        .to receive(:fetch).and_return(talents_json)
    end

    it "updates the leaderboard entry with ilvl, talents and tier set" do
      job
      entry.reload

      expect(entry.item_level).to be_present
      expect(entry.raw_equipment).to be_present
      expect(entry.raw_specialization).to be_present
      expect(entry.spec).to be_present
      expect(entry.spec_id).to be_present
    end
  end

  context "when the character is private or deleted (404s)" do
    before do
      allow(Blizzard::Api::Profile::CharacterEquipmentSummary)
        .to receive(:fetch)
              .and_raise(Blizzard::Client::Error.new("HTTP 404"))

      # Specializations should NOT even be called
      expect(Blizzard::Api::Profile::CharacterSpecializationSummary)
        .not_to receive(:fetch)
    end

    it "does not update the entry" do
      expect { job }.not_to change { entry.reload.updated_at }
    end
  end
end
