require "rails_helper"

RSpec.describe Blizzard::RateLimiter do
  after { described_class.reset! }

  describe ".for_credential" do
    it "returns the same instance for the same client_id" do
      a = described_class.for_credential("cred-1")
      b = described_class.for_credential("cred-1")
      expect(a).to be(b)
    end

    it "returns different instances for different client_ids" do
      a = described_class.for_credential("cred-1")
      b = described_class.for_credential("cred-2")
      expect(a).not_to be(b)
    end
  end

  describe "#acquire" do
    context "when both buckets are full (fresh limiter)" do
      subject(:limiter) { described_class.new(rps: 10.0, hourly_quota: 100.0) }

      it "returns immediately for each available token" do
        10.times do
          expect { Timeout.timeout(0.1) { limiter.acquire } }.not_to raise_error
        end
      end
    end

    context "when the per-second bucket is exhausted" do
      # Large hourly quota so only the per-second bucket is the bottleneck.
      subject(:limiter) { described_class.new(rps: 2.0, hourly_quota: 1_000_000.0) }

      it "blocks until the per-second bucket refills" do
        2.times { limiter.acquire }   # drain per-second bucket

        # Must sleep — verify it doesn't return within a tiny window.
        expect {
          Timeout.timeout(0.05) { limiter.acquire }
        }.to raise_error(Timeout::Error)
      end
    end

    context "when the hourly bucket is exhausted" do
      # Large per-second capacity so only the hourly bucket is the bottleneck.
      subject(:limiter) { described_class.new(rps: 1_000_000.0, hourly_quota: 2.0) }

      it "blocks until the hourly bucket refills" do
        2.times { limiter.acquire }   # drain the hourly quota

        # hourly_rps = 2/3600 ≈ 0.00056 tokens/s → refill takes ~1800s.
        # Verify it doesn't return within a short window, proving it's throttling.
        expect {
          Timeout.timeout(0.05) { limiter.acquire }
        }.to raise_error(Timeout::Error)
      end
    end
  end

  describe "#penalize!" do
    subject(:limiter) { described_class.new(rps: 1_000_000.0, hourly_quota: 1_000_000.0) }

    it "forces the next acquire to block by draining both buckets" do
      limiter.penalize!(drain_seconds: 5.0)

      expect {
        Timeout.timeout(0.05) { limiter.acquire }
      }.to raise_error(Timeout::Error)
    end
  end
end
