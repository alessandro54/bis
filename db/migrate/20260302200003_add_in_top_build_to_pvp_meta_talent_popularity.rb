class AddInTopBuildToPvpMetaTalentPopularity < ActiveRecord::Migration[8.1]
  def change
    add_column :pvp_meta_talent_popularity, :in_top_build, :boolean, default: false, null: false
  end
end
