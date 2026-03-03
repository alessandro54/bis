class AddTopBuildRankToPvpMetaTalentPopularity < ActiveRecord::Migration[8.1]
  def change
    add_column :pvp_meta_talent_popularity, :top_build_rank, :integer, default: 0, null: false
  end
end
