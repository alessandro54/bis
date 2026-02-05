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
    context "when equipment is already processed within TTL" do
      # Use a time within the default 1-hour TTL
      let(:equipment_processed_at) { 30.minutes.ago }

      before do
        # Ensure TTL is 1 hour for this test (dev .env sets it to 0)
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("EQUIPMENT_PROCESS_TTL_HOURS", 1).and_return(1)
        # Remove the default mock setup for this context
        RSpec::Mocks.space.proxy_for(Blizzard::Data::Items::UpsertFromRawEquipmentService).reset
      end

      it "returns success and does not call the Blizzard equipment service" do
        expect(Blizzard::Data::Items::UpsertFromRawEquipmentService).not_to receive(:new)

        res = result

        expect(res).to be_success
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

      it "returns attrs with processed equipment and tier set info" do
        now = Time.current

        res = result
        expect(res).to be_success

        attrs = res.context[:attrs]
        expect(attrs[:equipment_processed_at]).to be >= now
        expect(attrs[:item_level]).to eq(540)
        expect(attrs[:tier_set_id]).to eq(999)
        expect(attrs[:tier_set_name]).to eq("Gladiator Set")
        expect(attrs[:tier_set_pieces]).to eq(4)
        expect(attrs[:tier_4p_active]).to eq(true)
        expect(attrs[:raw_equipment]).to be_present
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

        it "returns attrs with processed_at and raw_equipment but no optional fields" do
          res = result
          attrs = res.context[:attrs]

          expect(attrs[:equipment_processed_at]).to be_present
          expect(attrs[:raw_equipment]).to be_present
          expect(attrs).not_to have_key(:item_level)
          expect(attrs).not_to have_key(:tier_set_id)
        end
      end

      it "provides a rebuild_items_proc that rebuilds associated pvp_leaderboard_entry_items" do
        old_item = create(:item)
        entry.pvp_leaderboard_entry_items.create!(
          item:       old_item,
          slot:       "CHEST",
          item_level: 500,
          context:    "old",
          raw:        {}
        )

        res = result
        # Simulate what ProcessEntryService does: call the rebuild proc inside a transaction
        ActiveRecord::Base.transaction do
          res.context[:rebuild_items_proc].call
        end
        entry.reload

        expect(entry.pvp_leaderboard_entry_items.count).to eq(1)

        created = entry.pvp_leaderboard_entry_items.first
        expect(created.item).to eq(item)
        expect(created.slot).to eq("HEAD")
        expect(created.item_level).to eq(540)
        expect(created.context).to eq("some_context")
        expect(created.raw["blizzard_id"]).to eq(blizzard_item_id)
        expect(created.raw["item_id"]).to eq(item.id)
        expect(created.raw["item_level"]).to eq(540)
      end
    end

    context "when an unexpected error occurs" do
      it "returns a failure wrapping the exception" do
        allow(Blizzard::Data::Items::UpsertFromRawEquipmentService)
          .to receive(:new)
                .and_raise(StandardError.new("unexpected error"))

        res = described_class.call(entry: entry, locale: locale)

        expect(res).to be_failure
        expect(res.error).to be_a(StandardError)
        expect(res.error.message).to eq("unexpected error")
      end
    end
  end
end
