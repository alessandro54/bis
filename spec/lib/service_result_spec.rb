# spec/lib/service_result_spec.rb
require "rails_helper"

RSpec.describe ServiceResult do
  describe ".success" do
    it "builds a successful result with payload" do
      result = described_class.success({ foo: "bar" }, message: "ok", context: { source: "test" })

      expect(result.ok?).to be(true)
      expect(result.success?).to be(true)
      expect(result.failure?).to be(false)

      expect(result.error).to be_nil
      expect(result.message).to eq("ok")
      expect(result.payload).to eq({ foo: "bar" })
      expect(result.context).to eq({ source: "test" })
    end

    it "defaults payload and context when not provided" do
      result = described_class.success

      expect(result.ok?).to be(true)
      expect(result.payload).to be_nil
      expect(result.context).to eq({})
    end
  end

  describe ".failure" do
    it "builds a failure result with error key" do
      result = described_class.failure(
        :invalid_input,
        message: "bad stuff",
        payload: { field: "name" },
        context: { source: "service_x" }
      )

      expect(result.ok?).to be(false)
      expect(result.failure?).to be(true)
      expect(result.success?).to be(false)

      expect(result.error).to eq(:invalid_input)
      expect(result.message).to eq("bad stuff")
      expect(result.payload).to eq({ field: "name" })
      expect(result.context).to eq({ source: "service_x" })
    end

    it "requires an error key" do
      expect do
        described_class.failure(nil)
      end.to raise_error(ArgumentError, "error can't be nil")
    end
  end

  describe "#ok?" do
    it "returns true for success and false for failure" do
      ok_result  = described_class.success
      bad_result = described_class.failure(:error)

      expect(ok_result.ok?).to be(true)
      expect(bad_result.ok?).to be(false)
    end
  end

  describe "#success?" do
    it "is an alias of #ok?" do
      result = described_class.success

      expect(result.success?).to eq(result.ok?)
    end
  end

  describe "#failure?" do
    it "is the negation of #ok?" do
      ok_result  = described_class.success
      bad_result = described_class.failure(:error)

      expect(ok_result.failure?).to be(false)
      expect(bad_result.failure?).to be(true)
    end
  end
end
