require "rails_helper"

RSpec.describe Pvp::RecoverFailedCharacterSyncsJob, type: :job do
  let(:season) { create(:pvp_season) }
  let(:cycle) do
    create(:pvp_sync_cycle, pvp_season:                  season,
                            expected_character_batches:  2,
                            completed_character_batches: 2)
  end
  let(:bracket) { create(:pvp_leaderboard, pvp_season: season, bracket: "3v3", region: "us") }

  describe "#perform" do
    context "when all entries are synced" do
      before do
        create(:pvp_leaderboard_entry, pvp_leaderboard: bracket,
               equipment_processed_at: 1.hour.ago, specialization_processed_at: 1.hour.ago,
               sync_retry_count: 0)
      end

      it "enqueues BuildAggregationsJob and no SyncCharacterBatchJob" do
        expect(Pvp::BuildAggregationsJob).to receive(:perform_later)
          .with(pvp_season_id: season.id, sync_cycle_id: cycle.id)
        expect(Pvp::SyncCharacterBatchJob).not_to receive(:perform_later)

        described_class.new.perform(cycle.id)
      end
    end

    context "when recoverable entries exist (sync_retry_count < MAX_RETRIES)" do
      let!(:entry) do
        create(:pvp_leaderboard_entry, pvp_leaderboard: bracket,
               equipment_processed_at: nil, specialization_processed_at: nil,
               sync_retry_count: 0)
      end

      it "increments sync_retry_count and expected_character_batches" do
        allow(Pvp::SyncCharacterBatchJob).to receive(:perform_later)

        described_class.new.perform(cycle.id)

        expect(entry.reload.sync_retry_count).to eq(1)
        expect(cycle.reload.expected_character_batches).to eq(3)
      end

      it "enqueues SyncCharacterBatchJob with the character_id" do
        expect(Pvp::SyncCharacterBatchJob).to receive(:perform_later)
          .with(character_ids: [ entry.character_id ], sync_cycle_id: cycle.id)

        described_class.new.perform(cycle.id)
      end

      it "does not enqueue BuildAggregationsJob" do
        allow(Pvp::SyncCharacterBatchJob).to receive(:perform_later)
        expect(Pvp::BuildAggregationsJob).not_to receive(:perform_later)

        described_class.new.perform(cycle.id)
      end
    end

    context "when entries are exhausted (sync_retry_count == MAX_RETRIES)" do
      let!(:exhausted_entry) do
        create(:pvp_leaderboard_entry, pvp_leaderboard: bracket,
               equipment_processed_at: nil, specialization_processed_at: nil,
               sync_retry_count: Pvp::RecoverFailedCharacterSyncsJob::MAX_RETRIES)
      end

      it "sends a Sentry warning" do
        expect(Sentry).to receive(:capture_message).with(
          "Characters exhausted sync retries",
          hash_including(level: :warning)
        )
        allow(Pvp::BuildAggregationsJob).to receive(:perform_later)

        described_class.new.perform(cycle.id)
      end

      it "still enqueues BuildAggregationsJob (all exhausted = no recoverable left)" do
        allow(Sentry).to receive(:capture_message)
        expect(Pvp::BuildAggregationsJob).to receive(:perform_later)
          .with(pvp_season_id: season.id, sync_cycle_id: cycle.id)

        described_class.new.perform(cycle.id)
      end
    end

    context "with a mix of exhausted and recoverable entries" do
      let!(:exhausted_entry) do
        create(:pvp_leaderboard_entry, pvp_leaderboard: bracket,
               equipment_processed_at: nil, specialization_processed_at: nil,
               sync_retry_count: Pvp::RecoverFailedCharacterSyncsJob::MAX_RETRIES)
      end

      let!(:recoverable_entry) do
        create(:pvp_leaderboard_entry, pvp_leaderboard: bracket,
               equipment_processed_at: nil, specialization_processed_at: nil,
               sync_retry_count: 1)
      end

      it "warns on exhausted and re-queues recoverable only" do
        expect(Sentry).to receive(:capture_message).with(
          "Characters exhausted sync retries",
          hash_including(level: :warning)
        )
        expect(Pvp::SyncCharacterBatchJob).to receive(:perform_later)
          .with(character_ids: [ recoverable_entry.character_id ], sync_cycle_id: cycle.id)
        expect(Pvp::BuildAggregationsJob).not_to receive(:perform_later)

        described_class.new.perform(cycle.id)
      end
    end
  end
end
