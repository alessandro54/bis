class CreateTranslations < ActiveRecord::Migration[8.1]
  def change
    create_table :translations do |t|
      t.string :locale, null: false
      t.string :key, null: false
      t.text :value, null: false

      t.references :translatable, polymorphic: true, null: false

      t.jsonb :meta, null: false, default: {}

      t.timestamps
    end

    add_index :translations,
              [:translatable_type, :translatable_id, :locale, :key],
              unique: true,
              name: :index_translations_on_translatable_and_locale_and_key

    add_index :translations, :key
    add_index :translations, :locale
  end
end
