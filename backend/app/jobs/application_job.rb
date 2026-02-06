require "async"
require "async/semaphore"
require "async/barrier"

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

  # Enable query cache for all jobs - caches repeated SELECT queries within a job
  around_perform :with_query_cache

  private

    # Cap fiber concurrency to available DB pool connections.
    # Leaves 1 connection free for the main fiber.
    def safe_concurrency(desired, work_size)
      available = ActiveRecord::Base.connection_pool.size - 1
      [ desired, work_size, [ available, 1 ].max ].min
    end

    # Run block for each item using Async fibers with bounded concurrency.
    # Returns collected non-nil results from each block invocation.
    def run_concurrently(items, concurrency:)
      return [] if items.empty?

      results = []

      Async do
        semaphore = Async::Semaphore.new(concurrency)
        barrier = Async::Barrier.new(parent: semaphore)

        items.each do |item|
          barrier.async do
            result = yield(item)
            results << result unless result.nil?
          end
        end

        barrier.wait
      ensure
        barrier.stop
      end

      results
    end

    def with_query_cache(&block)
      ActiveRecord::Base.cache(&block)
    end

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
