require "rails_helper"

RSpec.describe Pvp::SyncCharacterBatchJob, type: :job do
  include ActiveJob::TestHelper

  subject(:perform_job) do
    described_class.perform_now(
      character_ids: character_ids,
      locale:        locale
    )
  end

  let!(:character1) { create(:character, is_private: false) }
  let!(:character2) { create(:character, is_private: false) }
  let(:character_ids) { [ character1.id, character2.id ] }
  let(:locale) { "en_US" }

  before do
    clear_enqueued_jobs

    # Mock the SyncCharacterService to avoid actual API calls
    allow(Pvp::Characters::SyncCharacterService).to receive(:call)
      .and_return(ServiceResult.success(nil, context: { status: :no_entries }))
  end

  describe "#perform" do
    it "processes each character directly using SyncCharacterService with enqueue_processing: false" do
      perform_job

      expect(Pvp::Characters::SyncCharacterService)
        .to have_received(:call)
        .with(character: character1, locale: locale, enqueue_processing: false)

      expect(Pvp::Characters::SyncCharacterService)
        .to have_received(:call)
        .with(character: character2, locale: locale, enqueue_processing: false)
    end

    it "preloads all characters in a single query" do
      expect(Character).to receive(:where)
        .with(id: character_ids)
        .and_call_original

      perform_job
    end

    context "when characters have entries to process" do
      before do
        allow(Pvp::Characters::SyncCharacterService).to receive(:call)
          .and_return(ServiceResult.success(nil,
context: { status: :applied_fresh_snapshot, entry_ids_to_process: [ 1, 2 ] }))
      end

      it "batches all entry IDs and enqueues a single ProcessLeaderboardEntryBatchJob" do
        expect { perform_job }
          .to have_enqueued_job(Pvp::ProcessLeaderboardEntryBatchJob)
          .exactly(:once)
      end
    end

    context "when no characters have entries to process" do
      before do
        allow(Pvp::Characters::SyncCharacterService).to receive(:call)
          .and_return(ServiceResult.success(nil, context: { status: :reused_snapshot }))
      end

      it "does not enqueue ProcessLeaderboardEntryBatchJob" do
        expect { perform_job }
          .not_to have_enqueued_job(Pvp::ProcessLeaderboardEntryBatchJob)
      end
    end

    context "with a single character" do
      let(:character_ids) { [ character1.id ] }

      it "processes the character" do
        perform_job

        expect(Pvp::Characters::SyncCharacterService)
          .to have_received(:call)
          .with(character: character1, locale: locale, enqueue_processing: false)
          .once
      end
    end

    context "when character_ids is empty" do
      let(:character_ids) { [] }

      it "returns early without processing" do
        expect(Pvp::Characters::SyncCharacterService).not_to receive(:call)

        perform_job
      end
    end

    context "when character_ids contains nil values" do
      let(:character_ids) { [ character1.id, nil, character2.id ] }

      it "compacts the array and processes valid characters" do
        perform_job

        expect(Pvp::Characters::SyncCharacterService)
          .to have_received(:call).twice
      end
    end

    context "with private characters" do
      let!(:private_character) { create(:character, is_private: true) }
      let(:character_ids) { [ character1.id, private_character.id ] }

      it "filters out private characters and does not process them" do
        perform_job

        expect(Pvp::Characters::SyncCharacterService)
          .to have_received(:call)
          .with(character: character1, locale: locale, enqueue_processing: false)

        expect(Pvp::Characters::SyncCharacterService)
          .not_to have_received(:call)
          .with(character: private_character, locale: anything, enqueue_processing: anything)
      end
    end

    context "when SyncCharacterService fails for one character" do
      before do
        call_count = 0
        allow(Pvp::Characters::SyncCharacterService).to receive(:call) do
          call_count += 1
          if call_count == 1
            ServiceResult.failure("API error")
          else
            ServiceResult.success(nil, context: { status: :applied_fresh_snapshot, entry_ids_to_process: [ 3 ] })
          end
        end
      end

      it "continues processing other characters and batches successful entries" do
        expect { perform_job }
          .to have_enqueued_job(Pvp::ProcessLeaderboardEntryBatchJob)

        expect(Pvp::Characters::SyncCharacterService)
          .to have_received(:call).twice
      end

      it "logs the batch summary" do
        allow(Rails.logger).to receive(:info).and_call_original

        perform_job

        expect(Rails.logger).to have_received(:info).with(/Batch complete: 1\/2 succeeded, 1 failed/)
      end
    end

    context "when a Blizzard API error occurs for one character" do
      before do
        call_count = 0
        allow(Pvp::Characters::SyncCharacterService).to receive(:call) do
          call_count += 1
          if call_count == 1
            raise Blizzard::Client::Error, "Server error"
          else
            ServiceResult.success(nil, context: { status: :no_entries })
          end
        end
      end

      it "logs the error and continues with other characters" do
        expect(Rails.logger).to receive(:warn).with(/API error for character/).at_least(:once)

        perform_job

        expect(Pvp::Characters::SyncCharacterService)
          .to have_received(:call).twice
      end
    end

    context "when all characters fail with Blizzard API errors" do
      before do
        allow(Pvp::Characters::SyncCharacterService).to receive(:call)
          .and_raise(Blizzard::Client::Error.new("Rate limited"))
      end

      it "raises TotalBatchFailureError" do
        expect { perform_job }
          .to raise_error(BatchOutcome::TotalBatchFailureError, /All 2 items failed/)
      end
    end

    context "when all characters fail with rate limiting" do
      before do
        allow(Pvp::Characters::SyncCharacterService).to receive(:call)
          .and_raise(Blizzard::Client::RateLimitedError.new("429"))
      end

      it "raises TotalBatchFailureError with rate_limited status" do
        expect { perform_job }
          .to raise_error(BatchOutcome::TotalBatchFailureError, /rate_limited: 2/)
      end
    end
  end
end
