class CreateItemTranslations < ActiveRecord::Migration[8.1]
  def change
    create_table :item_translations do |t|
      t.references :item, null: false, foreign_key: true
      t.string :locale
      t.string :name
      t.string :description

      t.timestamps
    end

    add_index :item_translations, [:item_id, :locale], unique: true
  end
end
