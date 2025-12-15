require "rails_helper"

RSpec.describe Pvp::SyncCurrentSeasonLeaderboardsJob, type: :job do
  include ActiveJob::TestHelper

  let(:region) { "us" }
  let(:locale) { "en_US" }
  let(:season) { create(:pvp_season, is_current: true) }

  subject(:perform_job) do
    described_class.perform_now(
      region: region,
      locale: locale
    )
  end

  before do
    allow(PvpSeason).to receive(:current).and_return(season)
  end

  context "when a current season exists" do
    it "enqueues SyncLeaderboardJob for all brackets" do
      expect {
        perform_job
      }.to have_enqueued_job(Pvp::SyncLeaderboardJob).exactly(4).times

      expect(Pvp::SyncLeaderboardJob).to have_been_enqueued.with(
        region: region,
        season: season,
        bracket: "2v2",
        locale: locale
      )

      expect(Pvp::SyncLeaderboardJob).to have_been_enqueued.with(
        region: region,
        season: season,
        bracket: "3v3",
        locale: locale
      )

      expect(Pvp::SyncLeaderboardJob).to have_been_enqueued.with(
        region: region,
        season: season,
        bracket: "shuffle-overall",
        locale: locale
      )

      expect(Pvp::SyncLeaderboardJob).to have_been_enqueued.with(
        region: region,
        season: season,
        bracket: "rbg",
        locale: locale
      )
    end
  end

  context "when no current season exists" do
    before do
      allow(PvpSeason).to receive(:current).and_return(nil)
    end

    it "does not enqueue any jobs" do
      expect {
        perform_job
      }.not_to have_enqueued_job(Pvp::SyncLeaderboardJob)
    end
  end
end
