# spec/services/pvp/entries/process_equipment_service_spec.rb
require "rails_helper"

RSpec.describe Pvp::Entries::ProcessEquipmentService, type: :service do
  include ServiceSpecHelpers
  include_examples "service result interface"
  let(:entry) do
    create(
      :pvp_leaderboard_entry,
      raw_equipment:          raw_equipment,
      equipment_processed_at: equipment_processed_at,
      item_level:             nil,
      tier_set_id:            nil,
      tier_set_name:          nil,
      tier_set_pieces:        nil,
      tier_4p_active:         nil
    )
  end

  let(:equipment_processed_at) { nil }
  let(:service_instance) { default_service_instance }
  let!(:item) { create(:item, blizzard_id: blizzard_item_id) }

  subject(:result) do
    described_class.call(entry: entry, locale: locale)
  end

  before do
    mock_equipment_service(service_instance)
  end

  describe "#call" do
    context "when equipment is already processed" do
      let(:equipment_processed_at) { Time.current }

      it "returns success and does not call the Blizzard equipment service" do
        expect(Blizzard::Data::Items::UpsertFromRawEquipmentService).not_to receive(:new)

        res = result

        expect(res).to be_success
        # si tu ServiceResult expone `payload`, comprueba:
        expect(res.payload).to eq(entry) if res.respond_to?(:payload)
      end
    end

    context "when raw_equipment is missing equipped_items" do
      let(:raw_equipment) { {} }

      it "returns a failure with a descriptive error" do
        res = result

        expect(res).to be_failure
        expect(res.error).to eq("Missing equipped_items in raw_equipment")
      end
    end

    context "when raw_equipment is nil" do
      let(:raw_equipment) { nil }

      it "returns a failure with a descriptive error" do
        res = result

        expect(res).to be_failure
        expect(res.error).to eq("Missing equipped_items in raw_equipment")
      end
    end

    context "when everything goes well" do
      it "calls the Blizzard equipment upsert service with the correct arguments" do
        result

        expect(Blizzard::Data::Items::UpsertFromRawEquipmentService)
          .to have_received(:new)
                .with(raw_equipment: raw_equipment, locale: locale)
      end

      it "updates the entry with processed equipment and tier set info" do
        now = Time.current

        res = result
        expect(res).to be_success

        entry.reload

        expect(entry.equipment_processed_at).not_to be_nil
        expect(entry.equipment_processed_at).to be >= now
        expect(entry.item_level).to eq(540)
        expect(entry.raw_equipment).to eq(processed_equipment)
        expect(entry.tier_set_id).to eq(999)
        expect(entry.tier_set_name).to eq("Gladiator Set")
        expect(entry.tier_set_pieces).to eq(4)
        expect(entry.tier_4p_active).to eq(true)
      end

      context "when the upsert service provides nil item level and tier set data" do
        let(:service_instance) do
          instance_double(
            Blizzard::Data::Items::UpsertFromRawEquipmentService,
            call:       processed_equipment,
            item_level: nil,
            tier_set:   nil
          )
        end

        it "still updates processed_at and raw_equipment but leaves optional fields nil" do
          result

          entry.reload

          expect(entry.equipment_processed_at).not_to be_nil
          expect(entry.item_level).to be_nil
          expect(entry.tier_set_id).to be_nil
          expect(entry.raw_equipment).to eq(processed_equipment)
        end
      end

      it "rebuilds the associated pvp_leaderboard_entry_items" do
        # Creamos un item previo para asegurarnos que se borra
        old_item = create(:item)
        entry.pvp_leaderboard_entry_items.create!(
          item:       old_item,
          slot:       "CHEST",
          item_level: 500,
          context:    "old",
          raw:        {}
        )

        result
        entry.reload

        expect(entry.pvp_leaderboard_entry_items.count).to eq(1)

        created = entry.pvp_leaderboard_entry_items.first
        expect(created.item).to eq(item)
        expect(created.slot).to eq("HEAD")
        expect(created.item_level).to eq(540)
        expect(created.context).to eq("some_context")
        # Raw now contains the processed structure with item_id
        expect(created.raw["blizzard_id"]).to eq(blizzard_item_id)
        expect(created.raw["item_id"]).to eq(item.id)
        expect(created.raw["item_level"]).to eq(540)
      end
    end

    context "when an error occurs while rebuilding items" do
      it "returns a failure and rolls back changes" do
        # stub para romper dentro de la transacción
        allow(entry.pvp_leaderboard_entry_items)
          .to receive(:delete_all)
                .and_call_original

        allow(PvpLeaderboardEntryItem)
          .to receive(:insert_all!)
                .and_raise(StandardError.new("DB error"))

        res = result

        expect(res).to be_failure
        expect(res.error).to be_a(StandardError)

        entry.reload
        expect(entry.equipment_processed_at).to be_nil
        expect(entry.pvp_leaderboard_entry_items).to be_empty
      end
    end
  end
end
