module Pvp
  module Entries
    class ProcessEntryService < ApplicationService
      def initialize(entry:, locale: "en_US")
        @entry  = entry
        @locale = locale
      end

      # rubocop:disable Metrics/AbcSize
      def call
        return failure("Entry not found") unless entry

        eq_result = ProcessEquipmentService.call(entry: entry, locale: locale)
        return eq_result if eq_result.failure?

        spec_result = ProcessSpecializationService.call(entry: entry, locale: locale)
        return spec_result if spec_result.failure?

        # Merge attrs from both services into a single UPDATE
        merged_attrs = {}
        merged_attrs.merge!(eq_result.context[:attrs]) if eq_result.context[:attrs]
        merged_attrs.merge!(spec_result.context[:attrs]) if spec_result.context[:attrs]

        if merged_attrs.any?
          ActiveRecord::Base.transaction do
            # rubocop:disable Rails/SkipsModelValidations
            entry.update_columns(merged_attrs)
            # rubocop:enable Rails/SkipsModelValidations

            # Rebuild entry items if equipment was processed
            eq_result.context[:rebuild_items_proc]&.call

            # Rebuild character talents if build changed
            spec_result.context[:rebuild_talents_proc]&.call
          end

          # Free raw blobs now that structured data is extracted.
          # Saves ~5 KB/entry (97% of row size).
          # rubocop:disable Rails/SkipsModelValidations
          entry.update_columns(raw_equipment: nil, raw_specialization: nil)
          # rubocop:enable Rails/SkipsModelValidations
        end

        success(entry)
      rescue => e
        failure(e)
      end
      # rubocop:enable Metrics/AbcSize

      private

        attr_reader :entry, :locale
    end
  end
end
