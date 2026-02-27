# app/lib/wow/roles.rb
module Wow
  module Roles
    def self.role_for(class_id:, spec_id:)
      Wow::Catalog.role_for_spec(spec_id)
    end
  end
end
