#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("lib", __dir__)
require "hegel/native"

module FailingIntegerDemo
  ORIGIN = "n >= 5"
  EXPECTED_MINIMAL_COUNTEREXAMPLE = 5

  class ReproductionMismatch < StandardError; end

  class Run
    def initialize
      @context = Hegel::Native.hegel_context_new
      @owned = []
    end

    def call
      verify_version!
      settings = own(Hegel::Native.owned_handle(@context, :hegel_settings_new), :hegel_settings_free)
      configure(settings)

      run = start_run(settings)
      drive(run)
      result = run_result(run)
      failure = inspect_failure(result)
      replayed_integer = replay(settings, failure.fetch(:blob), failure.fetch(:origin))

      raise ReproductionMismatch, "expected #{EXPECTED_MINIMAL_COUNTEREXAMPLE}, got #{replayed_integer}" unless replayed_integer == EXPECTED_MINIMAL_COUNTEREXAMPLE

      puts "libhegel version: #{Hegel::Native::RELEASE}"
      puts "shrunk failing integer: #{replayed_integer}"
      puts "failure origin: #{failure.fetch(:origin)}"
      puts "reproduction blob: #{failure.fetch(:blob)}"
    ensure
      cleanup
    end

    private
      def verify_version!
        version = Hegel::Native.borrowed_string(@context, :hegel_version)
        return if version == Hegel::Native::RELEASE

        raise Hegel::Native::Error, "binding expects libhegel #{Hegel::Native::RELEASE}, loaded #{version.inspect}"
      end

      def configure(settings)
        check :hegel_settings_set_test_cases, settings, 200
        check :hegel_settings_set_database, settings, ""
        check :hegel_settings_set_derandomize, settings, true
        check :hegel_settings_set_seed, settings, 0xc0ffee, true
      end

      def start_run(settings)
        output = FFI::MemoryPointer.new(:pointer)
        check :hegel_run_start, settings, nil, nil, output
        own(non_null(output.read_pointer, :hegel_run_start), :hegel_run_free)
      end

      def drive(run)
        loop do
          output = FFI::MemoryPointer.new(:pointer)
          check :hegel_next_test_case, run, output
          test_case = output.read_pointer
          break if test_case.null?

          begin
            execute_case(test_case)
          ensure
            check :hegel_test_case_free, test_case
          end
        end
      end

      def execute_case(test_case)
        output = FFI::MemoryPointer.new(:int64)
        result = Hegel::Native.hegel_generate_integer(@context, test_case, 0, 100, output)

        if result == Hegel::Native::HEGEL_E_STOP_TEST
          check :hegel_mark_complete, test_case, Hegel::Native::HEGEL_STATUS_OVERRUN, nil
          return
        end

        Hegel::Native.check!(:hegel_generate_integer, result, @context)
        integer = output.read_int64
        status = integer < EXPECTED_MINIMAL_COUNTEREXAMPLE ? Hegel::Native::HEGEL_STATUS_VALID : Hegel::Native::HEGEL_STATUS_INTERESTING
        origin = status == Hegel::Native::HEGEL_STATUS_INTERESTING ? ORIGIN : nil
        check :hegel_mark_complete, test_case, status, origin
      end

      def run_result(run)
        result = own(Hegel::Native.owned_handle(@context, :hegel_run_result, run), :hegel_run_result_free)
        output = FFI::MemoryPointer.new(:int)
        check :hegel_run_result_status, result, output
        status = output.read_int

        unless status == Hegel::Native::HEGEL_RUN_STATUS_FAILED
          raise Hegel::Native::Error, "expected a failing run, got status #{status}"
        end

        result
      end

      def inspect_failure(result)
        count_output = FFI::MemoryPointer.new(:size_t)
        check :hegel_run_result_failure_count, result, count_output
        count = count_output.read_ulong
        raise Hegel::Native::Error, "expected one failure, got #{count}" unless count == 1

        failure_output = FFI::MemoryPointer.new(:pointer)
        check :hegel_run_result_failure, result, 0, failure_output
        failure = own(non_null(failure_output.read_pointer, :hegel_run_result_failure), :hegel_failure_free)

        origin = Hegel::Native.borrowed_string(@context, :hegel_failure_origin, failure)
        blob = Hegel::Native.borrowed_string(@context, :hegel_failure_reproduction_blob, failure)
        caveat = Hegel::Native.borrowed_string(@context, :hegel_failure_caveat, failure)

        raise Hegel::Native::Error, "expected origin #{ORIGIN.inspect}, got #{origin.inspect}" unless origin == ORIGIN
        raise Hegel::Native::Error, "failure did not include a reproduction blob" unless blob
        raise Hegel::Native::Error, "deterministic failure had caveat: #{caveat}" if caveat

        { origin:, blob: }
      end

      def replay(settings, blob, expected_origin)
        output = FFI::MemoryPointer.new(:pointer)
        check :hegel_test_case_from_blob, settings, blob, nil, nil, output
        test_case = non_null(output.read_pointer, :hegel_test_case_from_blob)

        begin
          integer_output = FFI::MemoryPointer.new(:int64)
          result = Hegel::Native.hegel_generate_integer(@context, test_case, 0, 100, integer_output)
          raise ReproductionMismatch, "blob overran while drawing the integer" if result == Hegel::Native::HEGEL_E_STOP_TEST

          Hegel::Native.check!(:hegel_generate_integer, result, @context)
          integer = integer_output.read_int64
          if integer < EXPECTED_MINIMAL_COUNTEREXAMPLE
            check :hegel_mark_complete, test_case, Hegel::Native::HEGEL_STATUS_VALID, nil
            raise ReproductionMismatch, "blob replay passed with #{integer}"
          end

          check :hegel_mark_complete, test_case, Hegel::Native::HEGEL_STATUS_INTERESTING, expected_origin
          integer
        ensure
          check :hegel_test_case_free, test_case
        end
      end

      def check(operation, *arguments)
        result = Hegel::Native.public_send(operation, @context, *arguments)
        Hegel::Native.check!(operation, result, @context)
      end

      def non_null(pointer, operation)
        raise Hegel::Native::Error, "#{operation} returned a null handle" if pointer.null?

        pointer
      end

      def own(handle, free_operation)
        @owned.unshift [free_operation, handle]
        handle
      end

      def cleanup
        active_error = $!
        cleanup_errors = @owned.filter_map do |operation, handle|
          result = Hegel::Native.public_send(operation, @context, handle)
          next if result == Hegel::Native::HEGEL_OK

          "#{operation} failed (#{result}): #{Hegel::Native.hegel_context_last_error(@context)}"
        end

        result = Hegel::Native.hegel_context_free(@context)
        cleanup_errors << "hegel_context_free failed (#{result})" unless result == Hegel::Native::HEGEL_OK

        return if cleanup_errors.empty?
        warn cleanup_errors.join("\n") if active_error
        raise Hegel::Native::Error, cleanup_errors.join("\n") unless active_error
      end
  end
end

FailingIntegerDemo::Run.new.call
