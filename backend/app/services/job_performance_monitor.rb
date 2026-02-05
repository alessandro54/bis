# Job performance monitoring and optimization service
class JobPerformanceMonitor
  class << self
    def track_job_performance(job_class, duration, success:, error: nil)
      metrics = {
        job_class: job_class.name,
        duration:  duration,
        success:   success,
        timestamp: Time.current,
        error:     error&.class&.name
      }

      # Store metrics for analysis
      store_metrics(metrics)

      # Alert on performance issues
      alert_on_performance_issues(metrics)

      # Auto-optimize if needed
      suggest_optimizations(metrics)
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

      def alert_on_performance_issues(metrics)
        # Alert on slow jobs
        if metrics[:duration] > 60.seconds
          Rails.logger.warn("Slow job detected: #{metrics[:job_class]} took #{metrics[:duration]}s")
        end

        # Alert on high failure rates
        recent_failures = JobPerformanceMetric.where(
          job_class:  metrics[:job_class],
          success:    false,
          created_at: 5.minutes.ago..Time.current
        ).count

        return unless recent_failures > 5

        Rails.logger.error("High failure rate for #{metrics[:job_class]}: #{recent_failures} failures in 5 minutes")
      end

      def suggest_optimizations(metrics)
        # Suggest optimizations based on patterns
        if metrics[:job_class].include?("Batch") && metrics[:duration] > 30.seconds
          Rails.logger.info("Consider reducing batch size for #{metrics[:job_class]}")
        end

        return unless metrics[:error] == "Blizzard::Client::Error"

        Rails.logger.info("Consider implementing circuit breaker for #{metrics[:job_class]}")
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
