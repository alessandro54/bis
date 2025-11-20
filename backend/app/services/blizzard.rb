# app/services/blizzard.rb
module Blizzard
  class << self
    def client(region: "us", locale: "en_US")
      @clients ||= {}
      key = [ region, locale ]
      @clients[key] ||= Client.new(region:, locale:)
    end

    def reset_clients!
      @clients = {}
    end
  end
end
