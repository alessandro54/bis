require "rails_helper"

RSpec.describe Pvp::Meta::TrendClassifier do
  describe ".call" do
    it "returns 'new' when prev_pct is nil" do
      expect(described_class.call(50.0, nil)).to eq("new")
    end

    it "returns 'up' when delta > 1.0" do
      expect(described_class.call(55.0, 40.0)).to eq("up")
    end

    it "returns 'down' when delta < -1.0" do
      expect(described_class.call(30.0, 45.0)).to eq("down")
    end

    it "returns 'stable' when |delta| <= 1.0" do
      expect(described_class.call(20.5, 20.0)).to eq("stable")
    end

    it "returns 'stable' at the exact 1.0 boundary" do
      expect(described_class.call(21.0, 20.0)).to eq("stable")
    end

    it "returns 'stable' at the exact -1.0 boundary" do
      expect(described_class.call(19.0, 20.0)).to eq("stable")
    end
  end
end
