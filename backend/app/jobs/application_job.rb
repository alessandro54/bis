# :nocov:
class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock with exponential backoff
  # This prevents queue pollution and allows database to recover from contention
  retry_on ActiveRecord::Deadlocked, wait: :exponentially_longer, attempts: 5

  # Most jobs are safe to ignore if the underlying records are no longer available
  # This prevents jobs from failing permanently when records are deleted during processing
  discard_on ActiveJob::DeserializationError

  # Discard jobs with record not found errors (records may have been deleted)
  # This prevents unnecessary retries for non-existent records
  discard_on ActiveRecord::RecordNotFound

  # Retry network/API errors with exponential backoff
  # This handles transient API failures without overloading the API
  retry_on StandardError, wait: :exponentially_longer, attempts: 3 do |job, error|
    # Log the error for debugging and monitoring
    Rails.logger.error("[#{job.class.name}] Retry attempt #{job.executions} failed: #{error.message}")
  end
end
# :nocov:
