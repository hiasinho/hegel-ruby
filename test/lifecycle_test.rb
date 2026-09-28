# frozen_string_literal: true

require_relative "test_helper"

class LifecycleTest < Minitest::Test
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

  def test_an_interrupted_case_releases_every_owned_root_handle
    native = NativeRecorder.new

    assert_raises(Interrupt) do
      Hegel.check(max_examples: 10, seed: 1234, native:) { raise Interrupt, "stop now" }
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
    integers = Hegel.integers(min: 0, max: 0)
    arrays = Hegel.arrays(integers, min_size: 1, max_size: 1)

    assert_raises(Hegel::Native::Error) do
      Hegel.check(max_examples: 10, seed: 1234, native:) { |test_case| test_case.draw(arrays) }
    end

    assert_operator native.calls[:hegel_new_collection], :>=, 1
    assert_equal native.calls[:hegel_new_collection], native.calls[:hegel_collection_free]
    assert_equal native.calls[:hegel_start_span], native.calls[:hegel_stop_span]
  end
end
