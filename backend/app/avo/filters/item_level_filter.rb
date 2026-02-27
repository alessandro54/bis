class Avo::Filters::ItemLevelFilter < Avo::Filters::SelectFilter
  self.name = "Min Item Level"

  def apply(request, query, value)
    query.where("item_level >= ?", value.to_i)
  end

  def options
    {
      "150+" => "150",
    }
  end
end
