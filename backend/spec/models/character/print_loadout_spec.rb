require "rails_helper"

RSpec.describe Character, type: :model do
  let(:character) { create(:character, name: "Valdris", realm: "tichondrius", region: "us") }

  # ── helpers ──────────────────────────────────────────────────────────────
  def make_item(name, quality: "epic")
    item = create(:item, quality: quality)
    item.set_translation("name", "en_US", name, meta: { source: "test" })
    item
  end

  def equip(slot, item, item_level: 500, enchantment: nil, enchantment_source_item: nil, sockets: [])
    create(:character_item,
      character:               character,
      item:                    item,
      slot:                    slot,
      item_level:              item_level,
      enchantment:             enchantment,
      enchantment_source_item: enchantment_source_item,
      sockets:                 sockets)
  end

  describe "#print_loadout" do
    let(:helm)      { make_item("Voidbound Helm") }
    let(:chest)     { make_item("Breastplate of the Warlord") }
    let(:sword)     { make_item("Greatsword of Rampant Fury") }
    let(:gem)       { make_item("Culminating Blasphemite", quality: "rare") }
    let(:scroll)    { make_item("Enchant Weapon - Authority of Radiant Power", quality: "uncommon") }
    let(:enchantment) do
      enc = create(:enchantment)
      enc.set_translation("name", "en_US", "Authority of Radiant Power", meta: { source: "test" })
      enc
    end

    before do
      equip("head",      helm,  item_level: 639,
                                sockets:    [ { "type" => "PRISMATIC", "item_id" => gem.id } ])
      equip("chest",     chest, item_level: 639)
      equip("main_hand", sword, item_level:              639,
                                enchantment:             enchantment,
                                enchantment_source_item: scroll)
    end

    it "includes the character display name and region" do
      expect { character.print_loadout }.to output(/Valdris-Tichondrius.*US/i).to_stdout
    end

    it "shows slot count and average item level" do
      expect { character.print_loadout }.to output(/3 slots.*avg ilvl.*639/i).to_stdout
    end

    it "shows each slot with its item level and translated name" do
      expect { character.print_loadout }.to output(/HEAD.*\[639\].*Voidbound Helm/i).to_stdout
      expect { character.print_loadout }.to output(/CHEST.*\[639\].*Breastplate of the Warlord/i).to_stdout
    end

    it "shows the enchantment name with ✦ marker" do
      expect { character.print_loadout }.to output(/✦ Authority of Radiant Power/).to_stdout
    end

    it "shows the enchantment source item name" do
      expect { character.print_loadout }.to output(/Enchant Weapon - Authority of Radiant Power/).to_stdout
    end

    it "shows socket gems with ◈ marker and gem name" do
      expect { character.print_loadout }.to output(/◈ PRISMATIC.*Culminating Blasphemite/i).to_stdout
    end

    it "does not show enchant/socket lines for plain slots" do
      output = capture_output { character.print_loadout }
      chest_block = output.lines.select { |l| l.match?(/CHEST/i) || l.match?(/Breastplate/) }
      expect(chest_block.none? { |l| l.include?("✦") || l.include?("◈") }).to be true
    end

    it "returns nil" do
      result = nil
      capture_output { result = character.print_loadout }
      expect(result).to be_nil
    end
  end

  describe "#print_talents" do
    let(:warrior_slam)   { create(:talent, talent_type: "class", spell_id: 1_464).tap  { |t|
 t.set_translation("name", "en_US", "Slam",          meta: { source: "test" }) } }
    let(:mortal_strike)  { create(:talent, talent_type: "spec",  spell_id: 12_294).tap { |t|
 t.set_translation("name", "en_US", "Mortal Strike", meta: { source: "test" }) } }
    let(:colossal_might) { create(:talent, talent_type: "hero",  spell_id: 440_989).tap { |t|
 t.set_translation("name", "en_US", "Colossal Might", meta: { source: "test" }) } }
    let(:sharpen_blade)  { create(:talent, talent_type: "pvp",   spell_id: 202_751).tap { |t|
 t.set_translation("name", "en_US", "Sharpen Blade", meta: { source: "test" }) } }

    before do
      create(:character_talent, character: character, talent: warrior_slam,   talent_type: "class", rank: 1)
      create(:character_talent, character: character, talent: mortal_strike,  talent_type: "spec",  rank: 1)
      create(:character_talent, character: character, talent: colossal_might, talent_type: "hero",  rank: 1)
      create(:character_talent, character: character, talent: sharpen_blade,  talent_type: "pvp",   rank: 1,
slot_number: 2)
    end

    it "includes the character display name and region" do
      expect { character.print_talents }.to output(/Valdris-Tichondrius.*US/i).to_stdout
    end

    it "prints a section header for each talent type present" do
      output = capture_output { character.print_talents }
      expect(output).to match(/CLASS/)
      expect(output).to match(/SPEC/)
      expect(output).to match(/HERO/)
      expect(output).to match(/PVP/)
    end

    it "lists each talent name under its type" do
      output = capture_output { character.print_talents }
      expect(output).to match(/Slam/)
      expect(output).to match(/Mortal Strike/)
      expect(output).to match(/Colossal Might/)
      expect(output).to match(/Sharpen Blade/)
    end

    it "shows slot_number for pvp talents" do
      expect { character.print_talents }.to output(/Sharpen Blade.*\[slot 2\]/).to_stdout
    end

    it "shows rank when greater than 1" do
      slam_rank2 = create(:talent, talent_type: "class", spell_id: 99_999)
      slam_rank2.set_translation("name", "en_US", "Overpower", meta: { source: "test" })
      create(:character_talent, character: character, talent: slam_rank2, talent_type: "class", rank: 2)

      expect { character.print_talents }.to output(/Overpower.*rank 2/).to_stdout
    end

    it "omits sections for types with no talents" do
      character_no_pvp = create(:character)
      create(:character_talent, character: character_no_pvp, talent: warrior_slam, talent_type: "class", rank: 1)

      output = capture_output { character_no_pvp.print_talents }
      expect(output).not_to match(/\bPVP\b/)
    end

    it "returns nil" do
      result = nil
      capture_output { result = character.print_talents }
      expect(result).to be_nil
    end
  end

  # ── helper ───────────────────────────────────────────────────────────────
  def capture_output(&block)
    output = StringIO.new
    $stdout = output
    block.call
    output.string
  ensure
    $stdout = STDOUT
  end
end
