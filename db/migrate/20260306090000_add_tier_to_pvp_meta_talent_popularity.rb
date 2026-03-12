class AddTierToPvpMetaTalentPopularity < ActiveRecord::Migration[8.1]
  def change
    add_column :pvp_meta_talent_popularity, :tier, :string, default: "common", null: false
  end
end
