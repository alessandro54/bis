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
          "item"       => { "id" => blizzard_item_id },
          "slot"       => { "type" => "HEAD" },
          "level"      => { "value" => 540 },
          "context"    => 26,
          "name"       => "Test Helm",
          "quality"    => { "type" => "EPIC" },
          "bonus_list" => [ 10397, 9438 ],
          "enchantments" => [
            {
              "enchantment_id"   => 7534,
              "enchantment_slot" => { "type" => "PERMANENT" },
              "source_item"      => { "id" => 226977 }
            }
          ],
          "sockets" => [ { "socket_type" => { "type" => "PRISMATIC" }, "item" => { "id" => 213746 } } ]
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
          "bonus_list"                 => [ 10397, 9438 ],
          "enchantment_id"             => 7534,
          "enchantment_source_item_id" => 226977,
          "embellishment_spell_id"     => nil,
          "sockets"                    => [ { "type" => "PRISMATIC", "item_id" => 213746 } ]
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

  def blizzard_item_id
    123
  end

  def locale
    "en_US"
  end
end
