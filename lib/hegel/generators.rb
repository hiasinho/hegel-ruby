# frozen_string_literal: true

require "ffi"

module Hegel
  SIGNED_64_BIT_RANGE = (-(2**63))..((2**63) - 1)
  UNSIGNED_64_BIT_MAX = (2**64) - 1

  class IntegerGenerator
    LABEL_NAME = "hegel-ruby.integers"

    attr_reader :min, :max

    def initialize(min:, max:)
      raise ArgumentError, "min must be an Integer" unless min.is_a?(Integer)
      raise ArgumentError, "max must be an Integer" unless max.is_a?(Integer)
      raise ArgumentError, "min is outside libhegel's signed 64-bit range" unless SIGNED_64_BIT_RANGE.cover?(min)
      raise ArgumentError, "max is outside libhegel's signed 64-bit range" unless SIGNED_64_BIT_RANGE.cover?(max)
      raise ArgumentError, "max must be greater than or equal to min" if max < min

      @min = min
      @max = max
    end

    def draw(test_case)
      output = FFI::MemoryPointer.new(:int64)
      test_case.call_native(:hegel_generate_integer, min, max, output)
      output.read_int64
    end

    def label(test_case)
      test_case.label_from_name(LABEL_NAME)
    end
  end

  class ArrayGenerator
    LABEL_NAME = "hegel-ruby.arrays"

    attr_reader :elements, :min_size, :max_size

    def initialize(elements, min_size:, max_size:)
      raise ArgumentError, "elements must be a generator" unless elements.respond_to?(:draw) && elements.respond_to?(:label)
      validate_size(:min_size, min_size)
      validate_size(:max_size, max_size)
      raise ArgumentError, "max_size must be greater than or equal to min_size" if max_size < min_size

      @elements = elements
      @min_size = min_size
      @max_size = max_size
    end

    def draw(test_case)
      collection = test_case.new_collection(min_size, max_size)
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
      def validate_size(name, value)
        unless value.is_a?(Integer) && value >= 0
          raise ArgumentError, "#{name} must be a non-negative Integer"
        end
        raise ArgumentError, "#{name} is outside libhegel's unsigned 64-bit range" if value > UNSIGNED_64_BIT_MAX
      end
  end
end
