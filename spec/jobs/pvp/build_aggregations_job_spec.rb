require "rails_helper"

RSpec.describe Pvp::BuildAggregationsJob, type: :job do
  let(:season) { create(:pvp_season) }
  let(:cycle)  { create(:pvp_sync_cycle, pvp_season: season) }

  let(:success_result) do
    instance_double(ServiceResult, success?: true, context: { count: 5 }, error: nil)
  end
  let(:failure_result) do
    instance_double(ServiceResult, success?: false,
                                   context:  { count: 0 },
                                   error:    StandardError.new("agg failed"))
  end

  before do
    [
      Pvp::Meta::ItemAggregationService,
      Pvp::Meta::EnchantAggregationService,
      Pvp::Meta::GemAggregationService,
      Pvp::Meta::TalentAggregationService
    ].each { |svc| allow(svc).to receive(:call).and_return(success_result) }
  end

  describe "#perform with sync_cycle_id" do
    context "when all aggregations succeed" do
      it "promotes the cycle as live on the season" do
        described_class.new.perform(pvp_season_id: season.id, sync_cycle_id: cycle.id)

        expect(season.reload.live_pvp_sync_cycle_id).to eq(cycle.id)
      end

      it "sets cycle status to completed" do
        described_class.new.perform(pvp_season_id: season.id, sync_cycle_id: cycle.id)

        expect(cycle.reload.status).to eq("completed")
      end

      it "purges old cycle data after promoting" do
        old_cycle = create(:pvp_sync_cycle, pvp_season: season)
        season.update!(live_pvp_sync_cycle_id: old_cycle.id)
        old_item = create(:pvp_meta_item_popularity, pvp_season:        season,
                                                     pvp_sync_cycle_id: old_cycle.id)

        described_class.new.perform(pvp_season_id: season.id, sync_cycle_id: cycle.id)

        expect(PvpMetaItemPopularity.exists?(old_item.id)).to be(false)
        expect(season.reload.live_pvp_sync_cycle_id).to eq(cycle.id)
      end
    end

    context "when any aggregation fails" do
      before do
        allow(Pvp::Meta::ItemAggregationService).to receive(:call).and_return(failure_result)
      end

      it "does not promote the cycle" do
        described_class.new.perform(pvp_season_id: season.id, sync_cycle_id: cycle.id)

        expect(season.reload.live_pvp_sync_cycle_id).to be_nil
      end

      it "sets cycle status to failed" do
        described_class.new.perform(pvp_season_id: season.id, sync_cycle_id: cycle.id)

        expect(cycle.reload.status).to eq("failed")
      end

      it "deletes draft rows for the failed cycle" do
        draft = create(:pvp_meta_item_popularity, pvp_season:        season,
                                                  pvp_sync_cycle_id: cycle.id)

        described_class.new.perform(pvp_season_id: season.id, sync_cycle_id: cycle.id)

        expect(PvpMetaItemPopularity.exists?(draft.id)).to be(false)
      end

      it "captures failure to Sentry" do
        expect(Sentry).to receive(:capture_message).with(
          "Aggregation cycle failed — live data preserved",
          hash_including(extra: hash_including(cycle_id: cycle.id))
        )

        described_class.new.perform(pvp_season_id: season.id, sync_cycle_id: cycle.id)
      end
    end
  end

  describe "#perform without sync_cycle_id (legacy)" do
    it "runs aggregations without promoting any cycle" do
      described_class.new.perform(pvp_season_id: season.id)

      expect(season.reload.live_pvp_sync_cycle_id).to be_nil
    end
  end

  describe "abort guard" do
    context "when cycle is aborted" do
      let(:cycle) { create(:pvp_sync_cycle, pvp_season: season, status: :aborted) }

      it "skips aggregations entirely" do
        described_class.new.perform(pvp_season_id: season.id, sync_cycle_id: cycle.id)

        [
          Pvp::Meta::ItemAggregationService,
          Pvp::Meta::EnchantAggregationService,
          Pvp::Meta::GemAggregationService,
          Pvp::Meta::TalentAggregationService
        ].each { |svc| expect(svc).not_to have_received(:call) }
      end

      it "does not change cycle status" do
        described_class.new.perform(pvp_season_id: season.id, sync_cycle_id: cycle.id)

        expect(cycle.reload.status).to eq("aborted")
      end

      it "does not promote the cycle to live" do
        described_class.new.perform(pvp_season_id: season.id, sync_cycle_id: cycle.id)

        expect(season.reload.live_pvp_sync_cycle_id).to be_nil
      end
    end
  end
end
