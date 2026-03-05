class Avo::Filters::SpecIdFilter < Avo::Filters::SelectFilter
  self.name = "Spec"

  def apply(request, query, value)
    query.where(spec_id: value.to_i)
  end

  def options
    Wow::Catalog.all_specs_with_slugs.map { |spec| [ spec[:id], spec[:spec_slug] ] }.to_h
  end
end
