# frozen_string_literal: true

require_relative "test_helper"

class RunnerTest < Minitest::Test
  INTEGERS = Hegel.integers(min: -10, max: 10)
  ARRAYS = Hegel.arrays(INTEGERS, min_size: 0, max_size: 5)

  def test_passes_a_normal_property
    result = Hegel.check(max_examples: 20, seed: 1234) do |test_case|
      values = test_case.draw(ARRAYS)

      raise "sort changed values" unless values.sort == values.sort
    end

    assert result.passed?
    assert_equal "0.44.0", result.engine_version
  end

  def test_shrinks_replays_and_preserves_a_user_failure
    arrays = Hegel.arrays(Hegel.integers(min: 0, max: 0), min_size: 2, max_size: 2)
    report = nil

    error = assert_raises(RuntimeError) do
      Hegel.check(max_examples: 10, seed: 1234, on_failure: ->(failure) { report = failure }) do |test_case|
        values = test_case.draw(arrays)
        raise "sort lost values" unless values.sort.uniq == values.sort
      end
    end

    assert_equal "sort lost values", error.message
    assert_same report.error, error
    assert_match(%r{test/runner_test\.rb:\d+}, error.backtrace.first)
    assert_equal [ [ 0, 0 ] ], report.drawn_values
    assert_match(/RuntimeError at test\/runner_test\.rb:\d+/, report.origin)
    refute_empty report.blob
  end

  def test_replays_a_saved_failure_through_the_same_property
    generator = Hegel.integers(min: 5, max: 5)
    report = nil

    assert_raises(RuntimeError) do
      Hegel.check(max_examples: 5, seed: 1234, on_failure: ->(failure) { report = failure }) do |test_case|
        assert_below_five(test_case, generator)
      end
    end

    replay = nil
    replayed = assert_raises(RuntimeError) do
      Hegel.replay(
        blob: report.blob,
        expected_origin: report.origin,
        max_examples: 5,
        seed: 1234,
        on_failure: ->(failure) { replay = failure }
      ) do |test_case|
        assert_below_five(test_case, generator)
      end
    end

    assert_equal "not below five", replayed.message
    assert_equal report.origin, replay.origin
    assert_equal [ 5 ], replay.drawn_values
  end

  def test_does_not_classify_interrupt_as_a_property_failure
    assert_raises(Interrupt) do
      Hegel.check(max_examples: 5, seed: 1234) { raise Interrupt, "stop" }
    end
  end

  def test_does_not_classify_frontend_errors_as_property_failures
    error = Hegel::ReproductionMismatch.new("stale blob")

    raised = assert_raises(Hegel::ReproductionMismatch) do
      Hegel.check(max_examples: 5, seed: 1234) { raise error }
    end

    assert_same error, raised
  end

  def test_rejects_draws_after_the_native_test_case_is_freed
    retained_test_case = nil

    Hegel.check(max_examples: 1, seed: 1234) do |test_case|
      retained_test_case = test_case
      test_case.draw(Hegel.integers(min: 0, max: 0))
    end

    assert_raises(Hegel::ClosedTestCase) do
      retained_test_case.draw(Hegel.integers(min: 0, max: 0))
    end
  end

  def test_validates_generator_bounds
    assert_raises(ArgumentError) { Hegel.integers(min: 1, max: 0) }
    assert_raises(ArgumentError) { Hegel.integers(min: 0, max: 2**63) }
    assert_raises(ArgumentError) { Hegel.arrays(INTEGERS, min_size: -1, max_size: 2) }
    assert_raises(ArgumentError) { Hegel.arrays(INTEGERS, min_size: 0, max_size: 2**64) }
  end

  private
    def assert_below_five(test_case, generator)
      raise "not below five" unless test_case.draw(generator) < 5
    end
end
