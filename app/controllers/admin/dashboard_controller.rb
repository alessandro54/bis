module Admin
  class DashboardController < Admin::BaseController
    helper_method :pct_class, :bar_class, :cycle_tag_class

    def show
      @season = PvpSeason.current
      return unless @season

      result        = Admin::DashboardHealthService.call(season: @season)
      @last_cycle   = result.context[:last_cycle]
      @brackets     = result.context[:brackets]
      @characters   = result.context[:characters]
      @freshness    = result.context[:freshness]
      @translations = result.context[:translations]
    end

    private

      def pct_class(value, good: true)
        threshold = good ? value : 100.0 - value
        if threshold >= 95 then "pct-green"
        elsif threshold >= 80 then "pct-yellow"
        else "pct-red"
        end
      end

      def bar_class(value, good: true)
        threshold = good ? value : 100.0 - value
        if threshold >= 95 then "bar-green"
        elsif threshold >= 80 then "bar-yellow"
        else "bar-red"
        end
      end

      def cycle_tag_class(status)
        case status
        when "completed" then "tag-green"
        when "failed"    then "tag-red"
        else "tag-blue"
        end
      end
  end
end
