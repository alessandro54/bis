RSpec.shared_examples "has timestamps" do
  describe "timestamps" do
    let(:resource) { create(described_class.name.underscore.to_sym) }

    it "sets created_at automatically" do
      expect(resource.created_at).to be_within(5.seconds).of(Time.current)
    end

    it "sets updated_at automatically" do
      expect(resource.updated_at).to be_within(5.seconds).of(Time.current)
    end

    it "updates updated_at on save" do
      original_updated_at = resource.updated_at
      sleep(0.1)
      resource.update!(updated_at: Time.current)
      resource.reload

      expect(resource.updated_at).to be > original_updated_at
    end
  end
end
