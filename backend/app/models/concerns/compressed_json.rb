# app/models/concerns/compressed_json.rb
# Provides transparent compression/decompression for JSON columns using zstd
# This reduces storage size by ~60% and improves I/O performance
#
# Usage:
#   class MyModel < ApplicationRecord
#     include CompressedJson
#     compressed_json :raw_equipment, :raw_specialization
#   end
#
module CompressedJson
  extend ActiveSupport::Concern

  # Compression level: 3 is a good balance between speed and ratio
  # Higher levels (up to 19) compress better but are slower
  COMPRESSION_LEVEL = 3

  # Magic bytes to identify compressed data (vs legacy uncompressed JSON)
  ZSTD_MAGIC = "\x28\xB5\x2F\xFD".b.freeze

  # rubocop:disable Metrics/BlockLength
  class_methods do
    # Define compressed JSON attributes
    # @param attrs [Array<Symbol>] attribute names to compress
    def compressed_json(*attrs)
      @compressed_json_attrs ||= []
      @compressed_json_attrs.concat(attrs)

      attrs.each do |attr|
        define_compressed_accessors(attr)
      end
    end

    # Get list of compressed JSON attributes
    def compressed_json_attrs
      @compressed_json_attrs || []
    end

    # Compress a value for use with update_columns or update_all
    # @param value [Hash, Array, String, nil] the value to compress
    # @return [String, nil] compressed binary data
    def compress_json_value(value)
      return nil if value.nil?

      json_string = value.is_a?(String) ? value : Oj.dump(value, mode: :compat)
      Zstd.compress(json_string, level: COMPRESSION_LEVEL)
    end

    # Decompress a value
    # @param raw_value [String, nil] compressed binary data
    # @return [Hash, Array, nil] decompressed JSON data
    def decompress_json_value(raw_value)
      return nil if raw_value.nil?

      if compressed_value?(raw_value)
        decompressed = Zstd.decompress(raw_value)
        Oj.load(decompressed, mode: :compat)
      else
        # Legacy uncompressed JSON - parse directly
        raw_value.is_a?(String) ? Oj.load(raw_value, mode: :compat) : raw_value
      end
    rescue Zstd::Error => e
      Rails.logger.error("[CompressedJson] Decompression error: #{e.message}")
      raw_value.is_a?(String) ? Oj.load(raw_value, mode: :compat) : raw_value
    end

    # Check if a value is compressed
    def compressed_value?(raw_value)
      return false unless raw_value.is_a?(String)
      return false if raw_value.bytesize < 4

      raw_value.b[0, 4] == ZSTD_MAGIC
    end

    private

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def define_compressed_accessors(attr)
        # Override the reader to decompress
        define_method(attr) do
          raw_value = read_attribute(attr)
          return nil if raw_value.nil?

          decompress_json(raw_value)
        end

        # Override the writer to compress
        define_method("#{attr}=") do |value|
          return write_attribute(attr, nil) if value.nil?

          compressed = compress_json(value)
          write_attribute(attr, compressed)
        end

        # Add a method to check if the stored value is compressed
        define_method("#{attr}_compressed?") do
          raw_value = read_attribute(attr)
          return false if raw_value.nil?

          self.class.compressed_value?(raw_value)
        end

        # Add a method to get the compression ratio
        define_method("#{attr}_compression_ratio") do
          raw_value = read_attribute(attr)
          return nil if raw_value.nil?

          original_size = Oj.dump(send(attr)).bytesize
          compressed_size = raw_value.bytesize
          ((1 - (compressed_size.to_f / original_size)) * 100).round(1)
        end
      end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
  end
  # rubocop:enable Metrics/BlockLength

  private

    def compress_json(value)
      self.class.compress_json_value(value)
    end

    def decompress_json(raw_value)
      self.class.decompress_json_value(raw_value)
    end
end
