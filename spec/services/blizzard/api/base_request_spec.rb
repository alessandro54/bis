# spec/services/blizzard/api/base_request_spec.rb
require "rails_helper"

RSpec.describe Blizzard::Api::BaseRequest do
  describe "#initialize" do
    let(:region) { "us" }
    let(:locale) { "en_US" }
    let(:client_double) { instance_double("Blizzard::Client") }

    it "uses Blizzard.client with the given region and locale" do
      expect(Blizzard).to receive(:client)
                            .with(region: region, locale: locale)
                            .and_return(client_double)

      request = described_class.new(region: region, locale: locale)

      expect(request.client).to eq(client_double)
    end

    it "uses Blizzard.client with default locale when none is provided" do
      default_locale = "en_US"
      client_for_default_locale = instance_double("Blizzard::Client")

      expect(Blizzard).to receive(:client)
                            .with(region: region, locale: default_locale)
                            .and_return(client_for_default_locale)

      request = described_class.new(region: region)

      expect(request.client).to eq(client_for_default_locale)
    end
  end

  describe "#client" do
    it "returns the same client instance that Blizzard.client returns" do
      region = "us"
      locale = "en_US"
      client_double = instance_double("Blizzard::Client")

      allow(Blizzard).to receive(:client)
                           .with(region: region, locale: locale)
                           .and_return(client_double)

      request = described_class.new(region: region, locale: locale)

      expect(request.client).to equal(client_double)
    end
  end
end
