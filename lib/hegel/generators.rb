# frozen_string_literal: true

require "ffi"

module Hegel
  SIGNED_64_BIT_RANGE = (-(2**63))..((2**63) - 1)
  UNSIGNED_64_BIT_MAX = (2**64) - 1

  class IntegerGenerator
    LABEL_NAME = "hegel-ruby.integers"

    attr_reader :min_value, :max_value

    def initialize(min_value:, max_value:)
      validate_bound(:min_value, min_value)
      validate_bound(:max_value, max_value)
      if min_value && max_value && max_value < min_value
        raise ArgumentError, "max_value must be greater than or equal to min_value"
      end

      @min_value = min_value
      @max_value = max_value
    end

    def draw(test_case)
      output = FFI::MemoryPointer.new(:int64)
      test_case.call_native(
        :hegel_generate_integer,
        min_value || SIGNED_64_BIT_RANGE.begin,
        max_value || SIGNED_64_BIT_RANGE.end,
        output
      )
      output.read_int64
    end

    def label(test_case)
      test_case.label_from_name(LABEL_NAME)
    end

    private
      def validate_bound(name, value)
        return if value.nil?

        raise ArgumentError, "#{name} must be an Integer or nil" unless value.is_a?(Integer)
        unless SIGNED_64_BIT_RANGE.cover?(value)
          raise ArgumentError, "#{name} is outside libhegel's signed 64-bit range"
        end
      end
  end

  class ArrayGenerator
    LABEL_NAME = "hegel-ruby.arrays"

    attr_reader :elements, :min_size, :max_size

    def initialize(elements, min_size:, max_size:)
      raise ArgumentError, "elements must be a generator" unless elements.respond_to?(:draw) && elements.respond_to?(:label)
      validate_size(:min_size, min_size)
      validate_size(:max_size, max_size, allow_nil: true)
      if max_size && max_size < min_size
        raise ArgumentError, "max_size must be greater than or equal to min_size"
      end

      @elements = elements
      @min_size = min_size
      @max_size = max_size
    end

    def draw(test_case)
      collection = test_case.new_collection(min_size, max_size || UNSIGNED_64_BIT_MAX)
      values = []

      begin
        values << test_case.draw_nested(elements) while test_case.collection_more?(collection)
      ensure
        test_case.release_collection(collection, active_error: $!)
      end

      values
    end

    def label(test_case)
      test_case.combine_labels(test_case.label_from_name(LABEL_NAME), elements.label(test_case))
    end

    private
      def validate_size(name, value, allow_nil: false)
        return if allow_nil && value.nil?

        unless value.is_a?(Integer) && value >= 0
          suffix = allow_nil ? " or nil" : ""
          raise ArgumentError, "#{name} must be a non-negative Integer#{suffix}"
        end
        raise ArgumentError, "#{name} is outside libhegel's unsigned 64-bit range" if value > UNSIGNED_64_BIT_MAX
      end
  end
end
