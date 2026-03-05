module Pvp
  module SyncConfig
    EQUIPMENT_TTL = 1.hour.freeze  # how long before an entry needs a fresh API fetch
    META_TTL      = 1.week.freeze  # how long before character metadata is considered stale
  end
end
