module Pvp
  class SyncCurrentSeasonLeaderboardsJob < ApplicationJob
    queue_as :default

    BRACKETS = %w[
                  2v2
                  3v3
                  rbg
                  blitz-overall
                  shuffle-overall

                  shuffle-deathknight-blood
                  shuffle-deathknight-frost
                  shuffle-deathknight-unholy
                  shuffle-demonhunter-havoc
                  shuffle-demonhunter-vengeance
                  shuffle-druid-balance
                  shuffle-druid-feral
                  shuffle-druid-guardian
                  shuffle-druid-restoration
                  shuffle-evoker-augmentation
                  shuffle-evoker-devastation
                  shuffle-evoker-preservation
                  shuffle-hunter-beastmastery
                  shuffle-hunter-marksmanship
                  shuffle-hunter-survival
                  shuffle-mage-arcane
                  shuffle-mage-fire
                  shuffle-mage-frost
                  shuffle-monk-brewmaster
                  shuffle-monk-mistweaver
                  shuffle-monk-windwalker
                  shuffle-paladin-holy
                  shuffle-paladin-protection
                  shuffle-paladin-retribution
                  shuffle-priest-discipline
                  shuffle-priest-holy
                  shuffle-priest-shadow
                  shuffle-rogue-assassination
                  shuffle-rogue-outlaw
                  shuffle-rogue-subtlety
                  shuffle-shaman-elemental
                  shuffle-shaman-enhancement
                  shuffle-shaman-restoration
                  shuffle-warlock-affliction
                  shuffle-warlock-demonology
                  shuffle-warlock-destruction
                  shuffle-warrior-arms
                  shuffle-warrior-fury
                  shuffle-warrior-protection
    ].freeze
    #                 blitz-deathknight-blood
    #                 blitz-deathknight-frost
    #                 blitz-deathknight-unholy
    #                 blitz-demonhunter-havoc
    #                 blitz-demonhunter-vengeance
    #                 blitz-druid-balance
    #                 blitz-druid-feral
    #                 blitz-druid-guardian
    #                 blitz-druid-restoration
    #                 blitz-evoker-augmentation
    #                 blitz-evoker-devastation
    #                 blitz-evoker-preservation
    #                 blitz-hunter-beastmastery
    #                 blitz-hunter-marksmanship
    #                 blitz-hunter-survival
    #                 blitz-mage-arcane
    #                 blitz-mage-fire
    #                 blitz-mage-frost
    #                 blitz-monk-brewmaster
    #                 blitz-monk-mistweaver
    #                 blitz-monk-windwalker
    #                 blitz-paladin-holy
    #                 blitz-paladin-protection
    #                 blitz-paladin-retribution
    #                 blitz-priest-discipline
    #                 blitz-priest-holy
    #                 blitz-priest-shadow
    #                 blitz-rogue-assassination
    #                 blitz-rogue-outlaw
    #                 blitz-rogue-subtlety
    #                 blitz-shaman-elemental
    #                 blitz-shaman-enhancement
    #                 blitz-shaman-restoration
    #                 blitz-warlock-affliction
    #                 blitz-warlock-demonology
    #                 blitz-warlock-destruction
    #                 blitz-warrior-arms
    #                 blitz-warrior-fury
    #                 blitz-warrior-protection

    def perform(region: "us", locale: "en_US")
      season = PvpSeason.find_by(blizzard_id: 40)
      return unless season

      BRACKETS.each do |bracket|
        SyncLeaderboardJob.perform_later(
          region:  region,
          season:  season,
          bracket: bracket,
          locale:  locale
        )
      end
    end
  end
end
