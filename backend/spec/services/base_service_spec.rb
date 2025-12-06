# spec/services/base_service_spec.rb
require "rails_helper"

RSpec.describe BaseService do
  class DummyBaseService < BaseService
    def initialize(should_fail: false)
      @should_fail = should_fail
    end

    def call
      if @should_fail
        failure(:something_wrong, message: "nope", payload: { foo: "bar" })
      else
        success({ foo: "bar" }, message: "ok", context: { source: "dummy" })
      end
    end
  end

  describe ".call" do
    it "instantiates and calls #call, returning a ServiceResult" do
      result = DummyBaseService.call

      expect(result).to be_a(ServiceResult)
      expect(result.ok?).to be(true)
      expect(result.payload).to eq({ foo: "bar" })
      expect(result.message).to eq("ok")
      expect(result.context).to eq({ source: "dummy" })
    end
  end

  describe "#success" do
    it "builds a success ServiceResult" do
      service = DummyBaseService.new
      result  = service.send(:success, { foo: 1 }, message: "ok", context: { a: 1 })

      expect(result).to be_a(ServiceResult)
      expect(result.ok?).to be(true)
      expect(result.error).to be_nil
      expect(result.payload).to eq({ foo: 1 })
      expect(result.message).to eq("ok")
      expect(result.context).to eq({ a: 1 })
    end
  end

  describe "#failure" do
    it "builds a failure ServiceResult" do
      service = DummyBaseService.new
      result  = service.send(
        :failure,
        :invalid_state,
        message: "bad",
        payload: { foo: 2 },
        context: { a: 2 }
      )

      expect(result).to be_a(ServiceResult)
      expect(result.ok?).to be(false)
      expect(result.error).to eq(:invalid_state)
      expect(result.message).to eq("bad")
      expect(result.payload).to eq({ foo: 2 })
      expect(result.context).to eq({ a: 2 })
    end
  end
end
