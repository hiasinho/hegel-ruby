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

  def test_shrinks_varied_arrays_to_a_minimal_duplicate
    arrays = Hegel.arrays(Hegel.integers(min: -10, max: 10), min_size: 0, max_size: 20)
    report = nil

    assert_raises(RuntimeError) do
      Hegel.check(max_examples: 100, seed: 1234, on_failure: ->(failure) { report = failure }) do |test_case|
        values = test_case.draw(arrays)
        raise "sort lost values" unless values.sort.uniq == values.sort
      end
    end

    assert_equal [ [ 0, 0 ] ], report.drawn_values
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

  def test_replay_rejects_a_property_that_now_passes
    generator = Hegel.integers(min: 5, max: 5)
    report = discover_integer_failure(generator)

    error = assert_raises(Hegel::ReproductionMismatch) do
      Hegel.replay(blob: report.blob, expected_origin: report.origin, seed: 1234) do |test_case|
        test_case.draw(generator)
      end
    end

    assert_equal "reproduction passed instead of failing", error.message
  end

  def test_replay_rejects_a_changed_failure_origin
    generator = Hegel.integers(min: 5, max: 5)
    report = discover_integer_failure(generator)

    error = assert_raises(Hegel::ReproductionMismatch) do
      Hegel.replay(blob: report.blob, expected_origin: report.origin, seed: 1234) do |test_case|
        fail_from_another_origin(test_case, generator)
      end
    end

    assert_match(/reproduction origin changed/, error.message)
  end

  def test_replay_rejects_an_overrun
    generator = Hegel.integers(min: 5, max: 5)
    report = discover_integer_failure(generator)

    error = assert_raises(Hegel::ReproductionMismatch) do
      Hegel.replay(blob: report.blob, expected_origin: report.origin, seed: 1234) do |test_case|
        test_case.draw(generator)
        test_case.draw(generator)
        raise "unreachable failure"
      end
    end

    assert_equal "reproduction overran while drawing values", error.message
  end

  def test_does_not_classify_interrupt_as_a_property_failure
    assert_raises(Interrupt) do
      Hegel.check(max_examples: 5, seed: 1234) { raise Interrupt, "stop" }
    end
  end

  def test_runner_instances_are_single_use
    runner = Hegel::Runner.new(max_examples: 1, seed: 1234)

    assert runner.check {}.passed?
    error = assert_raises(Hegel::Error) { runner.check {} }
    assert_equal "runner instances can only be used once", error.message
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

  def test_failure_reports_preserve_nested_draws_when_the_property_mutates_them
    integers = Hegel.integers(min: 0, max: 0)
    inner_arrays = Hegel.arrays(integers, min_size: 1, max_size: 1)
    nested_arrays = Hegel.arrays(inner_arrays, min_size: 1, max_size: 1)
    report = nil

    assert_raises(RuntimeError) do
      Hegel.check(max_examples: 1, seed: 1234, on_failure: ->(failure) { report = failure }) do |test_case|
        values = test_case.draw(nested_arrays)
        values.first.clear
        raise "mutated after drawing"
      end
    end

    assert_equal [ [ [ 0 ] ] ], report.drawn_values
    assert report.drawn_values.frozen?
    assert report.drawn_values.first.frozen?
    assert report.drawn_values.first.first.frozen?
  end

  def test_validates_generator_bounds
    assert_raises(ArgumentError) { Hegel.integers(min: 1, max: 0) }
    assert_raises(ArgumentError) { Hegel.integers(min: 0, max: 2**63) }
    assert_raises(ArgumentError) { Hegel.arrays(INTEGERS, min_size: -1, max_size: 2) }
    assert_raises(ArgumentError) { Hegel.arrays(INTEGERS, min_size: 0, max_size: 2**64) }
  end

  private
    def discover_integer_failure(generator)
      report = nil
      assert_raises(RuntimeError) do
        Hegel.check(max_examples: 5, seed: 1234, on_failure: ->(failure) { report = failure }) do |test_case|
          assert_below_five(test_case, generator)
        end
      end
      report
    end

    def assert_below_five(test_case, generator)
      raise "not below five" unless test_case.draw(generator) < 5
    end

    def fail_from_another_origin(test_case, generator)
      test_case.draw(generator)
      raise "failure moved"
    end
end
