module Pvp
  module Entries
    class ProcessEntryService < ApplicationService
      def initialize(entry:, locale: "en_US")
        @entry  = entry
        @locale = locale
      end

      def call
        return failure("Entry not found") unless entry

        ActiveRecord::Base.transaction do
          eq_result = ProcessEquipmentService.call(entry: entry, locale: locale)
          return eq_result if eq_result.failure?

          spec_result = ProcessSpecializationService.call(entry: entry)
          return spec_result if spec_result.failure?

          success(entry)
        end
      rescue => e
        failure(e)
      end

      private

        attr_reader :entry, :locale
    end
  end
end
