# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pvp::Meta::ClassDistributionService do
  describe "#call" do
    it "ranks high-volume strong specs above low-volume strong specs" do
      season = create(:pvp_season, id: 40)
      leaderboard = create(:pvp_leaderboard, region: "us", pvp_season_id: season.id)

      # Characters (class_id/class_slug used by the service)
      rogue = create(:character, class_id: 4, class_slug: "rogue")
      hunter = create(:character, class_id: 3, class_slug: "hunter")

      # Snapshot scope expectation: we rely on latest_snapshot_for_bracket to return these entries.
      # The simplest approach is to stub it to return a relation containing our records.
      relation = PvpLeaderboardEntry.none

      # High-volume, strong spec (Assa 259)
      30.times do |i|
        entry = create(
          :pvp_leaderboard_entry,
          pvp_leaderboard: leaderboard,
          character: rogue,
          spec_id: 259,
          rating: 2400 + (i % 10),
          wins: 80,
          losses: 60
        )
        relation = relation.or(PvpLeaderboardEntry.where(id: entry.id))
      end

      # Low-volume, very strong spec (Outlaw 260) -> should not beat Assa overall
      2.times do |i|
        entry = create(
          :pvp_leaderboard_entry,
          pvp_leaderboard: leaderboard,
          character: rogue,
          spec_id: 260,
          rating: 2550 + (i % 2),
          wins: 90,
          losses: 50
        )
        relation = relation.or(PvpLeaderboardEntry.where(id: entry.id))
      end

      # Medium-volume, medium power (MM 254) just to add variety
      10.times do |i|
        entry = create(
          :pvp_leaderboard_entry,
          pvp_leaderboard: leaderboard,
          character: hunter,
          spec_id: 254,
          rating: 2300 + (i % 5),
          wins: 70,
          losses: 70
        )
        relation = relation.or(PvpLeaderboardEntry.where(id: entry.id))
      end

      allow(PvpLeaderboardEntry).to receive(:latest_snapshot_for_bracket)
        .with("2v2", season_id: season.id)
        .and_return(relation)

      service = described_class.new(season: season, bracket: "2v2", region: "us")
      rows = service.call

      expect(rows).not_to be_empty

      assa = rows.find { |r| r[:spec_id] == 259 }
      outlaw = rows.find { |r| r[:spec_id] == 260 }
      mm = rows.find { |r| r[:spec_id] == 254 }

      expect(assa).to be_present
      expect(outlaw).to be_present
      expect(mm).to be_present

      # Key behavior: low-volume "strong" spec should be penalized by volume_factor
      expect(outlaw[:volume_factor]).to be <= assa[:volume_factor]

      # Overall meta ranking should put Assa above Outlaw
      expect(assa[:meta_score]).to be > outlaw[:meta_score]

      # Sanity: scores are in range
      expect(assa[:meta_score]).to be_between(0.0, 1.0)
      expect(outlaw[:meta_score]).to be_between(0.0, 1.0)
    end

    it "only returns dps specs (role filter)" do
      season = create(:pvp_season, id: 40)
      leaderboard = create(:pvp_leaderboard, region: "us", pvp_season_id: season.id)

      priest = create(:character, class_id: 5, class_slug: "priest")

      entry = create(
        :pvp_leaderboard_entry,
        pvp_leaderboard: leaderboard,
        character: priest,
        spec_id: 256, # discipline priest (healer)
        rating: 2400,
        wins: 80,
        losses: 60
      )

      relation = PvpLeaderboardEntry.where(id: entry.id)

      allow(PvpLeaderboardEntry).to receive(:latest_snapshot_for_bracket)
        .with("2v2", season_id: season.id)
        .and_return(relation)

      service = described_class.new(season: season, bracket: "2v2", region: "us", role: "dps")
      rows = service.call

      expect(rows).to eq([])
    end
  end
end
