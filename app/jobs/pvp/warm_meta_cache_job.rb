module Pvp
  class WarmMetaCacheJob < ApplicationJob
    queue_as :default

    SPEC_ENDPOINTS = %w[items enchants gems stats talents stat_priority top_players].freeze
    CONCURRENCY    = 8

    def perform
      season = PvpSeason.current
      return unless season

      combinations = spec_bracket_combinations(season)
      return if combinations.empty?

      Rails.logger.info("[WarmMetaCacheJob] Warming #{combinations.size} spec×bracket combinations")

      run_with_threads(combinations, concurrency: CONCURRENCY) do |(spec_id, bracket)|
        warm_spec_combination(spec_id, bracket)
      end

      Pvp::NotifyFrontendRevalidateService.call
      Rails.logger.info("[WarmMetaCacheJob] Cache warm complete")
      TelegramNotifier.send("🔥 Meta cache warmed — #{combinations.size} spec×bracket combinations ready")
    end

    private

      def spec_bracket_combinations(season)
        PvpMetaItemPopularity
          .where(pvp_season: season)
          .distinct
          .pluck(:spec_id, :bracket)
      end

      def warm_spec_combination(spec_id, bracket)
        base = internal_api_url
        SPEC_ENDPOINTS.each do |endpoint|
          HTTPX.get(
            "#{base}/api/v1/pvp/meta/#{endpoint}",
            params: { spec_id: spec_id, bracket: bracket }
          )
        end
      rescue => e
        Rails.logger.warn("[WarmMetaCacheJob] Failed spec_id=#{spec_id} bracket=#{bracket}: #{e.message}")
      end

      def internal_api_url
        @internal_api_url ||= ENV.fetch("INTERNAL_API_URL", "http://localhost:#{ENV.fetch('PORT', 3000)}")
      end
  end
end
