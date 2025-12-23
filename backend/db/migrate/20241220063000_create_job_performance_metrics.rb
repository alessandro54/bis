class CreateJobPerformanceMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :job_performance_metrics do |t|
      t.string :job_class, null: false, index: true
      t.float :duration, null: false
      t.boolean :success, null: false, default: false
      t.string :error_class
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false

      t.index [:job_class, :created_at]
      t.index [:created_at]
      t.index [:success]
    end
  end
end
