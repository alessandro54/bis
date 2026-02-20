# spec/services/pvp/entries/process_equipment_service_spec.rb
require "rails_helper"

RSpec.describe Pvp::Entries::ProcessEquipmentService, type: :service do
  include ServiceSpecHelpers
  include_examples "service result interface"

  let!(:item)            { create(:item, blizzard_id: blizzard_item_id) }
  let(:character)        { create(:character) }
  let(:service_instance) { default_service_instance }

  subject(:result) do
    described_class.call(character: character, raw_equipment: raw_equipment, locale: locale)
  end

  before { mock_equipment_service(service_instance) }

  describe "#call" do
    context "when raw_equipment is missing equipped_items" do
      let(:raw_equipment) { {} }

      it "returns a failure" do
        expect(result).to be_failure
        expect(result.error).to eq("Missing equipped_items in raw_equipment")
      end
    end

    context "when raw_equipment is nil" do
      let(:raw_equipment) { nil }

      it "returns a failure" do
        expect(result).to be_failure
        expect(result.error).to eq("Missing equipped_items in raw_equipment")
      end
    end

    context "when everything goes well" do
      it "calls UpsertFromRawEquipmentService with the correct arguments" do
        result

        expect(Blizzard::Data::Items::UpsertFromRawEquipmentService)
          .to have_received(:new)
                .with(raw_equipment: raw_equipment, locale: locale)
      end

      it "returns entry_attrs with equipment metadata" do
        attrs = result.context[:entry_attrs]

        expect(result).to be_success
        expect(attrs[:equipment_processed_at]).to be_present
        expect(attrs[:item_level]).to eq(540)
        expect(attrs[:tier_set_id]).to eq(999)
        expect(attrs[:tier_set_name]).to eq("Gladiator Set")
        expect(attrs[:tier_set_pieces]).to eq(4)
        expect(attrs[:tier_4p_active]).to eq(true)
      end

      context "when the upsert service provides nil item level and tier set" do
        let(:service_instance) do
          instance_double(
            Blizzard::Data::Items::UpsertFromRawEquipmentService,
            call:       processed_equipment,
            item_level: nil,
            tier_set:   nil
          )
        end

        it "returns entry_attrs without optional fields" do
          attrs = result.context[:entry_attrs]

          expect(attrs[:equipment_processed_at]).to be_present
          expect(attrs).not_to have_key(:item_level)
          expect(attrs).not_to have_key(:tier_set_id)
        end
      end

      context "when equipment fingerprint has changed" do
        before { character.update_columns(equipment_fingerprint: "old:fingerprint") }

        it "replaces character_items with the new equipment" do
          old_item = create(:item)
          character.character_items.create!(item: old_item, slot: "CHEST", item_level: 500)

          result
          character.reload

          expect(character.character_items.count).to eq(1)
          created = character.character_items.first
          expect(created.item).to eq(item)
          expect(created.slot).to eq("HEAD")
          expect(created.item_level).to eq(540)
          expect(created.enchantment_id).to eq(7534)
          expect(created.enchantment_source_item_id).to eq(enchantment_source_item.id)
          expect(created.bonus_list).to eq([ 10_397, 9438 ])
          expect(created.sockets).to eq([ { "type" => "PRISMATIC", "item_id" => 213_746 } ])
        end

        it "updates the character's equipment_fingerprint" do
          expect { result }.to change { character.reload.equipment_fingerprint }
        end
      end

      context "when equipment fingerprint is already current" do
        before do
          # Fingerprint computed from raw data: slot:blizzard_id:ilvl:enchantment_id
          character.update_columns(equipment_fingerprint: "head:#{blizzard_item_id}:540:7534")
        end

        it "does not call UpsertFromRawEquipmentService" do
          expect(Blizzard::Data::Items::UpsertFromRawEquipmentService).not_to receive(:new)
          result
        end

        it "does not touch character_items" do
          expect { result }.not_to change { character.character_items.count }
        end

        it "does not update the fingerprint" do
          expect { result }.not_to change { character.reload.equipment_fingerprint }
        end

        it "still returns entry_attrs with equipment_processed_at" do
          expect(result).to be_success
          expect(result.context[:entry_attrs][:equipment_processed_at]).to be_present
        end
      end
    end

    context "when an unexpected error occurs" do
      it "returns a failure wrapping the exception" do
        allow(Blizzard::Data::Items::UpsertFromRawEquipmentService)
          .to receive(:new)
                .and_raise(StandardError.new("unexpected error"))

        expect(result).to be_failure
        expect(result.error).to be_a(StandardError)
        expect(result.error.message).to eq("unexpected error")
      end
    end
  end
end
