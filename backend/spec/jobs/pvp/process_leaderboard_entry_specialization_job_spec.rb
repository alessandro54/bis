# spec/jobs/pvp/process_leaderboard_entry_specialization_job_spec.rb
require "rails_helper"

RSpec.describe Pvp::ProcessLeaderboardEntrySpecializationJob, type: :job do
  let(:raw_specialization) { {} }

  let(:entry) do
    create(
      "pvp_leaderboard_entry",
      raw_specialization:          raw_specialization,
      specialization_processed_at: nil
    )
  end

  let(:character) { entry.character }

  let(:locale) { "en_US" }
  let(:now)    { Time.zone.parse("2024-01-01 00:00:00") }

  subject(:perform_job) do
    described_class.perform_now(entry_id: entry.id, locale: locale)
  end

  before do
    allow(Time.zone).to receive(:now).and_return(now)
  end

  context "when specialization_processed_at is already present" do
    let(:raw_specialization) do
      { "foo" => "bar" }
    end

    before do
      entry.update_column("specialization_processed_at", Time.zone.now)
    end

    it "does nothing" do
      expect(Blizzard::Data::CharacterEquipmentSpecializationsService).not_to receive(:new)

      expect { perform_job }
        .not_to change { entry.reload.attributes }
    end
  end

  context "when the specialization service has no usable data" do
    let(:raw_specialization) do
      { "foo" => "bar" }
    end

    let(:service_instance) do
      instance_double(
        Blizzard::Data::CharacterEquipmentSpecializationsService,
        "has_data?" => false
      )
    end

    before do
      allow(Blizzard::Data::CharacterEquipmentSpecializationsService)
        .to receive(:new)
              .with(raw_specialization)
              .and_return(service_instance)
    end

    it "does nothing" do
      expect { perform_job }
        .not_to change { entry.reload.attributes }
    end
  end

  context "when the specialization data is valid" do
    let(:raw_specialization) do
      {
        "active_specialization" => {
          "name" => "Holy",
          "id" => 65
        },
        "active_hero_tree" => {
          "name" => "Lightsmith",
          "id" => 380
        }
      }
    end

    let(:talents_payload) do
      {
        "talents" => [
          { "id" => 1, "name" => "Some Talent" }
        ]
      }
    end

    let(:service_instance) do
      instance_double(
        Blizzard::Data::CharacterEquipmentSpecializationsService,
        "has_data?" => true,
        "active_specialization" => { "name" => "Holy", "id" => 65 },
        "active_hero_tree" => { "name" => "Lightsmith", "id" => 380 },
        "talents" => talents_payload,
        "class_slug" => "paladin"
      )
    end

    before do
      allow(Blizzard::Data::CharacterEquipmentSpecializationsService)
        .to receive(:new)
              .with(raw_specialization)
              .and_return(service_instance)
    end

    it "initializes the specialization service" do
      perform_job

      expect(Blizzard::Data::CharacterEquipmentSpecializationsService)
        .to have_received(:new)
              .with(raw_specialization)
    end

    it "updates the entry with specialization, hero tree and processed timestamp" do
      perform_job
      entry.reload

      expect(entry.specialization_processed_at).to eq(now)
      expect(entry.spec).to eq("holy")
      expect(entry.spec_id).to eq(65)
      expect(entry.hero_talent_tree_name).to eq("lightsmith")
      expect(entry.hero_talent_tree_id).to eq(380)
      expect(entry.raw_specialization).to eq(talents_payload)
    end

    it "updates the character class_slug if present" do
      perform_job
      character.reload

      expect(character.class_slug).to eq("paladin")
    end
  end

  context "when specialization is valid but class_slug is empty" do
    let(:raw_specialization) do
      {
        "active_specialization" => { "name" => "Holy", "id" => 65 },
        "active_hero_tree" => { "name" => "Lightsmith", "id" => 380 }
      }
    end

    let(:service_instance) do
      instance_double(
        Blizzard::Data::CharacterEquipmentSpecializationsService,
        "has_data?" => true,
        "active_specialization" => { "name" => "Holy", "id" => 65 },
        "active_hero_tree" => { "name" => "Lightsmith", "id" => 380 },
        "talents" => { "talents" => [] },
        "class_slug" => nil
      )
    end

    before do
      allow(Blizzard::Data::CharacterEquipmentSpecializationsService)
        .to receive(:new)
              .with(raw_specialization)
              .and_return(service_instance)
    end

    it "does not update the character class_slug" do
      expect do
        perform_job
      end.not_to change { character.reload.class_slug }
    end
  end
end
