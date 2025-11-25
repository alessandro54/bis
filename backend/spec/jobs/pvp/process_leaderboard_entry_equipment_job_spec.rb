# spec/jobs/pvp/process_leaderboard_entry_equipment_job_spec.rb
require "rails_helper"

RSpec.describe Pvp::ProcessLeaderboardEntryEquipmentJob, type: :job do
  let(:entry) do
    create(
      "pvp_leaderboard_entry",
      raw_equipment:          raw_equipment,
      equipment_processed_at: nil
    )
  end

  let(:locale)        { "en_US" }
  let(:now)           { Time.zone.parse("2024-01-01 00:00:00") }

  subject(:perform_job) do
    described_class.perform_now(entry_id: entry.id, locale: locale)
  end

  before do
    allow(Time.zone).to receive(:now).and_return(now)
  end

  context "when equipment_processed_at is already present" do
    let(:raw_equipment) { { "equipped_items" => [ { "id" => 1 } ] } }

    before do
      entry.update_column("equipment_processed_at", Time.zone.now)
    end

    it "does nothing" do
      expect(Blizzard::Data::Items::UpsertFromRawEquipmentService).not_to receive(:new)

      expect { perform_job }
        .not_to change { entry.reload.attributes }
    end
  end

  context "when raw_equipment is not a Hash" do
    let(:raw_equipment) { nil }

    it "does nothing" do
      expect(Blizzard::Data::Items::UpsertFromRawEquipmentService).not_to receive(:new)

      expect { perform_job }
        .not_to change { entry.reload.attributes }
    end
  end

  context "when raw_equipment does not contain 'equipped_items'" do
    let(:raw_equipment) { { "foo" => "bar" } }

    it "does nothing" do
      expect(Blizzard::Data::Items::UpsertFromRawEquipmentService).not_to receive(:new)

      expect { perform_job }
        .not_to change { entry.reload.attributes }
    end
  end

  context "when raw_equipment contains equipped_items" do
    let(:raw_equipment) do
      {
        "equipped_items" => [
          { "id" => 1, "slot" => { "type" => "HEAD" } }
        ]
      }
    end

    let(:processed_equipment) do
      {
        "equipped_items" => [
          { "id" => 1, "ilvl" => 540 }
        ]
      }
    end

    let(:tier_set_data) do
      {
        "tier_set_id" => 123,
        "tier_set_name" => "Gladiator Set",
        "tier_set_pieces" => 4,
        "tier_4p_active" => true
      }
    end

    let(:service_instance) do
      instance_double(
        Blizzard::Data::Items::UpsertFromRawEquipmentService,
        "item_level" => 540,
        "tier_set" => tier_set_data,
        "call" => processed_equipment
      )
    end

    before do
      allow(Blizzard::Data::Items::UpsertFromRawEquipmentService)
        .to receive(:new)
              .with(raw_equipment: raw_equipment, locale: locale)
              .and_return(service_instance)
    end

    it "initializes the equipment service correctly" do
      perform_job

      expect(Blizzard::Data::Items::UpsertFromRawEquipmentService)
        .to have_received(:new)
              .with(raw_equipment: raw_equipment, locale: locale)
    end

    it "updates the entry with item_level, processed equipment, tier set data and processed_at timestamp" do
      perform_job
      entry.reload

      expect(entry.item_level).to eq(540)
      expect(entry.raw_equipment).to eq(processed_equipment)
      expect(entry.tier_set_id).to eq(123)
      expect(entry.tier_set_name).to eq("Gladiator Set")
      expect(entry.tier_set_pieces).to eq(4)
      expect(entry.tier_4p_active).to eq(true)
      expect(entry.equipment_processed_at).to eq(now)
    end
  end
end
