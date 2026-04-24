class AddGinIndexToCharactersStatPcts < ActiveRecord::Migration[8.0]
  def change
    add_index :characters, :stat_pcts, using: :gin
  end
end
