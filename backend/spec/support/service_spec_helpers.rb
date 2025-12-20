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
          "item" => { "id" => blizzard_item_id },
          "slot" => { "type" => "HEAD" },
          "level" => { "value" => 540 },
          "context" => "some_context"
        }
      ]
    }
  end

  def processed_equipment
    raw_equipment
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
