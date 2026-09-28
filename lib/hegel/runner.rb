# frozen_string_literal: true

require "ffi"
require "rbconfig"
require_relative "errors"
require_relative "native/resources"
require_relative "test_case"

module Hegel
  class CheckResult
    attr_reader :engine_version

    def initialize(engine_version:)
      @engine_version = engine_version
    end

    def passed?
      true
    end
  end

  class FailureReport
    attr_reader :blob, :drawn_values, :engine_version, :error, :origin

    def initialize(blob:, drawn_values:, engine_version:, error:, origin:)
      @blob = blob
      @drawn_values = drawn_values.freeze
      @engine_version = engine_version
      @error = error
      @origin = origin
    end
  end

  class Runner
    LIBRARY_ROOT = File.expand_path(__dir__)
    PROJECT_ROOT = File.expand_path("../..", __dir__)
    WORKING_ROOT = File.expand_path(Dir.pwd)
    RUBY_LIBRARY_ROOTS = ([ RbConfig::CONFIG["rubylibdir"], RbConfig::CONFIG["archdir"] ] + Gem.path)
      .compact.map { |path| File.expand_path(path) }.uniq.freeze

    Outcome = Data.define(:status, :drawn_values, :error, :origin)

    def initialize(max_examples: 100, seed: nil, on_failure: nil, failure_exceptions: StandardError,
      propagate_exceptions: [], native: Native)
      validate_max_examples(max_examples)
      validate_seed(seed)

      @max_examples = max_examples
      @seed = seed
      @on_failure = on_failure
      @failure_exceptions = normalize_exception_classes(:failure_exceptions, failure_exceptions)
      @propagate_exceptions = normalize_exception_classes(:propagate_exceptions, propagate_exceptions)
      @native = native
      @context = @native.hegel_context_new
      if !@context || @context.null?
        raise Native::Error, "hegel_context_new returned a null handle"
      end

      @call = Native::Call.new(@native, @context)
      @resources = Native::Resources.new(adapter: @native, context: @context)
    end

    def check(&property)
      raise ArgumentError, "a property block is required" unless property

      verify_version!
      settings = build_settings
      run = start_run(settings)
      drive(run, &property)
      result = run_result(run)

      case result_status(result)
      when Native::HEGEL_RUN_STATUS_PASSED
        CheckResult.new(engine_version: engine_version)
      when Native::HEGEL_RUN_STATUS_FAILED
        replay_failure(settings, failure_from(result), &property)
      when Native::HEGEL_RUN_STATUS_ERROR
        raise Native::Error, "property run failed: #{@call.borrowed_string(:hegel_run_result_error, result)}"
      else
        raise Native::Error, "property run returned an unknown status"
      end
    ensure
      cleanup
    end

    def replay(blob:, expected_origin:, &property)
      raise ArgumentError, "blob must be a non-empty String" unless blob.is_a?(String) && !blob.empty?
      raise ArgumentError, "expected_origin must be a non-empty String" unless expected_origin.is_a?(String) && !expected_origin.empty?
      raise ArgumentError, "a property block is required" unless property

      verify_version!
      settings = build_settings
      replay_failure(settings, { blob:, origin: expected_origin }, &property)
    ensure
      cleanup
    end

    private
      def validate_max_examples(value)
        unless value.is_a?(Integer) && value.positive?
          raise ArgumentError, "max_examples must be a positive Integer"
        end
        if value > UNSIGNED_64_BIT_MAX
          raise ArgumentError, "max_examples is outside libhegel's unsigned 64-bit range"
        end
      end

      def validate_seed(value)
        return if value.nil?
        unless value.is_a?(Integer) && value >= 0
          raise ArgumentError, "seed must be nil or a non-negative Integer"
        end
        if value > UNSIGNED_64_BIT_MAX
          raise ArgumentError, "seed is outside libhegel's unsigned 64-bit range"
        end
      end

      def normalize_exception_classes(name, exceptions)
        classes = exceptions.is_a?(Array) ? exceptions : [ exceptions ]
        unless classes.all? { |exception_class| exception_class.is_a?(Class) && exception_class <= Exception }
          raise ArgumentError, "#{name} must contain Exception classes"
        end

        classes.freeze
      end

      def verify_version!
        version = engine_version
        return if version == Native::RELEASE

        raise Native::Error, "binding expects libhegel #{Native::RELEASE}, loaded #{version.inspect}"
      end

      def build_settings
        settings = own(@call.owned_handle(:hegel_settings_new), free: :hegel_settings_free)
        @call.call(:hegel_settings_set_test_cases, settings, @max_examples)
        @call.call(:hegel_settings_set_database, settings, "")
        @call.call(:hegel_settings_set_report_multiple_failures, settings, false)
        @call.call(:hegel_settings_set_seed, settings, @seed || 0, !@seed.nil?)
        settings
      end

      def start_run(settings)
        output = FFI::MemoryPointer.new(:pointer)
        @call.call(:hegel_run_start, settings, nil, nil, output)
        own(@call.non_null(output.read_pointer, :hegel_run_start), free: :hegel_run_free)
      end

      def drive(run, &property)
        loop do
          output = FFI::MemoryPointer.new(:pointer)
          @call.call(:hegel_next_test_case, run, output)
          handle = output.read_pointer
          break if handle.null?

          execute_and_free(handle, &property)
        end
      end

      def execute_and_free(handle, &property)
        own(handle, free: :hegel_test_case_free)
        test_case = TestCase.new(call: @call, resources: @resources, handle:)
        invoke(test_case, &property)
      ensure
        test_case&.__send__(:invalidate!)
        @resources.release(handle, free: :hegel_test_case_free, active_error: $!) if handle
      end

      def invoke(test_case)
        yield test_case
        @call.call(:hegel_mark_complete, native_handle(test_case), Native::HEGEL_STATUS_VALID, nil)
        Outcome.new(status: :passed, drawn_values: test_case.drawn_values, error: nil, origin: nil)
      rescue Native::StopTest
        @call.call(:hegel_mark_complete, native_handle(test_case), Native::HEGEL_STATUS_OVERRUN, nil)
        Outcome.new(status: :overrun, drawn_values: test_case.drawn_values, error: nil, origin: nil)
      rescue Native::Error
        raise
      rescue Exception => error # Property assertion classes need not inherit StandardError.
        raise if fatal_exception?(error) || !property_failure?(error)

        origin = origin_for(error)
        @call.call(:hegel_mark_complete, native_handle(test_case), Native::HEGEL_STATUS_INTERESTING, origin)
        Outcome.new(status: :failed, drawn_values: test_case.drawn_values, error:, origin:)
      end

      def native_handle(test_case)
        test_case.__send__(:handle)
      end

      def fatal_exception?(error)
        error.is_a?(SystemExit) || error.is_a?(SignalException) || error.is_a?(Hegel::Error) ||
          error.is_a?(Native::Error) || error.is_a?(Native::StopTest) ||
          @propagate_exceptions.any? { |exception_class| error.is_a?(exception_class) }
      end

      def property_failure?(error)
        @failure_exceptions.any? { |exception_class| error.is_a?(exception_class) }
      end

      def run_result(run)
        own(@call.owned_handle(:hegel_run_result, run), free: :hegel_run_result_free)
      end

      def result_status(result)
        output = FFI::MemoryPointer.new(:int)
        @call.call(:hegel_run_result_status, result, output)
        output.read_int
      end

      def failure_from(result)
        count_output = FFI::MemoryPointer.new(:size_t)
        @call.call(:hegel_run_result_failure_count, result, count_output)
        count = count_output.read_ulong
        raise Native::Error, "expected one failure, got #{count}" unless count == 1

        failure = own(@call.owned_handle(:hegel_run_result_failure, result, 0), free: :hegel_failure_free)
        blob = @call.borrowed_string(:hegel_failure_reproduction_blob, failure)
        raise Native::Error, "failure did not include a reproduction blob" unless blob

        { blob:, origin: @call.borrowed_string(:hegel_failure_origin, failure) }
      end

      def replay_failure(settings, failure)
        output = FFI::MemoryPointer.new(:pointer)
        @call.call(:hegel_test_case_from_blob, settings, failure.fetch(:blob), nil, nil, output)
        handle = @call.non_null(output.read_pointer, :hegel_test_case_from_blob)
        outcome = execute_and_free(handle) { |test_case| yield test_case }

        case outcome.status
        when :passed
          raise ReproductionMismatch, "reproduction passed instead of failing"
        when :overrun
          raise ReproductionMismatch, "reproduction overran while drawing values"
        end

        expected_origin = failure.fetch(:origin)
        unless outcome.origin == expected_origin
          raise ReproductionMismatch,
            "reproduction origin changed from #{expected_origin.inspect} to #{outcome.origin.inspect}"
        end

        report = FailureReport.new(
          blob: failure.fetch(:blob),
          drawn_values: outcome.drawn_values,
          engine_version: engine_version,
          error: outcome.error,
          origin: outcome.origin
        )
        @on_failure&.call(report)
        raise outcome.error
      end

      def engine_version
        @call.borrowed_string(:hegel_version)
      end

      def origin_for(error)
        locations = error.backtrace_locations || []
        location = locations.find { |candidate| user_frame?(candidate) }
        location ||= locations.find { |candidate| outside_hegel?(candidate) }
        location ||= locations.first
        source = location ? "#{source_path(location)}:#{location.lineno}" : "unknown"
        "#{error.class} at #{source}"
      end

      def user_frame?(location)
        return false unless outside_hegel?(location)

        path = File.expand_path(location.absolute_path || location.path)
        RUBY_LIBRARY_ROOTS.none? { |root| path == root || path.start_with?("#{root}/") }
      end

      def outside_hegel?(location)
        raw_path = location.absolute_path || location.path
        return false unless raw_path

        path = File.expand_path(raw_path)
        path != LIBRARY_ROOT && !path.start_with?("#{LIBRARY_ROOT}/")
      end

      def source_path(location)
        path = File.expand_path(location.absolute_path || location.path)
        return path.delete_prefix("#{WORKING_ROOT}/") if path.start_with?("#{WORKING_ROOT}/")
        return path.delete_prefix("#{PROJECT_ROOT}/") if path.start_with?("#{PROJECT_ROOT}/")

        path
      end

      def own(handle, free:)
        @resources.own(handle, free:)
      end

      def cleanup
        return unless @context

        active_error = $!
        cleanup_error = nil
        begin
          @resources.close(active_error:)
        rescue Native::Error => error
          cleanup_error = error
        end

        result = @native.hegel_context_free(@context)
        @context = nil
        if result != Native::HEGEL_OK
          context_error = Native::Error.new("hegel_context_free failed (#{result})")
          cleanup_error ||= context_error
        end

        return unless cleanup_error
        return warn(cleanup_error.message) if active_error

        raise cleanup_error
      end
  end
end
