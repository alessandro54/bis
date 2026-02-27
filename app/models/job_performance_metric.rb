# Model for storing job performance metrics
# == Schema Information
#
# Table name: job_performance_metrics
# Database name: primary
#
#  id          :bigint           not null, primary key
#  duration    :float            not null
#  error_class :string
#  job_class   :string           not null
#  success     :boolean          default(FALSE), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_job_performance_metrics_on_created_at                (created_at)
#  index_job_performance_metrics_on_job_class                 (job_class)
#  index_job_performance_metrics_on_job_class_and_created_at  (job_class,created_at)
#  index_job_performance_metrics_on_success                   (success)
#
class JobPerformanceMetric < ApplicationRecord
  validates :job_class, presence: true
  validates :duration, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :success, inclusion: { in: [ true, false ] }

  # Scopes for querying performance data
  scope :successful, -> { where(success: true) }
  scope :failed, -> { where(success: false) }
  scope :recent, ->(hours = 24) { where("created_at > ?", hours.hours.ago) }
  scope :for_job_class, ->(job_class) { where(job_class: job_class) }

  # Class methods for performance analysis
  def self.performance_summary(job_class: nil, time_range: 24.hours)
    query = recent(time_range)
    query = query.for_job_class(job_class) if job_class

    total = query.count
    successful = query.successful.count
    failed = query.failed.count

    {
      total_jobs:      total,
      successful_jobs: successful,
      failed_jobs:     failed,
      success_rate:    total > 0 ? (successful.to_f / total * 100).round(2) : 0,
      avg_duration:    query.average(:duration)&.round(2) || 0,
      max_duration:    query.maximum(:duration) || 0,
      min_duration:    query.minimum(:duration) || 0
    }
  end

  def self.slow_jobs(threshold_seconds = 30, time_range = 1.hour)
    recent(time_range)
      .where("duration > ?", threshold_seconds)
      .order(duration: :desc)
  end

  def self.error_distribution(time_range = 24.hours)
    recent(time_range)
      .failed
      .group(:error_class)
      .count
  end
end
