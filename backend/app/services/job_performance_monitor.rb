# Job performance monitoring and optimization service
class JobPerformanceMonitor
  # Sample rate for DB writes: 1 = 100%, 10 = 10%, 0 = disabled
  # Failures are always recorded regardless of sample rate
  SAMPLE_RATE = ENV.fetch("JOB_MONITOR_SAMPLE_RATE", 0).to_i

  class << self
    def track_job_performance(job_class, duration, success:, error: nil)
      return if SAMPLE_RATE.zero?

      metrics = {
        job_class: job_class.name,
        duration:  duration,
        success:   success,
        timestamp: Time.current,
        error:     error&.class&.name
      }

      # Always store failures; sample successes
      if !success || sampled?
        store_metrics(metrics)
      end

      # Alert on slow jobs (cheap check, no DB query)
      return unless duration > 60.seconds

      Rails.logger.warn("Slow job detected: #{metrics[:job_class]} took #{duration}s")
    end

    private def sampled?
      SAMPLE_RATE >= 1 && rand(SAMPLE_RATE) == 0
    end

    def get_performance_stats(job_class: nil, time_range: 1.hour)
      query = JobPerformanceMetric.where("created_at > ?", time_range.ago)
      query = query.where(job_class: job_class.name) if job_class

      rows = query.group(:job_class).pluck(
        :job_class,
        Arel.sql("COUNT(id)"),
        Arel.sql("AVG(duration)"),
        Arel.sql("MAX(duration)"),
        Arel.sql("MIN(duration)"),
        Arel.sql("SUM(CASE WHEN success THEN 1 ELSE 0 END)")
      )

      stats = rows.each_with_object({}) do |(job_class, count, avg, max, min, sum), hash|
        hash[job_class] = {
          count: count,
          avg:   avg,
          max:   max,
          min:   min,
          sum:   sum
        }
      end

      format_performance_stats(stats)
    end

    def optimize_queue_configuration
      recommendations = []

      # Analyze queue performance
      queue_stats = get_queue_performance

      queue_stats.each do |queue, stats|
        if stats[:avg_duration] > 30.seconds
          recommendations << "Consider increasing workers for #{queue} queue"
        end

        if stats[:failure_rate] > 0.1
          recommendations << "High failure rate in #{queue} queue - check for external API issues"
        end

        if stats[:throughput] < stats[:expected_throughput]
          recommendations << "Increase parallelism for #{queue} queue"
        end
      end

      recommendations
    end

    private

      def store_metrics(metrics)
        JobPerformanceMetric.create!(
          job_class:   metrics[:job_class],
          duration:    metrics[:duration],
          success:     metrics[:success],
          error_class: metrics[:error],
          created_at:  metrics[:timestamp]
        )
      rescue => e
        Rails.logger.error("Failed to store job metrics: #{e.message}")
      end

      def get_queue_performance
        recent_metrics = JobPerformanceMetric.where("created_at > ?", 1.hour.ago)
        queue_stats = initialize_queue_stats(recent_metrics)
        calculate_derived_metrics(queue_stats)
      end

      def initialize_queue_stats(recent_metrics)
        queue_stats = {}

        recent_metrics.each do |metric|
          queue = extract_queue_from_job_class(metric.job_class)
          queue_stats[queue] ||= create_default_stats
          update_stats_with_metric(queue_stats[queue], metric)
        end

        queue_stats
      end

      def create_default_stats
        {
          total_jobs:      0,
          successful_jobs: 0,
          total_duration:  0,
          max_duration:    0
        }
      end

      def update_stats_with_metric(stats, metric)
        stats[:total_jobs] += 1
        stats[:successful_jobs] += 1 if metric.success
        stats[:total_duration] += metric.duration
        stats[:max_duration] = [ stats[:max_duration], metric.duration ].max
      end

      def calculate_derived_metrics(queue_stats)
        queue_stats.each do |queue, stats|
          stats[:avg_duration] = stats[:total_duration] / stats[:total_jobs]
          stats[:failure_rate] = 1 - (stats[:successful_jobs].to_f / stats[:total_jobs])
          stats[:throughput] = stats[:total_jobs] / 3600.0 # jobs per second
        end

        queue_stats
      end

      def extract_queue_from_job_class(job_class)
        case job_class
        when /SyncCharacter/
          "character_sync"
        when /ProcessLeaderboard/
          "pvp_processing"
        else
          "background"
        end
      end

      def format_performance_stats(stats)
        stats.map do |job_class, data|
          {
            job_class:    job_class,
            total_jobs:   data[:count],
            avg_duration: data[:avg]&.round(2),
            max_duration: data[:max]&.round(2),
            min_duration: data[:min]&.round(2),
            success_rate: (data[:sum].to_f / data[:count] * 100).round(2)
          }
        end
      end
  end
end
