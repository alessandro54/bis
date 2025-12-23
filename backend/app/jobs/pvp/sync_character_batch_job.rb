module Pvp
  class SyncCharacterBatchJob < ApplicationJob
    self.enqueue_after_transaction_commit = :always
    queue_as :character_sync

    SYNC_QUEUES = %i[
      character_sync_a
      character_sync_b
      character_sync_c
      character_sync_d
    ].freeze

    def perform(character_ids:, locale: "en_US")
      ids = Array(character_ids).compact
      return if ids.empty?

      parallelism = ENV.fetch("PVP_SYNC_BATCH_PARALLELISM", 2).to_i
      parallelism = 1 if parallelism < 1

      if parallelism == 1
        ids.each do |character_id|
          sync_one(character_id: character_id, locale: locale)
        end
        return
      end

      work_queue = ::Queue.new
      ids.each { |id| work_queue << id }

      threads = Array.new(parallelism) do |i|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            while (character_id = (work_queue.pop(true) rescue nil))
              sync_one(
                character_id: character_id,
                locale: locale,
                queue: SYNC_QUEUES[character_id % SYNC_QUEUES.size]
              )
            end
          end
        end
      end

      threads.each(&:join)
    end

    private

      def sync_one(character_id:, locale:, queue: :character_sync)
        Pvp::SyncCharacterJob.set(queue: queue).perform_later(
          character_id: character_id,
          locale: locale
        )
      end
  end
end
