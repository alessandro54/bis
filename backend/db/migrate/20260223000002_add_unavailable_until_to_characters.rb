class AddUnavailableUntilToCharacters < ActiveRecord::Migration[8.1]
  def change
    add_column :characters, :unavailable_until, :datetime

    # Partial index — only indexes rows where the cooldown is active.
    # Most characters will have NULL here so this stays tiny.
    add_index :characters, :unavailable_until,
              where: "unavailable_until IS NOT NULL",
              name:  "index_characters_on_unavailable_until_active"
  end
end
