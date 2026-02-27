# Lightweight aggregator that collects per-item results during batch processing.
# Fiber-safe: only Array#<< from fibers in same Async reactor, never shared across threads.
class BatchOutcome
  class TotalBatchFailureError < StandardError; end

  # Statuses that count as failures
  FAILURE_STATUSES = %i[failed api_error rate_limited service_failure unexpected_error].freeze

  attr_reader :successes, :failures

  def initialize
    @successes = []
    @failures = []
  end

  def record_success(id:, status:)
    @successes << { id: id, status: status }
  end

  def record_failure(id:, status:, error:)
    @failures << { id: id, status: status, error: error }
  end

  def total
    @successes.size + @failures.size
  end

  def total_failure?
    total > 0 && @successes.empty?
  end

  def counts_by_status
    all_entries = @successes + @failures
    all_entries.each_with_object(Hash.new(0)) { |entry, counts| counts[entry[:status]] += 1 }
  end

  def summary_message(job_label:)
    succeeded = @successes.size
    failed    = @failures.size
    breakdown = counts_by_status.map { |status, count| "#{status}: #{count}" }.join(", ")

    msg = "[#{job_label}] Batch complete: #{succeeded}/#{total} succeeded, #{failed} failed. Breakdown: {#{breakdown}}"

    if @failures.any?
      samples = @failures.first(5).map { |f| "#{f[:id]}: #{f[:error]}" }.join("; ")
      msg += ". Failures: [#{samples}]"
      msg += " (+#{failed - 5} more)" if failed > 5
    end

    msg
  end

  def raise_if_total_failure!(job_label:)
    return unless total_failure?

    status_counts = @failures.each_with_object(Hash.new(0)) { |f, counts| counts[f[:status]] += 1 }
    status_summary = status_counts.map { |status, count| "#{status}: #{count}" }.join(", ")

    samples = @failures.first(3).map { |f| "#{f[:id]}: #{f[:error]}" }.join("; ")

    raise TotalBatchFailureError,
      "[#{job_label}] All #{total} items failed. Statuses: {#{status_summary}}. Samples: #{samples}"
  end
end
