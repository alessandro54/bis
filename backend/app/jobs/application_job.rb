# :nocov:
class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock with exponential backoff
  # This prevents queue pollution and allows database to recover from contention
  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 5

  # Most jobs are safe to ignore if the underlying records are no longer available
  # This prevents jobs from failing permanently when records are deleted during processing
  discard_on ActiveJob::DeserializationError

  # Discard jobs with record not found errors (records may have been deleted)
  # This prevents unnecessary retries for non-existent records
  discard_on ActiveRecord::RecordNotFound

  # Note: Network/API errors should be handled in individual jobs with specific error classes
  # Avoid retry_on StandardError as it's too broad and may retry programming errors

  # Add performance monitoring to all jobs
  around_perform :monitor_performance

  private

    def monitor_performance(&block)
      start_time = Time.current
      result = block.call
      duration = Time.current - start_time

      # Track performance metrics
      JobPerformanceMonitor.track_job_performance(
        self.class,
        duration,
        success: true
      )

      result
    rescue => error
      duration = Time.current - start_time

      # Track failure metrics
      JobPerformanceMonitor.track_job_performance(
        self.class,
        duration,
        success: false,
        error:   error
      )

      raise error
    end
end
# :nocov:
