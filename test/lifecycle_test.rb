# frozen_string_literal: true

require_relative "test_helper"

class LifecycleTest < Minitest::Test
  class RejectOnceGenerator
    def initialize(generator)
      @generator = generator
      @rejected = false
    end

    def label(test_case)
      @generator.label(test_case)
    end

    def draw(test_case)
      value = @generator.draw(test_case)
      unless @rejected
        @rejected = true
        test_case.reject
      end
      value
    end
  end

  class NativeRecorder
    attr_reader :calls, :completions

    def initialize
      @calls = Hash.new(0)
      @completions = []
      @next_generate_result = nil
    end

    def stop_next_generate!
      @next_generate_result = Hegel::Native::HEGEL_E_STOP_TEST
    end

    def method_missing(name, *arguments, &block)
      calls[name] += 1
      completions << arguments.drop(2) if name == :hegel_mark_complete
      if name == :hegel_generate_integer && @next_generate_result
        result = @next_generate_result
        @next_generate_result = nil
        return result
      end

      Hegel::Native.public_send(name, *arguments, &block)
    end

    def respond_to_missing?(name, include_private = false)
      Hegel::Native.respond_to?(name, include_private) || super
    end
  end

  def test_an_interrupted_case_releases_every_owned_root_handle
    native = NativeRecorder.new

    runner = build_runner(native, test_cases: 10)

    assert_raises(Interrupt) do
      runner.test { raise Interrupt, "stop now" }
    end

    assert_equal 0, native.calls[:hegel_mark_complete]
    assert_equal 1, native.calls[:hegel_test_case_free]
    assert_equal 1, native.calls[:hegel_run_free]
    assert_equal 1, native.calls[:hegel_settings_free]
    assert_equal 1, native.calls[:hegel_context_free]
  end

  def test_an_overrun_closes_nested_spans_and_the_collection
    native = NativeRecorder.new
    native.stop_next_generate!
    integers = Hegel.integers(min_value: 0, max_value: 0)
    arrays = Hegel.arrays(integers, min_size: 1, max_size: 1)

    runner = build_runner(native, test_cases: 10)

    assert_raises(Hegel::Native::Error) do
      runner.test { |test_case| test_case.draw(arrays) }
    end

    assert_operator native.calls[:hegel_new_collection], :>=, 1
    assert_equal native.calls[:hegel_new_collection], native.calls[:hegel_collection_free]
    assert_equal native.calls[:hegel_start_span], native.calls[:hegel_stop_span]
  end

  def test_an_assumption_rejection_marks_the_case_invalid_and_cleans_nested_resources
    native = NativeRecorder.new
    integers = Hegel.integers(min_value: 0, max_value: 0)
    arrays = Hegel.arrays(RejectOnceGenerator.new(integers), min_size: 1, max_size: 1)
    runner = build_runner(native, test_cases: 1)

    result = runner.test { |test_case| test_case.draw(arrays) }

    assert result.passed?
    assert_includes native.completions, [ Hegel::Native::HEGEL_STATUS_INVALID, nil ]
    assert_equal [ Hegel::Native::HEGEL_STATUS_VALID, nil ], native.completions.last
    assert_operator native.calls[:hegel_new_collection], :>=, 2
    assert_equal native.calls[:hegel_new_collection], native.calls[:hegel_collection_free]
    assert_equal native.calls[:hegel_start_span], native.calls[:hegel_stop_span]
  end

  def test_reentrant_runner_use_does_not_free_the_outer_run_twice
    native = NativeRecorder.new
    runner = build_runner(native, test_cases: 1)

    error = assert_raises(Hegel::Error) do
      runner.test { runner.test {} }
    end

    assert_equal "runner instances can only be used once", error.message
    assert_equal 1, native.calls[:hegel_test_case_free]
    assert_equal 1, native.calls[:hegel_run_free]
    assert_equal 1, native.calls[:hegel_settings_free]
    assert_equal 1, native.calls[:hegel_context_free]
  end

  def test_direct_reproduction_uses_the_blob_run_and_releases_its_handles
    generator = Hegel.integers(min_value: 5, max_value: 5)
    discovered = nil
    assert_raises(RuntimeError) do
      Hegel.test(test_cases: 1, seed: 1234, on_failure: ->(failure) { discovered = failure }) do |test_case|
        raise "not below five" unless test_case.draw(generator) < 5
      end
    end

    native = NativeRecorder.new
    runner = Hegel::Runner.new(
      test_cases: 1,
      seed: 1234,
      native:,
      failure_exceptions: StandardError,
      propagate_exceptions: []
    )

    assert_raises(RuntimeError) do
      runner.test(reproduce_failure: discovered.blob) do |test_case|
        raise "not below five" unless test_case.draw(generator) < 5
      end
    end

    assert_equal 0, native.calls[:hegel_run_start]
    assert_equal 1, native.calls[:hegel_run_start_blob]
    assert_equal 1, native.calls[:hegel_test_case_free]
    assert_equal 1, native.calls[:hegel_run_result_free]
    assert_equal 1, native.calls[:hegel_failure_free]
    assert_equal 1, native.calls[:hegel_run_free]
    assert_equal 1, native.calls[:hegel_settings_free]
    assert_equal 1, native.calls[:hegel_context_free]
  end

  private
    def build_runner(native, test_cases:)
      Hegel::Runner.new(
        test_cases:,
        seed: 1234,
        native:,
        failure_exceptions: StandardError,
        propagate_exceptions: []
      )
    end
end
