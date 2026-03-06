require "rails_helper"

RSpec.describe Blizzard::Data::Talents::UpsertFromRawSpecializationService do
  # Uses the motívate fixture — Discipline Priest whose active loadout has
  # class talents with default_points > 0 (Improved Flash Heal dp=1, Mind Blast dp=1).
  let(:motivate_raw) do
    JSON.parse(File.read(Rails.root.join("spec/fixtures/specialization/motívate.json")))
  end

  let(:disc_spec) do
    svc = Blizzard::Data::CharacterEquipmentSpecializationsService.new(motivate_raw)
    svc.all_specializations.find { |s| s[:spec_id] == 256 }
  end

  let(:raw_spec) do
    disc_spec[:talents].merge(
      "pvp_talents" => disc_spec[:pvp_talents],
      "talent_loadout_code" => disc_spec[:talent_loadout_code]
    ).stringify_keys!
  end

  subject(:result) { described_class.call(raw_specialization: raw_spec) }

  describe "default_points in junction output" do
    it "propagates default_points > 0 from class talents" do
      class_records = result["class"]
      with_dp = class_records.select { |r| r[:default_points] > 0 }

      expect(with_dp.size).to be >= 2
      expect(with_dp).to all(include(default_points: 1))
    end

    it "sets default_points to 0 for class talents without them" do
      class_records = result["class"]
      without_dp = class_records.select { |r| r[:default_points] == 0 }

      expect(without_dp).not_to be_empty
    end

    it "sets default_points to 0 for pvp talents" do
      pvp_records = result["pvp"]
      expect(pvp_records).not_to be_empty
      expect(pvp_records).to all(include(default_points: 0))
    end

    it "includes talent_id in every junction record" do
      result.each_value do |records|
        Array(records).each { |r| expect(r[:talent_id]).to be_present }
      end
    end
  end

  describe "per-spec variation" do
    let(:shadow_spec) do
      svc = Blizzard::Data::CharacterEquipmentSpecializationsService.new(motivate_raw)
      svc.all_specializations.find { |s| s[:spec_id] == 258 }
    end

    let(:shadow_raw) do
      shadow_spec[:talents].merge(
        "pvp_talents" => shadow_spec[:pvp_talents],
        "talent_loadout_code" => shadow_spec[:talent_loadout_code]
      ).stringify_keys!
    end

    it "returns different default_points counts for Discipline vs Shadow" do
      disc_dp   = result["class"].count { |r| r[:default_points] > 0 }
      shadow_dp = described_class.call(raw_specialization: shadow_raw)["class"]
                    .count { |r| r[:default_points] > 0 }

      # Discipline has 2, Shadow has 4 based on fixture data
      expect(disc_dp).not_to eq(shadow_dp)
    end
  end

  describe "Talent records" do
    it "does not store default_points on the talents table" do
      result
      expect(Talent.column_names).not_to include("default_points")
    end
  end
end
