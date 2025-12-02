# lib/wow/classes.rb
module Wow
  module Classes
    def self.slug_for(id)
      Wow::Catalog.class_slug(id)
    end
  end
end
