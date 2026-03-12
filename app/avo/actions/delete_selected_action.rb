class Avo::Actions::DeleteSelectedAction < Avo::BaseAction
  self.name = "Delete Selected"
  self.visible = -> { view.index? }
  self.confirm_button_label = "Delete"

  def handle(records:, **)
    count = records.count
    records.each_slice(1000) { |batch| batch.first.class.where(id: batch.map(&:id)).delete_all }
    inform("Deleted #{count} record#{"s" if count != 1}.")
  end
end
