# spec/services/blizzard/client_spec.rb
require "rails_helper"

RSpec.describe Blizzard::Client do
  let(:auth_double) { instance_double("Blizzard::Auth", access_token: "fake-token") }

  describe "#initialize" do
    it "sets region, locale and auth for valid values" do
      client = described_class.new(region: "us", locale: "en_US", auth: auth_double)

      expect(client.region).to eq("us")
      expect(client.locale).to eq("en_US")
      expect(client.auth).to eq(auth_double)
    end

    it "raises an error for unsupported region" do
      expect {
        described_class.new(region: "cn", locale: "en_US", auth: auth_double)
      }.to raise_error(ArgumentError, "Unsupported Blizzard API region: cn")
    end

    it "raises an error for invalid locale for a given region" do
      expect {
        described_class.new(region: "us", locale: "es_ES", auth: auth_double)
      }.to raise_error(ArgumentError, "Invalid locale 'es_ES' for region 'us'")
    end
  end

  describe "#get" do
    let(:region) { "us" }
    let(:locale) { "en_US" }
    let(:client) { described_class.new(region: region, locale: locale, auth: auth_double) }
    let(:http_double) { instance_double("HTTPX::Session") }

    let(:path) { "/data/wow/pvp-season/37/pvp-leaderboard/3v3" }
    let(:namespace) { "dynamic-us" }
    let(:extra_params) { { "page" => 2 } }

    before do
      # Stub de HTTPX.with para que devuelva nuestro double
      allow(HTTPX).to receive(:with).and_return(http_double)
    end

    it "builds the correct URL, query params and headers, and parses a successful JSON response" do
      response_body = { "ok" => true, "data" => [ 1, 2, 3 ] }.to_json
      response_double = instance_double(
        "HTTPX::Response",
        status: 200,
        body: double("body", to_s: response_body)
      )

      expected_url = "https://us.api.blizzard.com#{path}"
      expected_query = {
        namespace: namespace,
        locale: locale
      }.merge(extra_params)

      expect(http_double).to receive(:get).with(
        expected_url,
        params: expected_query,
        headers: { Authorization: "Bearer fake-token" }
      ).and_return(response_double)

      result = client.get(path, namespace: namespace, params: extra_params)

      expect(result).to eq(JSON.parse(response_body))
    end

    it "raises Blizzard::Client::Error when status is not 200" do
      response_double = instance_double(
        "HTTPX::Response",
        status: 404,
        body: double("body", to_s: "Not Found")
      )

      allow(http_double).to receive(:get).and_return(response_double)

      expect {
        client.get(path, namespace: namespace)
      }.to raise_error(
             Blizzard::Client::Error,
             /Blizzard API error: HTTP 404, body=Not Found/
           )
    end

    it "raises Blizzard::Client::Error when response body is invalid JSON" do
      response_double = instance_double(
        "HTTPX::Response",
        status: 200,
        body: double("body", to_s: "this is not json")
      )

      allow(http_double).to receive(:get).and_return(response_double)

      expect {
        client.get(path, namespace: namespace)
      }.to raise_error(
             Blizzard::Client::Error,
             /Blizzard API error: invalid JSON:/
           )
    end
  end

  describe "namespace helpers" do
    let(:client) { described_class.new(region: "eu", locale: "en_GB", auth: auth_double) }

    it "returns correct profile namespace" do
      expect(client.profile_namespace).to eq("profile-eu")
    end

    it "returns correct dynamic namespace" do
      expect(client.dynamic_namespace).to eq("dynamic-eu")
    end

    it "returns correct static namespace" do
      expect(client.static_namespace).to eq("static-eu")
    end
  end
end
