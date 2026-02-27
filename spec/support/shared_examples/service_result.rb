RSpec.shared_examples "service result interface" do
  it "returns a ServiceResult" do
    expect(result).to be_a(ServiceResult)
  end

  context "when successful" do
    it "returns success result" do
      if result.success?
        expect(result).to be_success
        expect(result.ok?).to be(true)
        expect(result.error).to be_nil
      end
    end
  end

  context "when failed" do
    it "returns failure result" do
      if result.failure?
        expect(result).to be_failure
        expect(result.ok?).to be(false)
        expect(result.error).to be_present
      end
    end
  end
end
