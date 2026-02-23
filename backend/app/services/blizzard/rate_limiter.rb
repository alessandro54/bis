module Blizzard
  # Thread-safe token bucket rate limiter, one instance per API region.
  # US and EU have independent Blizzard rate-limit buckets, so each region
  # gets its own limiter to avoid cross-contamination.
  #
  # Usage (automatic via Client#get — no manual calls needed):
  #   RateLimiter.for_region("us").acquire   # blocks until a token is available
  #
  # Tune throughput via PVP_BLIZZARD_RPS (default 80, safely under the 100/s limit).
  # With 8 SQ threads × 11 concurrent chars × 2 parallel requests = 176 potential
  # req/s per region, so the limiter is essential to avoid 429s.
  class RateLimiter
    DEFAULT_RPS = ENV.fetch("PVP_BLIZZARD_RPS", 80).to_f

    # One limiter per region, created on first use.
    @limiters = {}
    @mutex    = Mutex.new

    def self.for_region(region)
      @mutex.synchronize { @limiters[region] ||= new }
    end

    def initialize(rps: DEFAULT_RPS)
      @rps         = rps.to_f
      @tokens      = @rps          # start full so first burst isn't throttled
      @last_refill = clock
      @mutex       = Mutex.new
    end

    # Block until a request token is available, then consume it.
    # Sleeps outside the mutex so other threads can refill in parallel.
    def acquire
      loop do
        wait = nil

        @mutex.synchronize do
          refill
          if @tokens >= 1.0
            @tokens -= 1.0
            return
          end
          # Time until the next token arrives
          wait = (1.0 - @tokens) / @rps
        end

        sleep(wait)
      end
    end

    private

      def refill
        now     = clock
        elapsed = now - @last_refill
        @tokens = [(@tokens + elapsed * @rps), @rps].min
        @last_refill = now
      end

      # Monotonic clock avoids drift issues during system clock adjustments.
      def clock
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
  end
end
