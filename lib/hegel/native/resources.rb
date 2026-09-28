# frozen_string_literal: true

require_relative "call"

module Hegel
  module Native
    class Resources
      def initialize(adapter:, context:)
        @adapter = adapter
        @context = context
        @owned = []
      end

      def own(handle, free:)
        @owned.unshift [free, handle]
        handle
      end

      def release(handle, free:, active_error: nil)
        index = @owned.index { |operation, owned_handle| operation == free && owned_handle == handle }
        @owned.delete_at(index) if index
        cleanup_call(free, handle, active_error:)
      end

      def cleanup_call(operation, *arguments, active_error: nil)
        result = @adapter.public_send(operation, @context, *arguments)
        return if result == HEGEL_OK
        return if result == HEGEL_E_STOP_TEST && active_error.is_a?(StopTest)
        return if result == HEGEL_E_ASSUME && active_error.is_a?(Control::Rejected)

        detail = @adapter.hegel_context_last_error(@context)
        message = "#{operation} failed (#{result}): #{detail}"
        active_error ? warn(message) : raise(Error, message)
      end

      def close(active_error: nil)
        errors = @owned.filter_map do |operation, handle|
          result = @adapter.public_send(operation, @context, handle)
          next if result == HEGEL_OK

          "#{operation} failed (#{result}): #{@adapter.hegel_context_last_error(@context)}"
        end
        @owned.clear

        return if errors.empty?
        return warn(errors.join("\n")) if active_error

        raise Error, errors.join("\n")
      end
    end
  end
end
