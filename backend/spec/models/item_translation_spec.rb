# == Schema Information
#
# Table name: item_translations
#
#  id          :bigint           not null, primary key
#  description :string
#  locale      :string
#  name        :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  item_id     :bigint           not null
#
# Indexes
#
#  index_item_translations_on_item_id             (item_id)
#  index_item_translations_on_item_id_and_locale  (item_id,locale) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (item_id => items.id)
#
require 'rails_helper'

RSpec.describe ItemTranslation, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
