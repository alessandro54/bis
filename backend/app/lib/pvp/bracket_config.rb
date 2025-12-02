# app/lib/pvp/bracket_config.rb
module Pvp
  module BracketConfig
    # Defaults por familia
    FAMILY_DEFAULTS = {
      two_v_two:     {
        rating_min: 2100,
        job_queue:  :pvp_sync_2v2
      },
      three_v_three: {
        rating_min: 2200,
        job_queue:  :pvp_sync_3v3
      },
      shuffle_like:  {
        rating_min: 2400,
        job_queue:  :pvp_sync_shuffle
      },
      rbg_like:      {
        rating_min: 2200,
        job_queue:  :pvp_sync_rbg
      }
    }.freeze

    # Overrides específicos por bracket, por si quieres tunear cosas concretas
    # (puedes dejarlo vacío al inicio)
    EXPLICIT = {
      # "2v2"                    => { rating_min: 2050, job_queue: :pvp_sync_2v2_fast },
      # "shuffle-overall"        => { rating_min: 2450, job_queue: :pvp_sync_shuffle },
      # "blitz-overall"          => { rating_min: 2300, job_queue: :pvp_sync_rbg_fast },
      # "shuffle-druid-balance"  => { rating_min: 2500, job_queue: :pvp_sync_shuffle },
    }.freeze

    module_function

    def for(bracket)
      # 1) override explícito si existe
      return EXPLICIT[bracket] if EXPLICIT.key?(bracket)

      # 2) asignar familia según el nombre de la *queue* (bracket Blizzard)
      family_key =
        case bracket
        when "2v2"
          :two_v_two
        when "3v3"
          :three_v_three

          # Shuffle-like
        when "shuffle-overall", /\Ashuffle-/
          :shuffle_like

          # RBG + Blitz-like
        when "rbg", "blitz-overall", /\Ablitz-/
          :rbg_like

        else
          nil
        end

      return nil unless family_key

      FAMILY_DEFAULTS[family_key]
    end
  end
end
