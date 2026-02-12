class CreatePvpMetaTalentPicks < ActiveRecord::Migration[8.0]
  def change
    create_table :pvp_meta_talent_picks do |t|
      t.references :pvp_season, null: false, foreign_key: true
      t.string     :bracket,      null: false
      t.integer    :spec_id,      null: false
      t.references :talent,       null: false, foreign_key: true
      t.string     :talent_type,  null: false
      t.integer    :usage_count,  null: false, default: 0
      t.decimal    :pick_rate,    precision: 5, scale: 4
      t.decimal    :avg_rating,   precision: 7, scale: 2
      t.datetime   :snapshot_at,  null: false
      t.timestamps
    end
    add_index :pvp_meta_talent_picks,
      [:pvp_season_id, :bracket, :spec_id, :talent_type],
      name: "idx_talent_picks_lookup"
  end
end
