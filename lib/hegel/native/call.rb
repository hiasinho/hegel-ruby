# frozen_string_literal: true

require_relative "../errors"
require_relative "../native"

module Hegel
  module Native
    class Call
      def initialize(adapter, context)
        @adapter = adapter
        @context = context
      end

      def call(operation, *arguments)
        check!(operation, @adapter.public_send(operation, @context, *arguments))
      end

      def check!(operation, result)
        return if result == HEGEL_OK
        raise StopTest, "#{operation} stopped this test case" if result == HEGEL_E_STOP_TEST
        raise Control::Rejected, "#{operation} rejected this test case" if result == HEGEL_E_ASSUME

        detail = @adapter.hegel_context_last_error(@context)
        raise Error, "#{operation} failed (#{result}): #{detail}"
      end

      def owned_handle(operation, *arguments)
        output = FFI::MemoryPointer.new(:pointer)
        call(operation, *arguments, output)
        non_null(output.read_pointer, operation)
      end

      def borrowed_string(operation, *arguments)
        output = FFI::MemoryPointer.new(:pointer)
        call(operation, *arguments, output)
        pointer = output.read_pointer
        pointer.null? ? nil : pointer.read_string.dup.force_encoding(Encoding::UTF_8)
      end

      def non_null(pointer, operation)
        raise Error, "#{operation} returned a null handle" if pointer.null?

        pointer
      end
    end
  end
end
