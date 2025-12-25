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
          .with(character: character1, locale: locale, enqueue_processing: false)
          .and_return(ServiceResult.success(nil, context: { status: :applied_fresh_snapshot, entry_ids_to_process: [1, 2] }))

        allow(Pvp::Characters::SyncCharacterService).to receive(:call)
          .with(character: character2, locale: locale, enqueue_processing: false)
          .and_return(ServiceResult.success(nil, context: { status: :applied_fresh_snapshot, entry_ids_to_process: [3, 4] }))
      end

      it "batches all entry IDs and enqueues a single ProcessLeaderboardEntryBatchJob" do
        expect { perform_job }
          .to have_enqueued_job(Pvp::ProcessLeaderboardEntryBatchJob)
          .with(entry_ids: [1, 2, 3, 4], locale: locale)
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
        allow(Pvp::Characters::SyncCharacterService).to receive(:call)
          .with(character: character1, locale: locale, enqueue_processing: false)
          .and_return(ServiceResult.failure("API error"))

        allow(Pvp::Characters::SyncCharacterService).to receive(:call)
          .with(character: character2, locale: locale, enqueue_processing: false)
          .and_return(ServiceResult.success(nil, context: { status: :applied_fresh_snapshot, entry_ids_to_process: [3] }))
      end

      it "continues processing other characters and batches successful entries" do
        expect { perform_job }
          .to have_enqueued_job(Pvp::ProcessLeaderboardEntryBatchJob)
          .with(entry_ids: [3], locale: locale)

        expect(Pvp::Characters::SyncCharacterService)
          .to have_received(:call).twice
      end
    end

    context "when a Blizzard API error occurs" do
      before do
        allow(Pvp::Characters::SyncCharacterService).to receive(:call)
          .with(character: character1, locale: locale, enqueue_processing: false)
          .and_raise(Blizzard::Client::Error.new("Rate limited"))

        allow(Pvp::Characters::SyncCharacterService).to receive(:call)
          .with(character: character2, locale: locale, enqueue_processing: false)
          .and_return(ServiceResult.success(nil, context: { status: :no_entries }))
      end

      it "logs the error and continues with other characters" do
        expect(Rails.logger).to receive(:warn).with(/API error for character/)

        perform_job


        expect(Pvp::Characters::SyncCharacterService)
          .to have_received(:call).twice
      end
    end
  end
end
