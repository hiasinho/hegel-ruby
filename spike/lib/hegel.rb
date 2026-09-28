# frozen_string_literal: true

require_relative "hegel/native"

module Hegel
  PROJECT_ROOT = File.expand_path("../..", __dir__)
  INT64_RANGE = (-(2**63))..((2**63) - 1)
  UINT64_MAX = (2**64) - 1

  class ReproductionMismatch < StandardError; end

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
      @drawn_values = drawn_values
      @engine_version = engine_version
      @error = error
      @origin = origin
    end
  end

  class Outcome
    attr_reader :drawn_values, :error, :origin, :status

    def initialize(status:, drawn_values:, error: nil, origin: nil)
      @status = status
      @drawn_values = drawn_values
      @error = error
      @origin = origin
    end
  end

  module EngineCall
    module_function

    def check!(native, context, operation, result)
      return if result == Native::HEGEL_OK
      raise Native::StopTest, "#{operation} stopped this test case" if result == Native::HEGEL_E_STOP_TEST

      detail = native.hegel_context_last_error(context)
      raise Native::Error, "#{operation} failed (#{result}): #{detail}"
    end
  end

  class IntegerGenerator
    LABEL_NAME = "hegel-ruby.integers"

    attr_reader :max, :min

    def initialize(min:, max:)
      raise ArgumentError, "min must be an Integer" unless min.is_a?(Integer)
      raise ArgumentError, "max must be an Integer" unless max.is_a?(Integer)
      raise ArgumentError, "min is outside libhegel's signed 64-bit range" unless INT64_RANGE.cover?(min)
      raise ArgumentError, "max is outside libhegel's signed 64-bit range" unless INT64_RANGE.cover?(max)
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

    attr_reader :elements, :max_size, :min_size

    def initialize(elements, min_size:, max_size:)
      raise ArgumentError, "elements must be a generator" unless elements.respond_to?(:draw) && elements.respond_to?(:label)
      raise ArgumentError, "min_size must be a non-negative Integer" unless min_size.is_a?(Integer) && min_size >= 0
      raise ArgumentError, "max_size must be a non-negative Integer" unless max_size.is_a?(Integer) && max_size >= 0
      raise ArgumentError, "min_size is outside libhegel's unsigned 64-bit range" if min_size > UINT64_MAX
      raise ArgumentError, "max_size is outside libhegel's unsigned 64-bit range" if max_size > UINT64_MAX
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
        test_case.release(:hegel_collection_free, collection, active_error: $!)
      end

      values
    end

    def label(test_case)
      test_case.combine_labels(test_case.label_from_name(LABEL_NAME), elements.label(test_case))
    end
  end

  class TestCase
    attr_reader :drawn_values, :handle

    def initialize(native:, context:, handle:)
      @native = native
      @context = context
      @handle = handle
      @drawn_values = []
    end

    def draw(generator)
      value = draw_nested(generator)
      @drawn_values << copy_value(value)
      value
    end

    def draw_nested(generator)
      with_span(generator.label(self)) { generator.draw(self) }
    end

    def call_native(operation, *arguments)
      result = @native.public_send(operation, @context, @handle, *arguments)
      EngineCall.check!(@native, @context, operation, result)
    end

    def label_from_name(name)
      output = FFI::MemoryPointer.new(:uint64)
      result = @native.hegel_label_from_name(@context, name, output)
      EngineCall.check!(@native, @context, :hegel_label_from_name, result)
      output.read_uint64
    end

    def combine_labels(*labels)
      input = FFI::MemoryPointer.new(:uint64, labels.length)
      input.write_array_of_uint64(labels)
      output = FFI::MemoryPointer.new(:uint64)
      result = @native.hegel_label_combine(@context, input, labels.length, output)
      EngineCall.check!(@native, @context, :hegel_label_combine, result)
      output.read_uint64
    end

    def new_collection(min_size, max_size)
      output = FFI::MemoryPointer.new(:pointer)
      call_native(:hegel_new_collection, min_size, max_size, output)
      pointer = output.read_pointer
      raise Native::Error, "hegel_new_collection returned a null handle" if pointer.null?

      pointer
    end

    def collection_more?(collection)
      output = FFI::MemoryPointer.new(:bool)
      call_native(:hegel_collection_more, collection, output)
      output.read_uint8 != 0
    end

    def release(operation, handle, active_error: nil)
      cleanup_call(operation, handle, active_error:)
    end

    private
      def with_span(label)
        started = false
        call_native(:hegel_start_span, label)
        started = true
        yield
      ensure
        cleanup_call(:hegel_stop_span, @handle, false, active_error: $!) if started
      end

      def cleanup_call(operation, *arguments, active_error: nil)
        result = @native.public_send(operation, @context, *arguments)
        return if result == Native::HEGEL_OK
        return if result == Native::HEGEL_E_STOP_TEST && active_error.is_a?(Native::StopTest)

        if active_error
          warn "#{operation} failed (#{result}): #{@native.hegel_context_last_error(@context)}"
        else
          EngineCall.check!(@native, @context, operation, result)
        end
      end

      def copy_value(value)
        value.is_a?(Array) ? value.dup.freeze : value
      end
  end

  class Runner
    def initialize(max_examples:, seed:, on_failure:, native: Native)
      raise ArgumentError, "max_examples must be a positive Integer" unless max_examples.is_a?(Integer) && max_examples.positive?
      raise ArgumentError, "max_examples is outside libhegel's unsigned 64-bit range" if max_examples > UINT64_MAX
      raise ArgumentError, "seed must be a non-negative Integer" unless seed.is_a?(Integer) && seed >= 0
      raise ArgumentError, "seed is outside libhegel's unsigned 64-bit range" if seed > UINT64_MAX

      @max_examples = max_examples
      @seed = seed
      @on_failure = on_failure
      @native = native
      @owned = []
      @context = @native.hegel_context_new
      raise Native::Error, "hegel_context_new returned a null handle" if @context.null?
    end

    def check(&property)
      verify_version!
      settings = settings()
      run = start_run(settings)
      drive(run, &property)
      result = run_result(run)

      case result_status(result)
      when Native::HEGEL_RUN_STATUS_PASSED
        CheckResult.new(engine_version: engine_version)
      when Native::HEGEL_RUN_STATUS_FAILED
        failure = failure_from(result)
        replay_failure(settings, failure, &property)
      when Native::HEGEL_RUN_STATUS_ERROR
        message = borrowed_string(:hegel_run_result_error, result)
        raise Native::Error, "property run failed: #{message}"
      else
        raise Native::Error, "property run returned an unknown status"
      end
    ensure
      cleanup
    end

    def replay(blob:, expected_origin:, &property)
      verify_version!
      settings = settings()
      replay_failure(settings, { blob:, origin: expected_origin }, &property)
    ensure
      cleanup
    end

    private
      def verify_version!
        version = engine_version
        return if version == Native::RELEASE

        raise Native::Error, "binding expects libhegel #{Native::RELEASE}, loaded #{version.inspect}"
      end

      def settings
        settings = own(owned_handle(:hegel_settings_new), :hegel_settings_free)
        call_native :hegel_settings_set_test_cases, settings, @max_examples
        call_native :hegel_settings_set_database, settings, ""
        call_native :hegel_settings_set_derandomize, settings, true
        call_native :hegel_settings_set_seed, settings, @seed, true
        settings
      end

      def start_run(settings)
        output = FFI::MemoryPointer.new(:pointer)
        call_native :hegel_run_start, settings, nil, nil, output
        own(non_null(output.read_pointer, :hegel_run_start), :hegel_run_free)
      end

      def drive(run, &property)
        loop do
          output = FFI::MemoryPointer.new(:pointer)
          call_native :hegel_next_test_case, run, output
          handle = output.read_pointer
          break if handle.null?

          execute_and_free(handle, &property)
        end
      end

      def execute_and_free(handle, &property)
        test_case = TestCase.new(native: @native, context: @context, handle:)
        invoke(test_case, &property)
      ensure
        release_now(:hegel_test_case_free, handle, active_error: $!) if handle
      end

      def invoke(test_case)
        yield test_case
        call_native :hegel_mark_complete, test_case.handle, Native::HEGEL_STATUS_VALID, nil
        Outcome.new(status: :passed, drawn_values: test_case.drawn_values)
      rescue Native::StopTest
        call_native :hegel_mark_complete, test_case.handle, Native::HEGEL_STATUS_OVERRUN, nil
        Outcome.new(status: :overrun, drawn_values: test_case.drawn_values)
      rescue Native::Error
        raise
      rescue StandardError => error
        origin = origin_for(error)
        call_native :hegel_mark_complete, test_case.handle, Native::HEGEL_STATUS_INTERESTING, origin
        Outcome.new(status: :failed, drawn_values: test_case.drawn_values, error:, origin:)
      end

      def run_result(run)
        own(owned_handle(:hegel_run_result, run), :hegel_run_result_free)
      end

      def result_status(result)
        output = FFI::MemoryPointer.new(:int)
        call_native :hegel_run_result_status, result, output
        output.read_int
      end

      def failure_from(result)
        count_output = FFI::MemoryPointer.new(:size_t)
        call_native :hegel_run_result_failure_count, result, count_output
        count = count_output.read_ulong
        raise Native::Error, "expected one failure, got #{count}" unless count == 1

        output = FFI::MemoryPointer.new(:pointer)
        call_native :hegel_run_result_failure, result, 0, output
        failure = own(non_null(output.read_pointer, :hegel_run_result_failure), :hegel_failure_free)
        blob = borrowed_string(:hegel_failure_reproduction_blob, failure)
        raise Native::Error, "failure did not include a reproduction blob" unless blob

        { blob:, origin: borrowed_string(:hegel_failure_origin, failure) }
      end

      def replay_failure(settings, failure)
        output = FFI::MemoryPointer.new(:pointer)
        call_native :hegel_test_case_from_blob, settings, failure.fetch(:blob), nil, nil, output
        handle = non_null(output.read_pointer, :hegel_test_case_from_blob)
        outcome = execute_and_free(handle) { |test_case| yield test_case }

        case outcome.status
        when :passed
          raise ReproductionMismatch, "reproduction passed instead of failing"
        when :overrun
          raise ReproductionMismatch, "reproduction overran while drawing values"
        end

        unless outcome.origin == failure.fetch(:origin)
          raise ReproductionMismatch, "reproduction origin changed from #{failure.fetch(:origin).inspect} to #{outcome.origin.inspect}"
        end

        report = FailureReport.new(
          blob: failure.fetch(:blob),
          drawn_values: outcome.drawn_values,
          engine_version: engine_version,
          error: outcome.error,
          origin: outcome.origin
        )
        @on_failure&.call(report)
        raise outcome.error, outcome.error.message, outcome.error.backtrace
      end

      def engine_version
        borrowed_string(:hegel_version)
      end

      def origin_for(error)
        location = error.backtrace_locations&.find do |candidate|
          path = candidate.absolute_path || candidate.path
          path && !path.start_with?(File.expand_path(__dir__))
        end
        location ||= error.backtrace_locations&.first
        source = location ? "#{source_path(location)}:#{location.lineno}" : "unknown"
        "#{error.class} at #{source}"
      end

      def source_path(location)
        path = File.expand_path(location.absolute_path || location.path)
        return path.delete_prefix("#{PROJECT_ROOT}/") if path.start_with?("#{PROJECT_ROOT}/")

        path
      end

      def owned_handle(operation, *arguments)
        output = FFI::MemoryPointer.new(:pointer)
        call_native operation, *arguments, output
        non_null(output.read_pointer, operation)
      end

      def borrowed_string(operation, *arguments)
        output = FFI::MemoryPointer.new(:pointer)
        call_native operation, *arguments, output
        pointer = output.read_pointer
        pointer.null? ? nil : pointer.read_string.dup
      end

      def call_native(operation, *arguments)
        result = @native.public_send(operation, @context, *arguments)
        EngineCall.check!(@native, @context, operation, result)
      end

      def non_null(pointer, operation)
        raise Native::Error, "#{operation} returned a null handle" if pointer.null?

        pointer
      end

      def own(handle, free_operation)
        @owned.unshift [free_operation, handle]
        handle
      end

      def release_now(operation, handle, active_error: nil)
        result = @native.public_send(operation, @context, handle)
        return if result == Native::HEGEL_OK

        message = "#{operation} failed (#{result}): #{@native.hegel_context_last_error(@context)}"
        if active_error
          warn message
        else
          raise Native::Error, message
        end
      end

      def cleanup
        return unless @context

        active_error = $!
        cleanup_errors = @owned.filter_map do |operation, handle|
          result = @native.public_send(operation, @context, handle)
          next if result == Native::HEGEL_OK

          "#{operation} failed (#{result}): #{@native.hegel_context_last_error(@context)}"
        end
        @owned.clear

        result = @native.hegel_context_free(@context)
        cleanup_errors << "hegel_context_free failed (#{result})" unless result == Native::HEGEL_OK
        @context = nil

        return if cleanup_errors.empty?
        warn cleanup_errors.join("\n") if active_error
        raise Native::Error, cleanup_errors.join("\n") unless active_error
      end
  end

  module_function

  def integers(min:, max:)
    IntegerGenerator.new(min:, max:)
  end

  def arrays(elements, min_size:, max_size:)
    ArrayGenerator.new(elements, min_size:, max_size:)
  end

  def check(max_examples:, seed:, on_failure: nil, &property)
    Runner.new(max_examples:, seed:, on_failure:).check(&property)
  end

  def replay(blob:, expected_origin:, max_examples:, seed:, on_failure: nil, &property)
    Runner.new(max_examples:, seed:, on_failure:).replay(blob:, expected_origin:, &property)
  end
end
