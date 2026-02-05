require "rails_helper"

RSpec.describe Pvp::SyncLeaderboardJob, type: :job do
  include ActiveJob::TestHelper

  subject(:perform_job) do
    described_class.perform_now(
      region:  region,
      season:  season,
      bracket: bracket,
      locale:  locale
    )
  end

  let(:region) { "us" }
  let(:locale) { "en_US" }
  let(:bracket) { "3v3" }
  let!(:season) { create(:pvp_season, blizzard_id: 37, is_current: true) }

  let(:api_response) do
    {
      "entries" => [
        {
          "character" => {
            "id" => 12_345,
            "name" => "TestPlayer",
            "realm" => { "slug" => "illidan" }
          },
          "faction" => { "type" => "HORDE" },
          "rank" => 1,
          "rating" => 2400,
          "season_match_statistics" => { "won" => 100, "lost" => 50 }
        },
        {
          "character" => {
            "id" => 67_890,
            "name" => "AnotherPlayer",
            "realm" => { "slug" => "tichondrius" }
          },
          "faction" => { "type" => "ALLIANCE" },
          "rank" => 2,
          "rating" => 2350,
          "season_match_statistics" => { "won" => 90, "lost" => 60 }
        }
      ]
    }
  end

  before do
    clear_enqueued_jobs

    allow(Blizzard::Api::GameData::PvpSeason::Leaderboard)
      .to receive(:fetch)
      .with(pvp_season_id: season.blizzard_id, bracket: bracket, region: region, locale: locale)
      .and_return(api_response)
  end

  describe "#perform" do
    it "fetches leaderboard data from Blizzard API" do
      expect(Blizzard::Api::GameData::PvpSeason::Leaderboard)
        .to receive(:fetch)
        .with(pvp_season_id: season.blizzard_id, bracket: bracket, region: region, locale: locale)

      perform_job
    end

    it "creates or updates the leaderboard record" do
      expect { perform_job }
        .to change(PvpLeaderboard, :count).by(1)

      leaderboard = PvpLeaderboard.last
      expect(leaderboard.bracket).to eq(bracket)
      expect(leaderboard.region).to eq(region)
      expect(leaderboard.pvp_season).to eq(season)
    end

    it "upserts characters from leaderboard entries" do
      expect { perform_job }
        .to change(Character, :count).by(2)

      character = Character.find_by(blizzard_id: 12_345)
      expect(character.name).to eq("TestPlayer")
      expect(character.realm).to eq("illidan")
      expect(character.region).to eq(region)
    end

    it "creates leaderboard entries" do
      expect { perform_job }
        .to change(PvpLeaderboardEntry, :count).by(2)
    end

    it "enqueues SyncCharacterBatchJob for new characters" do
      expect { perform_job }
        .to have_enqueued_job(Pvp::SyncCharacterBatchJob)
    end

    context "when characters were recently synced" do
      let!(:existing_character) do
        create(:character, blizzard_id: 12_345, region: region, name: "TestPlayer", realm: "illidan")
      end

      let!(:existing_entry) do
        create(
          :pvp_leaderboard_entry,
          character:              existing_character,
          equipment_processed_at: 30.minutes.ago
        )
      end

      it "skips recently synced characters" do
        perform_job

        # Get the enqueued job
        enqueued_job = enqueued_jobs.find { |job| job["job_class"] == "Pvp::SyncCharacterBatchJob" }
        expect(enqueued_job).to be_present

        # The recently synced character should not be in the batch
        character_ids = enqueued_job["arguments"].first["character_ids"]
        expect(character_ids).not_to include(existing_character.id)
      end

      it "logs the number of skipped characters" do
        allow(Rails.logger).to receive(:info).and_call_original

        perform_job

        expect(Rails.logger).to have_received(:info).with(/skipped \(recently synced\)/)
      end
    end

    context "when all characters were recently synced" do
      before do
        # Create existing characters with recent syncs
        api_response["entries"].each do |entry_data|
          char_data = entry_data["character"]
          char = create(
            :character,
            blizzard_id: char_data["id"],
            region:      region,
            name:        char_data["name"],
            realm:       char_data.dig("realm", "slug")
          )
          create(
            :pvp_leaderboard_entry,
            character:              char,
            equipment_processed_at: 30.minutes.ago
          )
        end
      end

      it "does not enqueue any SyncCharacterBatchJob" do
        expect { perform_job }
          .not_to have_enqueued_job(Pvp::SyncCharacterBatchJob)
      end
    end

    context "with rating filter" do
      let(:bracket) { "3v3" }

      before do
        # 3v3 has a rating_min of 2200
        api_response["entries"] << {
          "character" => {
            "id" => 11_111,
            "name" => "LowRatedPlayer",
            "realm" => { "slug" => "illidan" }
          },
          "faction" => { "type" => "HORDE" },
          "rank" => 100,
          "rating" => 2000, # Below 2200 threshold
          "season_match_statistics" => { "won" => 50, "lost" => 50 }
        }
      end

      it "filters out entries below the rating threshold" do
        perform_job

        # Should only have 2 entries (the ones with 2400 and 2350 rating)
        expect(PvpLeaderboardEntry.count).to eq(2)
        expect(Character.find_by(blizzard_id: 11_111)).to be_nil
      end
    end

    context "with batch size" do
      let(:bracket) { "2v2" } # Use 2v2 which has lower rating threshold (2000)

      before do
        # Clear existing entries
        api_response["entries"] = []

        # Create many entries to test batch slicing - all above 2000 rating
        250.times do |i|
          api_response["entries"] << {
            "character" => {
              "id" => 100_000 + i,
              "name" => "Player#{i}",
              "realm" => { "slug" => "illidan" }
            },
            "faction" => { "type" => "HORDE" },
            "rank" => i + 1,
            "rating" => 2500, # All above threshold
            "season_match_statistics" => { "won" => 100, "lost" => 50 }
          }
        end
      end

      it "enqueues batch jobs in chunks of configured batch size" do
        # Get the configured batch size (defaults to 50)
        batch_size = ENV.fetch("PVP_SYNC_BATCH_SIZE", 50).to_i
        expected_batches = (250.0 / batch_size).ceil

        perform_job

        # Verify batch jobs are enqueued based on configured batch size
        expect(Pvp::SyncCharacterBatchJob)
          .to have_been_enqueued
          .at_least(expected_batches).times
      end
    end
  end
end
