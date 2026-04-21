require "rails_helper"

RSpec.describe Blizzard::Data::Talents::SyncTreeService, type: :service do
  let(:client_double) { instance_double(Blizzard::Client) }

  subject(:service) { described_class.new(region: "us", locale: "en_US") }

  before do
    allow(Blizzard::Client).to receive(:new).and_return(client_double)
  end

  describe "#apply_prerequisites (private)" do
    let(:edges) { Set.new([ [ 101, 100 ], [ 102, 101 ] ]) }

    before do
      TalentPrerequisite.create!(node_id: 999, prerequisite_node_id: 998)
    end

    it "rolls back delete when insert_all! raises" do
      allow(TalentPrerequisite).to receive(:insert_all!).and_raise(ActiveRecord::StatementInvalid, "simulated")

      expect {
        service.send(:apply_prerequisites, edges)
      }.to raise_error(ActiveRecord::StatementInvalid)

      expect(TalentPrerequisite.where(node_id: 999).count).to eq(1)
    end
  end

  describe "#apply_spec_assignments (private)" do
    it "rolls back delete when insert_all raises (per-spec transaction)" do
      existing_talent = create(:talent, blizzard_id: 50_001)
      TalentSpecAssignment.create!(talent: existing_talent, spec_id: 1, default_points: 0)

      # New assignment set references a different talent — delete_all will remove existing
      new_talent = create(:talent, blizzard_id: 50_002)
      spec_assignments = { 1 => [ 50_002 ] }

      allow(TalentSpecAssignment).to receive(:insert_all).and_raise(ActiveRecord::StatementInvalid, "simulated")

      expect {
        service.send(:apply_spec_assignments, spec_assignments)
      }.to raise_error(ActiveRecord::StatementInvalid)

      expect(TalentSpecAssignment.where(spec_id: 1, talent_id: existing_talent.id).count).to eq(1)
    end
  end

  describe "#call with a failing spec" do
    let(:empty_tree) { { "class_talent_nodes" => [], "spec_talent_nodes" => [], "hero_talent_trees" => [] } }

    before do
      allow(client_double).to receive(:static_namespace).and_return("static-us")

      # Index returns two spec entries
      allow(client_double).to receive(:get)
        .with("/data/wow/talent-tree/index", anything)
        .and_return({
          "spec_talent_trees" => [
            { "key" => { "href" => "https://us.api.blizzard.com/data/wow/talent-tree/786/" \
                                    "playable-specialization/71?namespace=static-us" } },
            { "key" => { "href" => "https://us.api.blizzard.com/data/wow/talent-tree/787/" \
                                    "playable-specialization/72?namespace=static-us" } }
          ]
        })

      # Spec 71 (tree 786) succeeds
      allow(client_double).to receive(:get)
        .with("/data/wow/talent-tree/786/playable-specialization/71", anything)
        .and_return(empty_tree)

      # Spec 72 (tree 787) fails
      allow(client_double).to receive(:get)
        .with("/data/wow/talent-tree/787/playable-specialization/72", anything)
        .and_raise(Blizzard::Client::Error, "timeout")

      # Silence media sync
      allow(service).to receive(:fetch_missing_media)
    end

    it "does not call apply_prerequisites when any spec fails" do
      expect(service).not_to receive(:apply_prerequisites)
      service.call
    end

    it "preserves existing spec assignments for the failed spec" do
      talent = create(:talent, blizzard_id: 10_001)
      TalentSpecAssignment.create!(talent: talent, spec_id: 72, default_points: 0)

      service.call

      expect(TalentSpecAssignment.where(spec_id: 72).count).to eq(1)
    end
  end
end
