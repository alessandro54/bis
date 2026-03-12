class AddStatPctsToCharacters < ActiveRecord::Migration[8.1]
  def change
    add_column :characters, :stat_pcts, :jsonb, default: {}
  end
end
