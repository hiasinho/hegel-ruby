# frozen_string_literal: true

require "ffi"
require_relative "errors"
require_relative "native/resources"

module Hegel
  class TestCase
    attr_reader :drawn_values

    def initialize(call:, resources:, handle:)
      @call = call
      @resources = resources
      @handle = handle
      @drawn_values = []
    end

    def draw(generator)
      ensure_active!
      unless generator.respond_to?(:draw) && generator.respond_to?(:label)
        raise ArgumentError, "generator must respond to draw and label"
      end

      value = draw_nested(generator)
      @drawn_values << copy_value(value)
      value
    end

    def draw_nested(generator)
      ensure_active!
      with_span(generator.label(self)) { generator.draw(self) }
    end

    def call_native(operation, *arguments)
      ensure_active!
      @call.call(operation, handle, *arguments)
    end

    def label_from_name(name)
      ensure_active!
      output = FFI::MemoryPointer.new(:uint64)
      @call.call(:hegel_label_from_name, name, output)
      output.read_uint64
    end

    def combine_labels(*labels)
      ensure_active!
      input = FFI::MemoryPointer.new(:uint64, labels.length)
      input.write_array_of_uint64(labels)
      output = FFI::MemoryPointer.new(:uint64)
      @call.call(:hegel_label_combine, input, labels.length, output)
      output.read_uint64
    end

    def new_collection(min_size, max_size)
      ensure_active!
      output = FFI::MemoryPointer.new(:pointer)
      call_native(:hegel_new_collection, min_size, max_size, output)
      collection = @call.non_null(output.read_pointer, :hegel_new_collection)
      @resources.own(collection, free: :hegel_collection_free)
    end

    def collection_more?(collection)
      ensure_active!
      output = FFI::MemoryPointer.new(:bool)
      call_native(:hegel_collection_more, collection, output)
      output.read_uint8 != 0
    end

    def release_collection(collection, active_error: nil)
      ensure_active!
      @resources.release(collection, free: :hegel_collection_free, active_error:)
    end

    def invalidate!
      @handle = nil
    end
    private :invalidate!

    private
      attr_reader :handle

      def ensure_active!
        raise ClosedTestCase, "this test case is no longer active" unless handle
      end

      def with_span(label)
        started = false
        call_native(:hegel_start_span, label)
        started = true
        yield
      ensure
        if started
          @resources.cleanup_call(:hegel_stop_span, handle, false, active_error: $!)
        end
      end

      def copy_value(value)
        value.is_a?(Array) ? value.map { |element| copy_value(element) }.freeze : value
      end
  end
end
