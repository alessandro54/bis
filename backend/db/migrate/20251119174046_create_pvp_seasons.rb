class CreatePvpSeasons < ActiveRecord::Migration[8.1]
  def change
    create_table :pvp_seasons do |t|
      t.string :display_name
      t.string :blizzard_id
      t.boolean :is_current, default: false

      t.datetime :start_time
      t.datetime :end_time

      t.timestamps
    end

    add_index :pvp_seasons, :is_current
    add_index :pvp_seasons, :updated_at
  end
end
