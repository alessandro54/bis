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

    # Cap fiber concurrency so the pool is shared safely across all SolidQueue
    # threads in this process.
    #
    # Every thread can run one job at a time; each job's async fibers check out
    # one connection each via with_connection.  The pool must cover all threads:
    #
    #   safe fibers per job = floor(DB_POOL / threads) - 1
    #
    # Pass threads: matching the worker's SOLID_QUEUE_THREADS / PVP_SYNC_THREADS
    # so the math is accurate.  Defaults to 1 (safe for one-off callers).
    def safe_concurrency(desired, work_size, threads: 1)
      pool_size  = ActiveRecord::Base.connection_pool.size
      per_thread = [ (pool_size / threads) - 1, 1 ].max
      [ desired, work_size, per_thread ].min
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

    # Thread-based bounded concurrency for I/O-heavy work where the HTTP
    # client does not yield to the Async fiber scheduler (e.g. HTTPX runs its
    # own blocking event loop). Threads release Ruby's GIL during network I/O,
    # so N threads truly run N requests in parallel.
    #
    # Each thread pops items off a shared queue until empty, then exits.
    # Returns collected non-nil results.
    def run_with_threads(items, concurrency:)
      return [] if items.empty?

      results = []
      mutex   = Mutex.new
      work    = items.dup

      [concurrency, items.size].min.times.map do
        Thread.new do
          loop do
            item = mutex.synchronize { work.shift }
            break unless item

            result = yield(item)
            mutex.synchronize { results << result } unless result.nil?
          end
        end
      end.each(&:join)

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
