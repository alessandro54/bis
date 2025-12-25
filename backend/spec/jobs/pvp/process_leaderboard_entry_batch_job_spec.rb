require "rails_helper"

RSpec.describe Pvp::ProcessLeaderboardEntryBatchJob, type: :job do
  include ActiveJob::TestHelper

  subject(:perform_job) do
    described_class.perform_now(
      entry_ids: entry_ids,
      locale:    locale
    )
  end

  let!(:entry1) { create(:pvp_leaderboard_entry) }
  let!(:entry2) { create(:pvp_leaderboard_entry) }
  let(:entry_ids) { [ entry1.id, entry2.id ] }
  let(:locale) { "en_US" }

  before do
    clear_enqueued_jobs

    # Mock the ProcessEntryService to avoid actual processing
    allow(Pvp::Entries::ProcessEntryService).to receive(:call)
      .and_return(ServiceResult.success(nil))
  end

  describe "#perform" do
    it "processes each entry directly using ProcessEntryService" do
      perform_job

      expect(Pvp::Entries::ProcessEntryService)
        .to have_received(:call)
        .with(entry: entry1, locale: locale)

      expect(Pvp::Entries::ProcessEntryService)
        .to have_received(:call)
        .with(entry: entry2, locale: locale)
    end

    it "preloads all entries in a single query" do
      expect(PvpLeaderboardEntry).to receive(:where)
        .with(id: entry_ids)
        .and_call_original

      perform_job
    end

    context "with a single entry" do
      let(:entry_ids) { [ entry1.id ] }

      it "processes the entry" do
        perform_job

        expect(Pvp::Entries::ProcessEntryService)
          .to have_received(:call)
          .with(entry: entry1, locale: locale)
          .once
      end
    end

    context "when entry_ids is empty" do
      let(:entry_ids) { [] }

      it "returns early without processing" do
        expect(Pvp::Entries::ProcessEntryService).not_to receive(:call)

        perform_job
      end
    end

    context "when entry_ids contains nil values" do
      let(:entry_ids) { [ entry1.id, nil, entry2.id ] }

      it "compacts the array and processes valid entries" do
        perform_job

        expect(Pvp::Entries::ProcessEntryService)
          .to have_received(:call).twice
      end
    end

    context "when an entry does not exist" do
      let(:entry_ids) { [ entry1.id, 999_999 ] }

      it "skips missing entries and processes existing ones" do
        perform_job

        expect(Pvp::Entries::ProcessEntryService)
          .to have_received(:call)
          .with(entry: entry1, locale: locale)
          .once
      end
    end

    context "when ProcessEntryService fails for one entry" do
      before do
        allow(Pvp::Entries::ProcessEntryService).to receive(:call)
          .with(entry: entry1, locale: locale)
          .and_return(ServiceResult.failure("Processing error"))

        allow(Pvp::Entries::ProcessEntryService).to receive(:call)
          .with(entry: entry2, locale: locale)
          .and_return(ServiceResult.success(nil))
      end

      it "logs the error and continues processing other entries" do
        expect(Rails.logger).to receive(:error).with(/Failed for entry #{entry1.id}/)

        perform_job

        expect(Pvp::Entries::ProcessEntryService)
          .to have_received(:call).twice
      end
    end

    context "when an unexpected error occurs" do
      before do
        allow(Pvp::Entries::ProcessEntryService).to receive(:call)
          .with(entry: entry1, locale: locale)
          .and_raise(StandardError.new("Unexpected error"))

        allow(Pvp::Entries::ProcessEntryService).to receive(:call)
          .with(entry: entry2, locale: locale)
          .and_return(ServiceResult.success(nil))
      end

      it "logs the error and continues with other entries" do
        expect(Rails.logger).to receive(:error).with(/Error for entry #{entry1.id}/)

        perform_job


        expect(Pvp::Entries::ProcessEntryService)
          .to have_received(:call).twice
      end
    end
  end
end
