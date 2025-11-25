# spec/jobs/pvp/leaderboard_entry_process_equipment_job_spec.rb
require "rails_helper"

RSpec.describe Pvp::LeaderboardEntryProcessEquipmentJob, type: :job do
  let(:locale) { "en_US" }
  let(:entry)  { create(:pvp_leaderboard_entry, raw_equipment: raw_equipment) }

  subject(:perform_job) do
    described_class.perform_now(entry_id: entry.id, locale: locale)
  end

  context "when raw_equipment is not a Hash" do
    let(:raw_equipment) { nil }

    it "does not initialize the service or update the entry" do
      expect(Blizzard::Data::Items::UpsertFromRawEquipmentService).not_to receive(:new)

      expect { perform_job }.not_to change { entry.reload.attributes }
    end
  end

  context "when raw_equipment is a Hash without equipped_items" do
    let(:raw_equipment) { { foo: "bar" } }

    it "does not initialize the service or update the entry" do
      expect(Blizzard::Data::Items::UpsertFromRawEquipmentService).not_to receive(:new)

      expect { perform_job }.not_to change { entry.reload.attributes }
    end
  end

  context "when raw_equipment contains equipped_items" do
    let(:raw_equipment) do
      {
        equipped_items: [
          { id: 1 }
        ]
      }.deep_stringify_keys!
    end

    let(:processed_equipment) do
      {
        equipped_items: [
          { id: 1, ilvl: 520 }
        ]
      }.deep_stringify_keys!
    end

    let(:tier_set_data) do
      {
        tier_set_id:     123,
        tier_set_name:   "Gladiator Set",
        tier_set_pieces: 4,
        tier_4p_active:  true
      }
    end

    let(:service_instance) do
      instance_double(
        Blizzard::Data::Items::UpsertFromRawEquipmentService,
        item_level: 672,
        tier_set:   tier_set_data,
        call:       processed_equipment
      )
    end

    before do
      allow(Blizzard::Data::Items::UpsertFromRawEquipmentService)
        .to receive(:new)
              .with(raw_equipment: raw_equipment, locale: locale)
              .and_return(service_instance)
    end

    it "initializes the equipment service" do
      perform_job

      expect(Blizzard::Data::Items::UpsertFromRawEquipmentService)
        .to have_received(:new)
              .with(raw_equipment: raw_equipment, locale: locale)
    end

    it "updates the entry with processed data" do
      perform_job
      entry.reload

      expect(entry.item_level).to eq(672)
      expect(entry.raw_equipment).to eq(processed_equipment)
      expect(entry.tier_set_id).to eq(123)
      expect(entry.tier_set_name).to eq("Gladiator Set")
      expect(entry.tier_set_pieces).to eq(4)
      expect(entry.tier_4p_active).to eq(true)
    end
  end
end
