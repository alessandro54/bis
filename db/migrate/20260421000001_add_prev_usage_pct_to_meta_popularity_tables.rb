class AddPrevUsagePctToMetaPopularityTables < ActiveRecord::Migration[8.0]
  def change
    add_column :pvp_meta_item_popularity,    :prev_usage_pct, :decimal, precision: 5, scale: 2
    add_column :pvp_meta_enchant_popularity, :prev_usage_pct, :decimal, precision: 5, scale: 2
    add_column :pvp_meta_gem_popularity,     :prev_usage_pct, :decimal, precision: 5, scale: 2
  end
end
