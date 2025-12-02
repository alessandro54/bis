# lib/wow/specs.rb
module Wow
  module Specs
    def self.slug_for(id)
      Wow::Catalog.spec_slug(id)
    end
  end
end
