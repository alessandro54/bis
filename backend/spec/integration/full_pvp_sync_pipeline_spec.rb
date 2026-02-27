# spec/integration/full_pvp_sync_pipeline_spec.rb
#
# End-to-end integration test for the PvP sync pipeline.
#
# The three fixture characters (jw, egirlbooster, motívate) are placed on a
# 3v3/US leaderboard and processed through the full two-phase chain:
#
#   Phase 1  SyncCurrentSeasonLeaderboardsJob
#            → SyncLeaderboardService
#            → 3 characters upserted, 3 entries created
#
#   Phase 2  SyncCharacterBatchJob
#            → SyncCharacterService (per character)
#              → ProcessEquipmentService   (builds CharacterItem records)
#              → ProcessSpecializationService (builds CharacterTalent records)
#            → entries updated with item_level, spec_id, processed_at, …
#
# ─── Threading note ──────────────────────────────────────────────────────────
# ApplicationJob#run_with_threads spawns real threads. Those threads get their
# own DB connections and cannot see data inside the test transaction opened by
# DatabaseCleaner. To keep everything in the same transaction the stub below
# replaces run_with_threads with a synchronous map.
#
# SyncCharacterService#fetch_remote_data ALSO spawns two threads to hit the
# Blizzard API in parallel, but those threads only make HTTP calls — which are
# fully mocked — so they never touch the DB and are safe to leave as-is.
# ─────────────────────────────────────────────────────────────────────────────

require "rails_helper"

RSpec.describe "Full PvP sync pipeline", type: :integration do
  include ActiveJob::TestHelper

  # Make ApplicationJob#run_with_threads synchronous so DB ops share the test
  # transaction. The private method is accessible via allow_any_instance_of.
  before do
    allow_any_instance_of(ApplicationJob).to receive(:run_with_threads) do |_job, items, **_opts, &block|
      items.map { |item| block.call(item) }
    end
  end

  # ── Season ──────────────────────────────────────────────────────────────────

  let!(:season) { create(:pvp_season, blizzard_id: 37, is_current: true, display_name: "Season 14") }

  # ── Fixture payloads ────────────────────────────────────────────────────────

  let(:jw_equipment) do
    JSON.parse(File.read(Rails.root.join("spec/fixtures/equipment/jw.json")))
  end
  let(:jw_specialization) do
    JSON.parse(File.read(Rails.root.join("spec/fixtures/specialization/jw.json")))
  end

  let(:egirl_equipment) do
    JSON.parse(File.read(Rails.root.join("spec/fixtures/equipment/egirlbooster.json")))
  end
  let(:egirl_specialization) do
    JSON.parse(File.read(Rails.root.join("spec/fixtures/specialization/egirlbooster.json")))
  end

  let(:motivate_equipment) do
    JSON.parse(File.read(Rails.root.join("spec/fixtures/equipment/motívate.json")))
  end
  let(:motivate_specialization) do
    JSON.parse(File.read(Rails.root.join("spec/fixtures/specialization/motívate.json")))
  end

  # ── Blizzard leaderboard API response ───────────────────────────────────────
  # Mirrors the real character IDs from the profile fixtures so the characters
  # created by SyncLeaderboardService match what SyncCharacterService will look up.

  let(:leaderboard_response) do
    {
      "entries" => [
        {
          "character"               => { "id" => 177_763_085, "name" => "Jw",           "realm" => { "slug" => "malorne"  } },
          "faction"                 => { "type" => "ALLIANCE" },
          "rank"                    => 1,
          "rating"                  => 3100,
          "season_match_statistics" => { "won" => 300, "lost" => 50 }
        },
        {
          "character"               => { "id" => 202_523_551, "name" => "Egirlbooster", "realm" => { "slug" => "sargeras" } },
          "faction"                 => { "type" => "ALLIANCE" },
          "rank"                    => 2,
          "rating"                  => 3050,
          "season_match_statistics" => { "won" => 250, "lost" => 60 }
        },
        {
          "character"               => { "id" => 158_821_778, "name" => "Motívate",     "realm" => { "slug" => "sargeras" } },
          "faction"                 => { "type" => "ALLIANCE" },
          "rank"                    => 3,
          "rating"                  => 3000,
          "season_match_statistics" => { "won" => 200, "lost" => 70 }
        }
      ]
    }
  end

  # ── Global API stubs ────────────────────────────────────────────────────────

  before do
    clear_enqueued_jobs

    # --- Phase 1: bracket discovery (US=3v3, EU=nothing) --------------------
    allow(Blizzard::Api::GameData::PvpSeason::LeaderboardsIndex)
      .to receive(:fetch)
      .with(hash_including(region: "us"))
      .and_return({ "leaderboards" => [{ "name" => "3v3" }] })

    allow(Blizzard::Api::GameData::PvpSeason::LeaderboardsIndex)
      .to receive(:fetch)
      .with(hash_including(region: "eu"))
      .and_return({ "leaderboards" => [] })

    # --- Phase 1: leaderboard entries ---------------------------------------
    allow(Blizzard::Api::GameData::PvpSeason::Leaderboard)
      .to receive(:fetch)
      .with(hash_including(bracket: "3v3", region: "us"))
      .and_return(leaderboard_response)

    # --- Phase 2: equipment per character (matched by realm + name) ---------
    allow(Blizzard::Api::Profile::CharacterEquipmentSummary)
      .to receive(:fetch_with_last_modified)
      .with(hash_including(realm: "malorne"))
      .and_return([ jw_equipment, "Wed, 01 Jan 2026 12:00:00 GMT", true ])

    allow(Blizzard::Api::Profile::CharacterEquipmentSummary)
      .to receive(:fetch_with_last_modified)
      .with(hash_including(realm: "sargeras", name: "Egirlbooster"))
      .and_return([ egirl_equipment, "Wed, 01 Jan 2026 12:00:00 GMT", true ])

    allow(Blizzard::Api::Profile::CharacterEquipmentSummary)
      .to receive(:fetch_with_last_modified)
      .with(hash_including(realm: "sargeras", name: "Motívate"))
      .and_return([ motivate_equipment, "Wed, 01 Jan 2026 12:00:00 GMT", true ])

    # --- Phase 2: specialization per character ------------------------------
    allow(Blizzard::Api::Profile::CharacterSpecializationSummary)
      .to receive(:fetch_with_last_modified)
      .with(hash_including(realm: "malorne"))
      .and_return([ jw_specialization, "Wed, 01 Jan 2026 12:00:00 GMT", true ])

    allow(Blizzard::Api::Profile::CharacterSpecializationSummary)
      .to receive(:fetch_with_last_modified)
      .with(hash_including(realm: "sargeras", name: "Egirlbooster"))
      .and_return([ egirl_specialization, "Wed, 01 Jan 2026 12:00:00 GMT", true ])

    allow(Blizzard::Api::Profile::CharacterSpecializationSummary)
      .to receive(:fetch_with_last_modified)
      .with(hash_including(realm: "sargeras", name: "Motívate"))
      .and_return([ motivate_specialization, "Wed, 01 Jan 2026 12:00:00 GMT", true ])

    # Stub jobs that are out of scope for this test
    allow(::Characters::SyncCharacterMetaBatchJob).to receive(:perform_later)
    allow(Pvp::BuildAggregationsJob).to receive(:perform_later)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Phase 1 — SyncCurrentSeasonLeaderboardsJob
  # ═══════════════════════════════════════════════════════════════════════════

  describe "Phase 1 — leaderboard sync" do
    subject(:run_phase1) { Pvp::SyncCurrentSeasonLeaderboardsJob.perform_now }

    it "creates exactly 3 characters" do
      expect { run_phase1 }.to change(Character, :count).by(3)
    end

    it "creates the 3v3/US leaderboard" do
      run_phase1
      lb = PvpLeaderboard.find_by(bracket: "3v3", region: "us")
      expect(lb).to be_present
      expect(lb.pvp_season).to eq(season)
    end

    it "creates 3 entries with correct rank and rating" do
      run_phase1
      entries = PvpLeaderboardEntry.order(:rank)
      expect(entries.map(&:rank)).to   eq([ 1, 2, 3 ])
      expect(entries.map(&:rating)).to eq([ 3100, 3050, 3000 ])
      expect(entries.map(&:wins)).to   eq([ 300, 250, 200 ])
    end

    it "creates the entries without equipment data (not yet synced)" do
      run_phase1
      expect(PvpLeaderboardEntry.where.not(equipment_processed_at: nil).count).to eq(0)
    end

    it "creates a PvpSyncCycle in :syncing_characters status" do
      run_phase1
      cycle = PvpSyncCycle.last
      expect(cycle.status).to eq("syncing_characters")
      expect(cycle.expected_character_batches).to eq(1)
      expect(cycle.regions).to include("us")
    end

    it "enqueues one SyncCharacterBatchJob" do
      expect { run_phase1 }.to have_enqueued_job(Pvp::SyncCharacterBatchJob)
    end

    it "stores the correct character names and realms" do
      run_phase1
      expect(Character.pluck(:name)).to   contain_exactly("Jw", "Egirlbooster", "Motívate")
      expect(Character.pluck(:realm)).to  contain_exactly("malorne", "sargeras", "sargeras")
      expect(Character.pluck(:region).uniq).to eq([ "us" ])
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Phase 2 — SyncCharacterBatchJob
  # ═══════════════════════════════════════════════════════════════════════════

  describe "Phase 2 — character equipment and talent sync" do
    # Run phase 1 first to set up characters and entries
    before { Pvp::SyncCurrentSeasonLeaderboardsJob.perform_now }

    subject(:run_phase2) do
      Pvp::SyncCharacterBatchJob.perform_now(
        character_ids: Character.pluck(:id),
        locale:        "en_US",
        sync_cycle_id: PvpSyncCycle.last&.id
      )
    end

    it "sets equipment_processed_at on all 3 entries" do
      run_phase2
      expect(PvpLeaderboardEntry.where.not(equipment_processed_at: nil).count).to eq(3)
    end

    it "sets specialization_processed_at on all 3 entries" do
      run_phase2
      expect(PvpLeaderboardEntry.where.not(specialization_processed_at: nil).count).to eq(3)
    end

    it "sets item_level on all 3 entries" do
      run_phase2
      expect(PvpLeaderboardEntry.where.not(item_level: nil).count).to eq(3)
    end

    it "sets spec_id on all 3 entries" do
      run_phase2
      expect(PvpLeaderboardEntry.where.not(spec_id: nil).count).to eq(3)
    end

    it "creates CharacterItem records from the equipment fixtures" do
      expect { run_phase2 }.to change(CharacterItem, :count).by_at_least(3)
    end

    it "creates CharacterTalent records from the specialization fixtures" do
      expect { run_phase2 }.to change(CharacterTalent, :count).by_at_least(3)
    end

    it "sets last_equipment_snapshot_at on every character" do
      run_phase2
      Character.all.each do |char|
        expect(char.reload.last_equipment_snapshot_at).to be_present,
          "expected last_equipment_snapshot_at on #{char.name}"
      end
    end

    it "marks the PvpSyncCycle as completed" do
      run_phase2
      expect(PvpSyncCycle.last.reload.status).to eq("completed")
    end

    it "increments completed_character_batches to 1" do
      run_phase2
      cycle = PvpSyncCycle.last.reload
      expect(cycle.completed_character_batches).to eq(1)
      expect(cycle.expected_character_batches).to  eq(1)
    end

    it "triggers BuildAggregationsJob once all batches are done" do
      expect(Pvp::BuildAggregationsJob).to receive(:perform_later).once
      run_phase2
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Full end-to-end: both phases in sequence
  # ═══════════════════════════════════════════════════════════════════════════

  describe "full end-to-end pipeline" do
    it "starts from an empty DB and produces fully processed characters" do
      # ── Pre-conditions ──────────────────────────────────────────────────────
      expect(Character.count).to          eq(0)
      expect(PvpLeaderboard.count).to     eq(0)
      expect(PvpLeaderboardEntry.count).to eq(0)

      # ── Phase 1: leaderboard sync ───────────────────────────────────────────
      Pvp::SyncCurrentSeasonLeaderboardsJob.perform_now

      expect(Character.count).to          eq(3)
      expect(PvpLeaderboard.count).to     eq(1)
      expect(PvpLeaderboardEntry.count).to eq(3)

      # Entries exist but are not yet processed
      expect(PvpLeaderboardEntry.where.not(equipment_processed_at: nil).count).to eq(0)

      # ── Phase 2: character sync ─────────────────────────────────────────────
      Pvp::SyncCharacterBatchJob.perform_now(
        character_ids: Character.pluck(:id),
        locale:        "en_US",
        sync_cycle_id: PvpSyncCycle.last.id
      )

      # ── Characters ──────────────────────────────────────────────────────────
      expect(Character.count).to eq(3)
      expect(Character.pluck(:name)).to contain_exactly("Jw", "Egirlbooster", "Motívate")

      jw       = Character.find_by!(name: "Jw")
      egirl    = Character.find_by!(name: "Egirlbooster")
      motivate = Character.find_by!(name: "Motívate")

      expect(jw.realm).to       eq("malorne")
      expect(jw.region).to      eq("us")
      expect(egirl.realm).to    eq("sargeras")
      expect(motivate.realm).to eq("sargeras")

      [ jw, egirl, motivate ].each do |char|
        expect(char.reload.last_equipment_snapshot_at).to be_present,
          "expected last_equipment_snapshot_at on #{char.name}"
        expect(char.character_items.count).to be > 0,
          "expected CharacterItem records for #{char.name}"
        expect(char.character_talents.count).to be > 0,
          "expected CharacterTalent records for #{char.name}"
      end

      # ── Entries fully processed ──────────────────────────────────────────────
      PvpLeaderboardEntry.all.each do |entry|
        char_name = entry.character.name
        expect(entry.equipment_processed_at).to be_present,
          "entry #{entry.id} (#{char_name}) missing equipment_processed_at"
        expect(entry.specialization_processed_at).to be_present,
          "entry #{entry.id} (#{char_name}) missing specialization_processed_at"
        expect(entry.item_level).to be_present,
          "entry #{entry.id} (#{char_name}) missing item_level"
        expect(entry.spec_id).to be_present,
          "entry #{entry.id} (#{char_name}) missing spec_id"
      end

      # ── Leaderboard shape ────────────────────────────────────────────────────
      lb      = PvpLeaderboard.find_by!(bracket: "3v3", region: "us")
      entries = lb.entries.order(:rank)
      expect(entries.map(&:rank)).to   eq([ 1, 2, 3 ])
      expect(entries.map(&:rating)).to eq([ 3100, 3050, 3000 ])

      # ── Sync cycle ───────────────────────────────────────────────────────────
      cycle = PvpSyncCycle.last
      expect(cycle.status).to                          eq("completed")
      expect(cycle.completed_character_batches).to eq(1)
      expect(cycle.expected_character_batches).to  eq(1)
    end
  end
end
