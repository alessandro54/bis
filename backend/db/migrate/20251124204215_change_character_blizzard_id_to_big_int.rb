class ChangeCharacterBlizzardIdToBigInt < ActiveRecord::Migration[8.1]
  def up
    change_column :characters,
                  :blizzard_id,
                  :bigint,
                  using: "blizzard_id::bigint"
  end

  def down
    change_column :characters,
                  :blizzard_id,
                  :string
  end
end