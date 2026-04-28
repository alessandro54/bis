require "rails_helper"

RSpec.describe Blizzard::Data::Talents::SyncTreeService, type: :service do
  let(:client_double) { instance_double(Blizzard::Client) }

  subject(:service) { described_class.new(region: "us", locale: "en_US") }

  before do
    allow(Blizzard::Client).to receive(:new).and_return(client_double)
    allow(SyncTalentMediaJob).to receive(:perform_later)
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

      new_talent = create(:talent, blizzard_id: 50_002)
      spec_assignments = { 1 => [ 50_002 ] }

      allow(TalentSpecAssignment).to receive(:insert_all).and_raise(ActiveRecord::StatementInvalid, "simulated")

      expect {
        service.send(:apply_spec_assignments, spec_assignments)
      }.to raise_error(ActiveRecord::StatementInvalid)

      expect(TalentSpecAssignment.where(spec_id: 1, talent_id: existing_talent.id).count).to eq(1)
    end
  end

  describe "#apply_talent_types (private)" do
    it "does not downgrade a talent already classified as hero" do
      talent = create(:talent, blizzard_id: 99_001, talent_type: "hero")
      talent_attrs = { 99_001 => { talent_type: "class", node_id: 1, display_row: 1, display_col: 1, max_rank: 1,
spell_id: nil } }

      service.send(:apply_talent_types, talent_attrs)

      expect(talent.reload.talent_type).to eq("hero")
    end

    it "corrects a class talent to spec" do
      talent = create(:talent, blizzard_id: 99_002, talent_type: "class")
      talent_attrs = { 99_002 => { talent_type: "spec", node_id: 1, display_row: 1, display_col: 1, max_rank: 1,
spell_id: nil } }

      service.send(:apply_talent_types, talent_attrs)

      expect(talent.reload.talent_type).to eq("spec")
    end
  end

  describe "talent_type priority in process_nodes (private)" do
    it "hero wins over class when same blizzard_id appears in both sections" do
      talent_attrs = {}
      edges        = Set.new
      ids          = Set.new
      name_map     = {}

      rank = { "tooltip" => { "talent" => { "id" => 500, "name" => "Halo" },
                              "spell_tooltip" => { "spell" => { "id" => 1 } } } }
      class_node = { "id" => 1, "display_row" => 1, "display_col" => 1, "ranks" => [ rank ] }
      hero_node  = { "id" => 2, "display_row" => 2, "display_col" => 2, "ranks" => [ rank ] }

      service.send(:process_nodes, [ class_node ], "class", talent_attrs, edges, ids, name_map)
      service.send(:process_nodes, [ hero_node ],  "hero",  talent_attrs, edges, ids, name_map)

      expect(talent_attrs[500][:talent_type]).to eq("hero")
    end

    it "hero is not overwritten when class is processed after hero" do
      talent_attrs = {}
      edges        = Set.new
      ids          = Set.new
      name_map     = {}

      rank = { "tooltip" => { "talent" => { "id" => 501, "name" => "Halo" },
                              "spell_tooltip" => { "spell" => { "id" => 2 } } } }
      hero_node  = { "id" => 2, "display_row" => 2, "display_col" => 2, "ranks" => [ rank ] }
      class_node = { "id" => 1, "display_row" => 1, "display_col" => 1, "ranks" => [ rank ] }

      service.send(:process_nodes, [ hero_node ],  "hero",  talent_attrs, edges, ids, name_map)
      service.send(:process_nodes, [ class_node ], "class", talent_attrs, edges, ids, name_map)

      expect(talent_attrs[501][:talent_type]).to eq("hero")
    end
  end

  describe "#call with a failing spec" do
    let(:empty_tree) { { "class_talent_nodes" => [], "spec_talent_nodes" => [], "hero_talent_trees" => [] } }

    before do
      allow(client_double).to receive(:static_namespace).and_return("static-us")
      allow(client_double).to receive(:locale).and_return("en_US")

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

      allow(client_double).to receive(:get)
        .with("/data/wow/talent-tree/786/playable-specialization/71", anything)
        .and_return(empty_tree)

      allow(client_double).to receive(:get)
        .with("/data/wow/talent-tree/787/playable-specialization/72", anything)
        .and_raise(Blizzard::Client::Error, "timeout")
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

    it "does not enqueue SyncTalentMediaJob on non-force sync" do
      expect(SyncTalentMediaJob).not_to receive(:perform_later)
      service.call
    end

    it "enqueues SyncTalentMediaJob when force: true" do
      force_service = described_class.new(region: "us", locale: "en_US", force: true)
      expect(SyncTalentMediaJob).to receive(:perform_later).with(region: "us", locale: "en_US")
      force_service.call
    end
  end
end
