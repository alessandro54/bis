# spec/services/pvp/entries/process_specialization_service_spec.rb
require "rails_helper"

RSpec.describe Pvp::Entries::ProcessSpecializationService, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  subject(:result) { described_class.call(entry: entry) }

  let(:entry)     { create(:pvp_leaderboard_entry, attrs_for_entry) }
  let(:character) { entry.character }

  let(:attrs_for_entry) do
    {
      raw_specialization:          raw_specialization,
      specialization_processed_at: specialization_processed_at
    }
  end

  # Ensure character starts with a different class_slug to avoid intermittent test failures
  before do
    character.update!(class_slug: "warrior", class_id: 1)
  end

  let(:raw_specialization)          { { "some" => "data" } }
  let(:specialization_processed_at) { nil }

  let(:spec_service_double) do
    instance_double(
      Blizzard::Data::CharacterEquipmentSpecializationsService,
      has_data?:             has_data,
      active_specialization: active_spec,
      active_hero_tree:      hero_tree,
      talents:               talents,
      class_slug:            class_slug
    )
  end

  let(:has_data) { true }
  let(:active_spec) do
    {
      "id" => 262,
      "name" => "Elemental"
    }
  end
  let(:hero_tree) do
    {
      "id" => 123,
      "name" => "Stormbringer"
    }
  end
  let(:talents)    { [ { "dummy" => "talent" } ] }
  let(:class_slug) { "Shaman" }
  let(:class_id)   { 7 }

  before do
    allow(Blizzard::Data::CharacterEquipmentSpecializationsService)
      .to receive(:new)
            .and_return(spec_service_double)

    allow(Wow::Catalog)
      .to receive(:class_id_for_spec)
            .with(active_spec["id"])
            .and_return(class_id)
  end

  context "when specialization is already processed" do
    let(:specialization_processed_at) { 1.hour.ago }

    it "returns success immediately" do
      result = described_class.call(entry: entry)

      expect(result).to be_success
      expect(result.payload).to eq(entry)
    end

    it "does not instantiate the Blizzard specialization service" do
      expect(Blizzard::Data::CharacterEquipmentSpecializationsService)
        .not_to receive(:new)

      described_class.call(entry: entry)
    end
  end

  context "when there is no specialization data" do
    let(:has_data) { false }

    it "returns a failure with a descriptive error" do
      res = result

      expect(res).to be_failure
      expect(res.error).to eq("No specialization data")

      expect(entry.reload.specialization_processed_at).to be_nil
    end
  end

  context "when everything goes well" do
    it "updates the entry with specialization info and talents" do
      freeze_time do
        res = result

        expect(res).to be_success
        entry.reload

        expect(entry.specialization_processed_at).to be_within(1.second).of(Time.current)
        expect(entry.spec_id).to eq(active_spec["id"])
        expect(entry.hero_talent_tree_name).to eq(hero_tree["name"].downcase)
        expect(entry.hero_talent_tree_id).to eq(hero_tree["id"])
        expect(entry.raw_specialization).to eq(talents)
      end
    end

    it "updates the character's class_slug (normalized) and class_id when class_slug is present" do
      expect do
        result
        character.reload
      end.to change(character, :class_slug)
               .to("shaman")
               .and change(character, :class_id)
                      .to(class_id)
    end

    it "does not change character class fields if class_slug is blank" do
      allow(spec_service_double).to receive(:class_slug).and_return(nil)

      expect do
        described_class.call(entry: entry)
        character.reload
      end.not_to change {
        [ character.class_slug, character.class_id ]
      }
    end
  end

  context "when an unexpected error happens" do
    before do
      allow(entry).to receive(:update!).and_raise(StandardError.new("boom"))
    end

    it "returns a failure with the exception as error" do
      res = result

      expect(res).to be_failure
      expect(res.error).to be_a(StandardError)
      expect(res.error.message).to eq("boom")
    end
  end
end
