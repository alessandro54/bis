module Pvp
  module Characters
    class LastEquipmentSnapshotFinderService
      def self.call(character_id:, ttl_hours: 24)
        new(character_id:, ttl_hours: ttl_hours).entry
      end

      def initialize(character_id:, ttl_hours: 24)
        @character_id = character_id
        @ttl_hours = ttl_hours
      end

      def entry
        # Optimized query with proper indexing - uses composite index on character_id + equipment_processed_at
        PvpLeaderboardEntry
          .where(character_id:)
          .where.not(equipment_processed_at:      nil,
                     specialization_processed_at: nil,
                     raw_equipment:               nil,
                     raw_specialization:          nil)
          .where("equipment_processed_at > ?", ttl_hours.hours.ago)
          .order(equipment_processed_at: :desc)
          .limit(1)
          .first
      end

      private

        attr_reader :character_id, :ttl_hours
    end
  end
end
