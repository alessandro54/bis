require "rails_helper"

RSpec.describe Blizzard::Data::Items::UpsertFromRawEquipmentService do
  subject(:service) { described_class.new(raw_equipment: raw_equipment, locale: locale) }

  let(:locale) { "en_US" }

  # A realistic equipped item with enchantment + socket gem
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
          "quality" => { "type" => "EPIC" },
          "context" => "raid-normal",
          "enchantments" => [
            {
              "display_string" => "Enchanted: Chant of Leeching Fangs |A:Professions-ChatIcon-Quality-Tier3:20:20|a",
              "enchantment_id" => 7534,
              "enchantment_slot" => { "type" => "PERMANENT" },
              "source_item" => { "id" => 226_977 }
            }
          ],
          "sockets" => [
            { "socket_type" => { "type" => "PRISMATIC" }, "item" => { "id" => 213_746 } }
          ]
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
          "quality" => { "type" => "EPIC" },
          "context" => "raid-heroic"
        }
      ]
    }
  end

  describe "#call" do
    it "upserts equipped items with correct metadata" do
      expect { service.call }.to change(Item, :count).by_at_least(2)

      item = Item.find_by(blizzard_id: 12_345)
      expect(item.inventory_type).to eq("head")
      expect(item.item_class).to eq("armor")
      expect(item.item_subclass).to eq("plate")
      expect(item.blizzard_media_id).to eq(111)
      expect(item.quality).to eq("epic")
    end

    it "stores quality as a string on the Item record" do
      service.call

      item = Item.find_by(blizzard_id: 12_345)
      expect(item.quality).to eq("epic")
    end

    context "with socket gems" do
      it "upserts socket gems as Item stubs" do
        expect { service.call }.to change(Item, :count).by(4) # 2 equipped + 1 gem + 1 enchantment source

        gem_item = Item.find_by(blizzard_id: 213_746)
        expect(gem_item).to be_present
      end

      it "returns sockets with resolved DB item IDs" do
        result     = service.call
        head_entry = result["equipped_items"]["head"]

        gem_db_id = Item.find_by(blizzard_id: 213_746).id
        expect(head_entry["sockets"]).to eq([
          { "type" => "PRISMATIC", "item_id" => gem_db_id, "display_string" => nil }
        ])
      end

      it "does not duplicate a gem already present as an equipped item" do
        # If blizzard_id 213_746 happened to also be equipped, it should only appear once
        expect(Item).to receive(:insert_all).at_most(:once).and_call_original
        service.call
      end
    end

    context "with enchantments" do
      it "upserts enchantment stubs into the enchantments table" do
        expect { service.call }.to change(Enchantment, :count).by(1)

        enchantment = Enchantment.find_by(blizzard_id: 7534)
        expect(enchantment).to be_present
      end

      it "upserts the enchantment source scroll as an Item stub" do
        service.call

        source_item = Item.find_by(blizzard_id: 226_977)
        expect(source_item).to be_present
      end

      it "returns enchantment_id as the DB enchantment ID" do
        result     = service.call
        head_entry = result["equipped_items"]["head"]

        enchantment_db_id = Enchantment.find_by(blizzard_id: 7534).id
        expect(head_entry["enchantment_id"]).to eq(enchantment_db_id)
      end

      it "returns enchantment_source_item_id as the DB item ID" do
        result     = service.call
        head_entry = result["equipped_items"]["head"]

        source_item_db_id = Item.find_by(blizzard_id: 226_977).id
        expect(head_entry["enchantment_source_item_id"]).to eq(source_item_db_id)
      end

      it "is idempotent — re-running does not create duplicate enchantments" do
        service.call
        expect { service.call }.not_to change(Enchantment, :count)
      end
    end

    it "returns a hash with slot -> item mapping" do
      result = service.call

      expect(result["equipped_items"].keys).to contain_exactly("head", "chest")
    end

    it "includes item_id as the DB id in the returned structure" do
      result     = service.call
      head_entry = result["equipped_items"]["head"]

      db_item_id = Item.find_by(blizzard_id: 12_345).id
      expect(head_entry["blizzard_id"]).to eq(12_345)
      expect(head_entry["item_id"]).to eq(db_item_id)
      expect(head_entry["item_level"]).to eq(540)
      expect(head_entry["name"]).to eq("Helm of Valor")
      expect(head_entry["quality"]).to eq("epic")
      expect(head_entry["context"]).to eq("raid-normal")
    end

    it "upserts translations in bulk" do
      # 2 item names + 1 enchantment name
      expect { service.call }.to change(Translation, :count).by(3)

      item        = Item.find_by(blizzard_id: 12_345)
      translation = Translation.find_by(
        translatable_type: "Item",
        translatable_id:   item.id,
        locale:            locale,
        key:               "name"
      )
      expect(translation.value).to eq("Helm of Valor")
    end

    it "upserts enchantment name translations from display_string" do
      service.call

      enchantment = Enchantment.find_by(blizzard_id: 7534)
      translation = Translation.find_by(
        translatable_type: "Enchantment",
        translatable_id:   enchantment.id,
        locale:            locale,
        key:               "name"
      )
      expect(translation).to be_present
      expect(translation.value).to eq("Chant of Leeching Fangs")
    end

    it "does not create translations for gem or enchantment source stubs" do
      service.call

      gem_item    = Item.find_by(blizzard_id: 213_746)
      source_item = Item.find_by(blizzard_id: 226_977)
      expect(Translation.where(translatable: gem_item)).to be_empty
      expect(Translation.where(translatable: source_item)).to be_empty
    end

    context "when items already exist" do
      let!(:existing_item) { create(:item, blizzard_id: 12_345, quality: "rare") }

      it "updates existing items via upsert" do
        expect { service.call }.to change(Item, :count).by_at_least(1)

        existing_item.reload
        expect(existing_item.quality).to eq("epic")
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
        # +1 Chestplate name, +1 enchantment name (Helm name upserted, no new row)
        expect { service.call }.to change(Translation, :count).by(2)

        existing_translation.reload
        expect(existing_translation.value).to eq("Helm of Valor")
      end
    end

    context "with excluded slots" do
      let(:raw_equipment) do
        {
          "equipped_items" => [
            { "item" => { "id" => 99_001 }, "slot" => { "type" => "TABARD" }, "level" => { "value" => 1 },
"name" => "Guild Tabard" },
            { "item" => { "id" => 99_002 }, "slot" => { "type" => "SHIRT" },  "level" => { "value" => 1 },
"name" => "Fancy Shirt" },
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

      it "excludes TABARD and SHIRT slots from upsert" do
        expect { service.call }.to change(Item, :count).by(1)

        expect(Item.find_by(blizzard_id: 99_001)).to be_nil
        expect(Item.find_by(blizzard_id: 99_002)).to be_nil
        expect(Item.find_by(blizzard_id: 11_111)).to be_present
      end
    end

    context "with empty equipped_items" do
      let(:raw_equipment) { { "equipped_items" => [] } }

      it "returns empty hash structure without errors" do
        result = service.call

        expect(result).to eq({ "equipped_items" => {} })
        expect(Item.count).to eq(0)
        expect(Enchantment.count).to eq(0)
      end
    end
  end

  describe "#item_level" do
    it "calculates average item level across all equipped items" do
      service.call

      expect(service.item_level).to eq(542) # (540 + 545) / 2
    end

    context "with no valid items" do
      let(:raw_equipment) { { "equipped_items" => [] } }

      it "returns nil" do
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
              "quality" => { "type" => "EPIC" }
            }
          ]
        }
      end

      it "returns nil" do
        expect(service.tier_set).to be_nil
      end
    end
  end
end
