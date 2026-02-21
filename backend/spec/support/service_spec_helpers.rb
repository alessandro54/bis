module ServiceSpecHelpers
  def mock_equipment_service(service_instance = nil)
    service_instance ||= default_service_instance

    allow(Blizzard::Data::Items::UpsertFromRawEquipmentService)
      .to receive(:new)
            .with(raw_equipment: raw_equipment, locale: locale)
            .and_return(service_instance)
  end

  def default_service_instance
    instance_double(
      Blizzard::Data::Items::UpsertFromRawEquipmentService,
      call:       processed_equipment,
      item_level: 540,
      tier_set:   tier_set_data
    )
  end

  def raw_equipment
    {
      "equipped_items" => [
        {
          "item"    => { "id" => blizzard_item_id },
          "slot"    => { "type" => "HEAD" },
          "level"   => { "value" => 540 },
          "context" => 26,
          "name"    => "Test Helm",
          "quality" => { "type" => "EPIC" },
          "bonus_list" => [ 10_397, 9438 ],
          "enchantments" => [
            {
              "enchantment_id"   => enchantment_blizzard_id,
              "enchantment_slot" => { "type" => "PERMANENT" },
              "source_item"      => { "id" => enchantment_source_blizzard_id }
            }
          ],
          "sockets" => [
            { "socket_type" => { "type" => "PRISMATIC" }, "item" => { "id" => socket_gem_blizzard_id } }
          ]
        }
      ]
    }
  end

  def processed_equipment
    {
      "equipped_items" => {
        "head" => {
          "blizzard_id"                => blizzard_item_id,
          "item_id"                    => item.id,
          "item_level"                 => 540,
          "name"                       => "Test Helm",
          "quality"                    => "epic",
          "context"                    => 26,
          "bonus_list"                 => [ 10_397, 9438 ],
          "enchantment_id"             => enchantment.id,
          "enchantment_source_item_id" => enchantment_source_item.id,
          "embellishment_spell_id"     => nil,
          "sockets"                    => [ { "type" => "PRISMATIC", "item_id" => socket_gem_item.id } ]
        }
      }
    }
  end

  def tier_set_data
    {
      tier_set_id:     999,
      tier_set_name:   "Gladiator Set",
      tier_set_pieces: 4,
      tier_4p_active:  true
    }
  end

  def enchantment
    @enchantment ||= create(:enchantment, blizzard_id: enchantment_blizzard_id)
  end

  def enchantment_source_item
    @enchantment_source_item ||= create(:item, blizzard_id: enchantment_source_blizzard_id)
  end

  def socket_gem_item
    @socket_gem_item ||= create(:item, blizzard_id: socket_gem_blizzard_id)
  end

  def blizzard_item_id
    123
  end

  def enchantment_blizzard_id
    7534
  end

  def enchantment_source_blizzard_id
    226_977
  end

  def socket_gem_blizzard_id
    213_746
  end

  def locale
    "en_US"
  end
end
