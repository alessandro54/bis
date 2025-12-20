module TestHelpers
  def create_test_season(**overrides)
    create(:pvp_season, blizzard_id: 1, **overrides)
  end

  def create_test_leaderboard(**overrides)
    season = overrides.delete(:pvp_season) || create_test_season
    create(:pvp_leaderboard, pvp_season: season, **overrides)
  end

  def valid_brackets
    [ '2v2', '3v3', 'rbg', 'shuffle' ]
  end

  def valid_regions
    [ 'us', 'eu', 'kr', 'tw', 'cn' ]
  end

  def expect_timestamp_within_precision(actual, expected, precision_seconds = 0.001)
    expect(actual).to be_within(precision_seconds.seconds).of(expected)
  end
end
