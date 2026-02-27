require "rails_helper"

RSpec.describe ApplicationService do
  class DummyAppService < ApplicationService
    def initialize(value:)
      @value = value
    end

    def call
      return failure(:too_small, message: "value too small") if @value < 10

      success({ doubled: @value * 2 }, message: "ok-app")
    end
  end

  it "inherits from BaseService" do
    expect(described_class < BaseService).to be(true)
  end

  describe ".call" do
    it "returns success result when business logic passes" do
      result = DummyAppService.call(value: 20)

      expect(result).to be_a(ServiceResult)
      expect(result.ok?).to be(true)
      expect(result.payload).to eq({ doubled: 40 })
      expect(result.message).to eq("ok-app")
    end

    it "returns failure result when business logic fails" do
      result = DummyAppService.call(value: 5)

      expect(result.ok?).to be(false)
      expect(result.error).to eq(:too_small)
      expect(result.message).to eq("value too small")
    end
  end
end
