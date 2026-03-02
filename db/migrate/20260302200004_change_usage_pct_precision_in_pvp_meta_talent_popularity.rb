class ChangeUsagePctPrecisionInPvpMetaTalentPopularity < ActiveRecord::Migration[8.1]
  def change
    change_column :pvp_meta_talent_popularity, :usage_pct, :decimal, precision: 8, scale: 4
  end
end
