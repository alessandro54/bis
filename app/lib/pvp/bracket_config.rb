module Pvp
  module BracketConfig
    # top_n is the sole limiter — no rating_min. This naturally adapts to season
    # maturity: early season syncs fewer players (all available top), late season
    # caps at the configured maximum. See discovery/pvp/all-brackets.ipynb.
    FAMILY_DEFAULTS = {
      two_v_two:     { top_n: 1000, job_queue: :pvp_sync_2v2 },
      three_v_three: { top_n: 1000, job_queue: :pvp_sync_3v3 },
      shuffle_like:  { top_n: 500,  job_queue: :pvp_sync_shuffle },
      rbg_like:      { top_n: 500,  job_queue: :pvp_sync_rbg },
      default:       { top_n: 500,  job_queue: :default }
    }.freeze

    # Brackets to skip entirely during discovery — redundant because their
    # characters are fully covered by the per-spec brackets we already sync.
    SKIP_BRACKETS = %w[shuffle-overall].freeze

    EXPLICIT = {}.freeze

    module_function

    def for(bracket)
      return EXPLICIT[bracket] if EXPLICIT.key?(bracket)

      family_key =
        case bracket
        when "2v2"
          :two_v_two
        when "3v3"
          :three_v_three
        when "shuffle-overall", /\Ashuffle-/
          :shuffle_like
        when "rbg", "blitz-overall", /\Ablitz-/
          :rbg_like
        else
          :default
        end

      FAMILY_DEFAULTS[family_key]
    end
  end
end
