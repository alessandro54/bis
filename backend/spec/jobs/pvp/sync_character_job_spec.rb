require "rails_helper"

RSpec.describe Pvp::SyncCharacterJob, type: :job do
  include ActiveJob::TestHelper

  let(:character) { create(:character) }
  let(:locale) { "pt_BR" }

  subject(:perform_job) do
    described_class.perform_now(
      character_id: character.id,
      locale:       locale
    )
  end

  let(:service_result) do
    instance_double(
      ServiceResult,
      success?: success,
      error:    service_error
    )
  end

  before do
    allow(Pvp::Characters::SyncCharacterService)
      .to receive(:call)
      .and_return(service_result)
  end

  context "when the service succeeds" do
    let(:success) { true }
    let(:service_error) { nil }

    it "delegates all work to the service" do
      perform_job

      expect(Pvp::Characters::SyncCharacterService).to have_received(:call).with(
        character: character,
        locale:    locale
      )
    end
  end

  context "when the service returns an exception" do
    let(:success) { false }
    let(:service_error) { StandardError.new("boom") }

    it "raises the same exception so the job is marked as failed" do
      expect { perform_job }.to raise_error(service_error.class, "boom")
    end
  end

  context "when the service returns a non-exception error" do
    let(:success) { false }
    let(:service_error) { "something went wrong" }

    it "wraps the error in a StandardError" do
      expect { perform_job }
        .to raise_error(StandardError, "[SyncCharacterJob] Failed for character #{character.id}: #{service_error}")
    end
  end
end
