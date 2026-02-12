# spec/services/pvp/entries/process_entry_service_spec.rb
require "rails_helper"

RSpec.describe Pvp::Entries::ProcessEntryService, type: :service do
  let(:entry)  { create(:pvp_leaderboard_entry) }
  let(:locale) { "en_US" }

  subject(:result) { described_class.call(entry: entry, locale: locale) }

  describe "#call" do
    context "when entry is nil" do
      let(:entry) { nil }

      it "returns a failure with 'Entry not found'" do
        res = result

        expect(res).to be_failure
        expect(res.error).to eq("Entry not found")
      end
    end

    context "when equipment processing fails" do
      let(:equipment_result) { ServiceResult.failure("no equipment") }

      before do
        allow(Pvp::Entries::ProcessEquipmentService)
          .to receive(:call)
                .with(entry: entry, locale: locale)
                .and_return(equipment_result)

        allow(Pvp::Entries::ProcessSpecializationService)
          .to receive(:call)
      end

      it "returns the equipment failure result and does not call specialization service" do
        res = result

        expect(res).to eq(equipment_result)
        expect(res).to be_failure

        expect(Pvp::Entries::ProcessEquipmentService)
          .to have_received(:call)
                .with(entry: entry, locale: locale)

        expect(Pvp::Entries::ProcessSpecializationService)
          .not_to have_received(:call)
      end
    end

    context "when equipment processing succeeds but specialization fails" do
      let(:equipment_result)      { ServiceResult.success(entry) }
      let(:specialization_result) { ServiceResult.failure("no spec") }

      before do
        allow(Pvp::Entries::ProcessEquipmentService)
          .to receive(:call)
                .with(entry: entry, locale: locale)
                .and_return(equipment_result)

        allow(Pvp::Entries::ProcessSpecializationService)
          .to receive(:call)
                .with(entry: entry, locale: locale)
                .and_return(specialization_result)
      end

      it "returns the specialization failure result" do
        res = result

        expect(res).to eq(specialization_result)
        expect(res).to be_failure

        expect(Pvp::Entries::ProcessEquipmentService)
          .to have_received(:call)
                .with(entry: entry, locale: locale)

        expect(Pvp::Entries::ProcessSpecializationService)
          .to have_received(:call)
                .with(entry: entry, locale: locale)
      end
    end

    context "when both equipment and specialization succeed" do
      let(:equipment_result)      { ServiceResult.success(entry) }
      let(:specialization_result) { ServiceResult.success(entry) }

      before do
        allow(Pvp::Entries::ProcessEquipmentService)
          .to receive(:call)
                .with(entry: entry, locale: locale)
                .and_return(equipment_result)

        allow(Pvp::Entries::ProcessSpecializationService)
          .to receive(:call)
                .with(entry: entry, locale: locale)
                .and_return(specialization_result)
      end

      it "returns a success with the entry as payload" do
        res = result

        expect(res).to be_success
        expect(res.payload).to eq(entry)

        expect(Pvp::Entries::ProcessEquipmentService)
          .to have_received(:call)
                .with(entry: entry, locale: locale)

        expect(Pvp::Entries::ProcessSpecializationService)
          .to have_received(:call)
                .with(entry: entry, locale: locale)
      end
    end

    context "when an unexpected error is raised" do
      let(:boom) { StandardError.new("boom") }

      before do
        allow(Pvp::Entries::ProcessEquipmentService)
          .to receive(:call)
                .and_raise(boom)
      end

      it "wraps the exception in a failure ServiceResult" do
        res = result

        expect(res).to be_failure
        expect(res.error).to be_a(StandardError)
        expect(res.error.message).to eq("boom")
      end
    end
  end
end
