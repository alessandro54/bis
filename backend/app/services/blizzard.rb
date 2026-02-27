# app/services/blizzard.rb
module Blizzard
  class << self
    # Always constructs a fresh Client so each call picks up the next auth
    # from AuthPool's round-robin. Caching the client would pin one credential
    # per region and defeat the round-robin distribution.
    def client(region: "us", locale: "en_US")
      Client.new(region:, locale:)
    end
  end
end
