require "rails_helper"

RSpec.describe Pvp::ProcessLeaderboardEntryBatchJob, type: :job do
  include ActiveJob::TestHelper

  subject(:perform_job) do
    described_class.perform_now(
      entry_ids: entry_ids,
      locale:    locale
    )
  end

  # Create entries without equipment_processed_at so they pass the TTL filter
  let!(:entry1) { create(:pvp_leaderboard_entry, equipment_processed_at: nil) }
  let!(:entry2) { create(:pvp_leaderboard_entry, equipment_processed_at: nil) }
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

    it "preloads entries with characters using includes" do
      # The query now uses includes(:character) and filters by TTL
      expect(PvpLeaderboardEntry).to receive(:includes)
        .with(:character)
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

    context "when entry was recently processed (within TTL)" do
      before do
        # Ensure TTL is 1 hour for this test (dev .env sets it to 0)
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("EQUIPMENT_PROCESS_TTL_HOURS", 1).and_return(1)
      end

      let(:recently_processed_entry) do
        create(:pvp_leaderboard_entry, equipment_processed_at: 30.minutes.ago)
      end
      let(:entry_ids) { [ entry1.id, recently_processed_entry.id ] }

      it "skips the recently processed entry" do
        perform_job

        # Only entry1 should be processed (recently_processed_entry is skipped)
        expect(Pvp::Entries::ProcessEntryService)
          .to have_received(:call)
          .with(entry: entry1, locale: locale)
          .once
      end

      it "logs the skip count" do
        allow(Rails.logger).to receive(:info).and_call_original

        perform_job

        expect(Rails.logger).to have_received(:info).with(/Skipped 1\/2 already processed entries/)
      end
    end

    context "when all entries were recently processed" do
      before do
        # Ensure TTL is 1 hour for this test (dev .env sets it to 0)
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("EQUIPMENT_PROCESS_TTL_HOURS", 1).and_return(1)
      end

      let(:processed_entry1) { create(:pvp_leaderboard_entry, equipment_processed_at: 30.minutes.ago) }
      let(:processed_entry2) { create(:pvp_leaderboard_entry, equipment_processed_at: 30.minutes.ago) }
      let(:entry_ids) { [ processed_entry1.id, processed_entry2.id ] }

      it "returns early without processing any entries" do
        expect(Pvp::Entries::ProcessEntryService).not_to receive(:call)

        perform_job
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
