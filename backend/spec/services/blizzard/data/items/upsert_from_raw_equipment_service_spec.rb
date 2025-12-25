require "rails_helper"

RSpec.describe Blizzard::Data::Items::UpsertFromRawEquipmentService do
  subject(:service) { described_class.new(raw_equipment: raw_equipment, locale: locale) }

  let(:locale) { "en_US" }

  let(:raw_equipment) do
    {
      "equipped_items" => [
        {
          "item" => { "id" => 12_345 },
          "slot" => { "type" => "HEAD" },
          "level" => { "value" => 540 },
          "name" => "Helm of Valor",
          "inventory_type" => { "type" => "HEAD" },
          "item_class" => { "name" => "Armor" },
          "item_subclass" => { "name" => "Plate" },
          "media" => { "id" => 111 },
          "quality" => { "type" => "EPIC" }
        },
        {
          "item" => { "id" => 67_890 },
          "slot" => { "type" => "CHEST" },
          "level" => { "value" => 545 },
          "name" => "Chestplate of Might",
          "inventory_type" => { "type" => "CHEST" },
          "item_class" => { "name" => "Armor" },
          "item_subclass" => { "name" => "Plate" },
          "media" => { "id" => 222 },
          "quality" => { "type" => "EPIC" }
        }
      ]
    }
  end

  describe "#call" do
    it "upserts items to the database" do
      expect { service.call }
        .to change(Item, :count).by(2)

      item = Item.find_by(blizzard_id: 12_345)
      expect(item.inventory_type).to eq("head")
      expect(item.item_class).to eq("armor")
      expect(item.item_subclass).to eq("plate")
    end

    it "upserts translations in bulk" do
      expect { service.call }
        .to change(Translation, :count).by(2)

      item = Item.find_by(blizzard_id: 12_345)
      translation = Translation.find_by(
        translatable_type: "Item",
        translatable_id:   item.id,
        locale:            locale,
        key:               "name"
      )
      expect(translation.value).to eq("Helm of Valor")
    end

    it "uses upsert_all for translations instead of individual saves" do
      expect(Translation).to receive(:upsert_all).and_call_original

      service.call
    end

    context "when items already exist" do
      let!(:existing_item) { create(:item, blizzard_id: 12_345) }

      it "updates existing items" do
        expect { service.call }
          .to change(Item, :count).by(1) # Only one new item

        existing_item.reload
        expect(existing_item.inventory_type).to eq("head")
      end
    end

    context "when translations already exist" do
      let!(:existing_item) { create(:item, blizzard_id: 12_345) }
      let!(:existing_translation) do
        Translation.create!(
          translatable: existing_item,
          locale:       locale,
          key:          "name",
          value:        "Old Name",
          meta:         { source: "test" }
        )
      end

      it "updates existing translations" do
        expect { service.call }
          .to change(Translation, :count).by(1) # Only one new translation

        existing_translation.reload
        expect(existing_translation.value).to eq("Helm of Valor")
      end
    end

    context "with excluded slots" do
      let(:raw_equipment) do
        {
          "equipped_items" => [
            {
              "item" => { "id" => 12_345 },
              "slot" => { "type" => "TABARD" },
              "level" => { "value" => 1 },
              "name" => "Guild Tabard"
            },
            {
              "item" => { "id" => 67_890 },
              "slot" => { "type" => "SHIRT" },
              "level" => { "value" => 1 },
              "name" => "Fancy Shirt"
            },
            {
              "item" => { "id" => 11_111 },
              "slot" => { "type" => "HEAD" },
              "level" => { "value" => 540 },
              "name" => "Helm of Valor",
              "inventory_type" => { "type" => "HEAD" },
              "item_class" => { "name" => "Armor" },
              "item_subclass" => { "name" => "Plate" },
              "media" => { "id" => 111 },
              "quality" => { "type" => "EPIC" }
            }
          ]
        }
      end

      it "excludes TABARD and SHIRT slots" do
        expect { service.call }
          .to change(Item, :count).by(1)

        expect(Item.find_by(blizzard_id: 12_345)).to be_nil
        expect(Item.find_by(blizzard_id: 67_890)).to be_nil
        expect(Item.find_by(blizzard_id: 11_111)).to be_present
      end
    end

    context "with empty equipped_items" do
      let(:raw_equipment) { { "equipped_items" => [] } }

      it "returns early without errors" do
        expect { service.call }.not_to raise_error
        expect(Item.count).to eq(0)
      end
    end
  end

  describe "#item_level" do
    it "calculates average item level" do
      service.call

      expect(service.item_level).to eq(542) # (540 + 545) / 2
    end

    context "with no valid items" do
      let(:raw_equipment) { { "equipped_items" => [] } }

      it "returns nil" do
        service.call

        expect(service.item_level).to be_nil
      end
    end
  end

  describe "#tier_set" do
    let(:raw_equipment) do
      {
        "equipped_items" => [
          {
            "item" => { "id" => 12_345 },
            "slot" => { "type" => "HEAD" },
            "level" => { "value" => 540 },
            "name" => "Tier Helm",
            "inventory_type" => { "type" => "HEAD" },
            "item_class" => { "name" => "Armor" },
            "item_subclass" => { "name" => "Plate" },
            "media" => { "id" => 111 },
            "quality" => { "type" => "EPIC" },
            "set" => {
              "item_set" => { "id" => 999, "name" => "Gladiator Set" },
              "items" => [
                { "is_equipped" => true },
                { "is_equipped" => true },
                { "is_equipped" => true },
                { "is_equipped" => true },
                { "is_equipped" => false }
              ],
              "effects" => [
                { "required_count" => 2, "is_active" => true },
                { "required_count" => 4, "is_active" => true }
              ]
            }
          }
        ]
      }
    end

    it "extracts tier set information" do
      service.call
      tier_set = service.tier_set

      expect(tier_set[:tier_set_id]).to eq(999)
      expect(tier_set[:tier_set_name]).to eq("Gladiator Set")
      expect(tier_set[:tier_set_pieces]).to eq(4)
      expect(tier_set[:tier_4p_active]).to eq(true)
    end

    context "with no tier set" do
      let(:raw_equipment) do
        {
          "equipped_items" => [
            {
              "item" => { "id" => 12_345 },
              "slot" => { "type" => "HEAD" },
              "level" => { "value" => 540 },
              "name" => "Regular Helm",
              "inventory_type" => { "type" => "HEAD" },
              "item_class" => { "name" => "Armor" },
              "item_subclass" => { "name" => "Plate" },
              "media" => { "id" => 111 },
              "quality" => { "type" => "EPIC" }
            }
          ]
        }
      end

      it "returns nil" do
        service.call

        expect(service.tier_set).to be_nil
      end
    end
  end
end
