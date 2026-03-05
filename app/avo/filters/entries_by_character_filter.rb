class Avo::Filters::EntriesByCharacterFilter < Avo::Filters::TextFilter
  self.name = "Entries by Character"


  def apply(request, query, value)
    query.joins(:character).where("characters.name ILIKE ?", "%#{value}%")
  end
end
