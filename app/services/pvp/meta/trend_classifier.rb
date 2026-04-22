module Pvp
  module Meta
    module TrendClassifier
      DELTA_THRESHOLD = 1.0

      def self.call(current_pct, prev_pct)
        return "new" if prev_pct.nil?

        delta = current_pct.to_f - prev_pct.to_f
        if delta > DELTA_THRESHOLD
          "up"
        elsif delta < -DELTA_THRESHOLD
          "down"
        else
          "stable"
        end
      end
    end
  end
end
