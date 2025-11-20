# spec/services/blizzard/auth_spec.rb
require "rails_helper"

RSpec.describe Blizzard::Auth do
  include ActiveSupport::Testing::TimeHelpers

  let(:client_id) { "test_client_id" }
  let(:client_secret) { "test_client_secret" }

  subject(:auth) do
    described_class.new(client_id:, client_secret:)
  end

  describe "#initialize" do
    context "when client_id or client_secret is missing" do
      it "raises an ArgumentError" do
        expect {
          described_class.new(client_id: nil, client_secret: nil)
        }.to raise_error(
          ArgumentError,
          "Blizzard client_id and client_secret must be provided"
        )

        expect {
          described_class.new(client_id: "", client_secret: client_secret)
        }.to raise_error(
          ArgumentError,
          "Blizzard client_id and client_secret must be provided"
        )

        expect {
          described_class.new(client_id: client_id, client_secret: nil)
        }.to raise_error(
          ArgumentError,
          "Blizzard client_id and client_secret must be provided"
        )
      end
    end
  end

  describe "#access_token" do
    let(:cache_key) { Blizzard::Auth::CACHE_KEY }

    context "when there is a valid cached token" do
      let(:cached_token) { "cached-token" }
      let(:future_time)  { 10.minutes.from_now }

      before do
        allow(Rails.cache).to receive(:read).with(cache_key).and_return(
          {
            token: cached_token,
            expires_at: future_time
          }
        )
      end

      it "returns the cached token and does not call HTTP" do
        expect(Net::HTTP).not_to receive(:start)

        token = auth.access_token

        expect(token).to eq(cached_token)
      end
    end

    context "when there is no cached token" do
      let(:new_token)      { "new-access-token" }
      let(:expires_in_sec) { 3600 }

      let(:http_response) do
        instance_double(
          Net::HTTPSuccess,
          is_a?: true,
          code: "200",
          message: "OK",
          body: {
            access_token: new_token,
            expires_in: expires_in_sec
          }.to_json
        )
      end

      before do
        allow(Rails.cache).to receive(:read).with(cache_key).and_return(nil)

        http_double = instance_double(Net::HTTP)

        allow(Net::HTTP).to receive(:start)
          .and_yield(http_double)

        allow(http_double).to receive(:request)
          .and_return(http_response)

        allow(Rails.cache).to receive(:write)
      end

      it "performs the OAuth request and caches the token" do
        freeze_time do
          token = auth.access_token

          expect(token).to eq(new_token)
          expect(Net::HTTP).to have_received(:start).once

          expected_expires_at =
            Time.current + expires_in_sec - Blizzard::Auth::EXPIRY_SKEW_SECONDS

          expect(Rails.cache).to have_received(:write).with(
            cache_key,
            hash_including(
              token: new_token,
              expires_at: expected_expires_at
            ),
            expires_in: expires_in_sec
          )
        end
      end
    end

    context "when cached token is expired" do
      let(:expired_token) { "expired-token" }
      let(:new_token)     { "fresh-token" }

      let(:http_response) do
        instance_double(
          Net::HTTPSuccess,
          is_a?: true,
          code: "200",
          message: "OK",
          body: {
            access_token: new_token,
            expires_in: 1800
          }.to_json
        )
      end

      before do
        allow(Rails.cache).to receive(:read).with(cache_key).and_return(
          {
            token: expired_token,
            expires_at: 5.minutes.ago
          }
        )

        http_double = instance_double(Net::HTTP)

        allow(Net::HTTP).to receive(:start)
          .and_yield(http_double)

        allow(http_double).to receive(:request)
          .and_return(http_response)

        allow(Rails.cache).to receive(:write)
      end

      it "ignores expired token and fetches a new one" do
        token = auth.access_token

        expect(token).to eq(new_token)
        expect(Net::HTTP).to have_received(:start).once
      end
    end

    context "when the HTTP response is not success" do
      let(:http_response) do
        instance_double(
          Net::HTTPUnauthorized,
          is_a?: false,
          code: "401",
          message: "Unauthorized",
          body: '{"error":"invalid_client"}'
        )
      end

      before do
        allow(Rails.cache).to receive(:read).with(cache_key).and_return(nil)

        http_double = instance_double(Net::HTTP)

        allow(Net::HTTP).to receive(:start)
          .and_yield(http_double)

        allow(http_double).to receive(:request)
          .and_return(http_response)
      end

      it "raises Blizzard::Auth::Error" do
        expect {
        auth.access_token
      }.to raise_error(Blizzard::Auth::Error, /Blizzard OAuth error/)
      end
    end

    context "when the response does not contain access_token" do
      let(:http_response) do
        instance_double(
          Net::HTTPSuccess,
          is_a?: true,
          code: "200",
          message: "OK",
          body: { "expires_in" => 3600 }.to_json
        )
      end

      before do
        allow(Rails.cache).to receive(:read).with(cache_key).and_return(nil)

        http_double = instance_double(Net::HTTP)

        allow(Net::HTTP).to receive(:start)
          .and_yield(http_double)

        allow(http_double).to receive(:request)
          .and_return(http_response)
      end

      it "raises Blizzard::Auth::Error" do
        expect {
          auth.access_token
        }.to raise_error(Blizzard::Auth::Error, /does not include access_token/)
      end
    end
  end
end
