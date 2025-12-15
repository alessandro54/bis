require "rails_helper"

RSpec.describe Pvp::SyncCharacterBatchJob, type: :job do
  include ActiveJob::TestHelper

  subject(:perform_job) do
    described_class.perform_now(
      character_ids: character_ids,
      locale:        locale
    )
  end

  let!(:character) { create(:character) }
  let(:character_ids) { [character.id] }
  let(:locale) { "en_US" }

  before do
    clear_enqueued_jobs
  end

  context "when the sync service succeeds" do
    before do
      allow(Pvp::Characters::SyncCharacterService)
        .to receive(:call)
        .and_return(ServiceResult.success)
    end

    it "does not enqueue fallback jobs" do
      expect { perform_job }.not_to have_enqueued_job(Pvp::SyncCharacterJob)
    end

    it "invokes the service for each character id" do
      perform_job

      expect(Pvp::Characters::SyncCharacterService).to have_received(:call).with(
        character: character,
        locale:    locale
      )
    end
  end

  context "when the sync service reports a failure" do
    let(:service_error) { StandardError.new("boom") }

    before do
      allow(Pvp::Characters::SyncCharacterService)
        .to receive(:call)
        .and_return(ServiceResult.failure(service_error))
    end

    it "enqueues an individual job for retry" do
      expect { perform_job }
        .to have_enqueued_job(Pvp::SyncCharacterJob)
        .with(character_id: character.id, locale: locale)
    end
  end

  context "when the service raises an unexpected error" do
    before do
      allow(Pvp::Characters::SyncCharacterService)
        .to receive(:call)
        .and_raise(StandardError, "unexpected boom")
    end

    it "enqueues an individual job for retry" do
      expect { perform_job }
        .to have_enqueued_job(Pvp::SyncCharacterJob)
        .with(character_id: character.id, locale: locale)
    end
  end
end
