require "rails_helper"

RSpec.describe Pvp::SyncCharacterBatchJob, type: :job do
  include ActiveJob::TestHelper

  subject(:perform_job) do
    described_class.perform_now(
      character_ids: character_ids,
      locale:        locale
    )
  end

  let!(:character1) { create(:character) }
  let!(:character2) { create(:character) }
  let(:character_ids) { [ character1.id, character2.id ] }
  let(:locale) { "en_US" }

  before do
    clear_enqueued_jobs
  end

  it "enqueues individual SyncCharacterJob for each character for parallel processing" do
    expect { perform_job }
      .to have_enqueued_job(Pvp::SyncCharacterJob)
      .exactly(2).times

    expect(Pvp::SyncCharacterJob).to have_been_enqueued.with(
      character_id:      character1.id,
      locale:            locale,
      processing_queues: nil
    )

    expect(Pvp::SyncCharacterJob).to have_been_enqueued.with(
      character_id:      character2.id,
      locale:            locale,
      processing_queues: nil
    )
  end

  context "with a single character" do
    let(:character_ids) { [ character1.id ] }

    it "enqueues one SyncCharacterJob" do
      expect { perform_job }
        .to have_enqueued_job(Pvp::SyncCharacterJob)
        .exactly(1).times
        .with(character_id: character1.id, locale: locale, processing_queues: nil)
    end
  end
end
