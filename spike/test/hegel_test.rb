# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "hegel"
require "minitest/autorun"

class HegelTest < Minitest::Test
  class NativeRecorder
    attr_reader :calls

    def initialize
      @calls = Hash.new(0)
      @stop_next_generate = false
    end

    def stop_next_generate!
      @stop_next_generate = true
    end

    def method_missing(name, *arguments, &block)
      calls[name] += 1
      if name == :hegel_generate_integer && @stop_next_generate
        @stop_next_generate = false
        return Hegel::Native::HEGEL_E_STOP_TEST
      end

      Hegel::Native.public_send(name, *arguments, &block)
    end

    def respond_to_missing?(name, include_private = false)
      Hegel::Native.respond_to?(name, include_private) || super
    end
  end

  def test_normal_completion
    integers = Hegel.integers(min: -10, max: 10)
    arrays = Hegel.arrays(integers, min_size: 0, max_size: 5)

    result = Hegel.check(max_examples: 20, seed: 1234) do |test_case|
      values = test_case.draw(arrays)
      actual = values.sort
      raise "sort changed values" unless actual == values.sort
    end

    assert result.passed?
    assert_equal "0.44.0", result.engine_version
    assert_raises(ArgumentError) { Hegel.integers(min: 0, max: 2**64) }
    assert_raises(ArgumentError) { Hegel.arrays(integers, min_size: 0, max_size: 2**64) }
  end

  def test_user_failure_and_replay_preserve_the_exception
    integers = Hegel.integers(min: 0, max: 0)
    arrays = Hegel.arrays(integers, min_size: 2, max_size: 2)
    first_report = nil

    first_error = assert_raises(RuntimeError) do
      Hegel.check(max_examples: 10, seed: 1234, on_failure: ->(failure) { first_report = failure }) do |test_case|
        broken_sort_property(test_case, arrays)
      end
    end

    replay_report = nil
    replay_error = assert_raises(RuntimeError) do
      Hegel.replay(
        blob: first_report.blob,
        expected_origin: first_report.origin,
        max_examples: 10,
        seed: 1234,
        on_failure: ->(failure) { replay_report = failure }
      ) do |test_case|
        broken_sort_property(test_case, arrays)
      end
    end

    assert_equal "sort lost values", first_error.message
    assert_equal first_error.message, replay_error.message
    assert_equal first_error.backtrace.first, replay_error.backtrace.first
    assert_match %r{RuntimeError at spike/test/hegel_test\.rb:\d+}, first_report.origin
    assert_equal first_report.origin, replay_report.origin
    assert_equal [[0, 0]], replay_report.drawn_values
  end

  def test_native_error_and_stop_test_are_distinct
    context = Hegel::Native.hegel_context_new

    assert_raises(Hegel::Native::StopTest) do
      Hegel::EngineCall.check!(Hegel::Native, context, :injected_call, Hegel::Native::HEGEL_E_STOP_TEST)
    end
    assert_raises(Hegel::Native::Error) do
      Hegel::EngineCall.check!(Hegel::Native, context, :injected_call, -2)
    end
  ensure
    Hegel::Native.hegel_context_free(context) if context && !context.null?
  end

  def test_stop_test_inside_array_closes_spans_and_collection
    native = NativeRecorder.new
    native.stop_next_generate!
    integers = Hegel.integers(min: 0, max: 0)
    arrays = Hegel.arrays(integers, min_size: 1, max_size: 1)
    runner = Hegel::Runner.new(max_examples: 10, seed: 1234, on_failure: nil, native:)

    assert_raises(Hegel::Native::Error) do
      runner.check { |test_case| test_case.draw(arrays) }
    end

    assert_operator native.calls[:hegel_new_collection], :>=, 1
    assert_equal native.calls[:hegel_new_collection], native.calls[:hegel_collection_free]
    assert_equal native.calls[:hegel_start_span], native.calls[:hegel_stop_span]
  end

  def test_interrupt_abandons_the_case_and_frees_owned_handles
    native = NativeRecorder.new
    runner = Hegel::Runner.new(max_examples: 10, seed: 1234, on_failure: nil, native:)

    assert_raises(Interrupt) do
      runner.check { raise Interrupt, "stop now" }
    end

    assert_equal 0, native.calls[:hegel_mark_complete]
    assert_equal 1, native.calls[:hegel_test_case_free]
    assert_equal 1, native.calls[:hegel_run_free]
    assert_equal 1, native.calls[:hegel_settings_free]
    assert_equal 1, native.calls[:hegel_context_free]
  end

  private
    def broken_sort_property(test_case, arrays)
      values = test_case.draw(arrays)
      raise "sort lost values" unless values.sort.uniq == values.sort
    end
end
