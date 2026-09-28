# frozen_string_literal: true

require_relative "test_helper"

class RunnerTest < Minitest::Test
  INTEGERS = Hegel.integers(min_value: -10, max_value: 10)
  ARRAYS = Hegel.arrays(INTEGERS, min_size: 0, max_size: 5)

  def test_passes_a_normal_property
    result = Hegel.test(test_cases: 20, seed: 1234) do |test_case|
      values = test_case.draw(ARRAYS)

      raise "sort changed values" unless values.sort == values.sort
    end

    assert result.passed?
    assert_equal "0.44.0", result.engine_version
  end

  def test_invalid_cases_do_not_consume_the_valid_case_budget_or_report_failures
    valid_values = []
    invocations = 0
    failure_callback_called = false
    integers = Hegel.integers(min_value: 0, max_value: 100)

    result = Hegel.test(
      test_cases: 10,
      seed: 1234,
      on_failure: ->(*) { failure_callback_called = true }
    ) do |test_case|
      invocations += 1
      value = test_case.draw(integers)
      test_case.assume(value.odd?)
      valid_values << value
    end

    assert result.passed?
    assert_equal 10, valid_values.length
    assert_operator invocations, :>, valid_values.length
    assert valid_values.all?(&:odd?)
    refute failure_callback_called
  end

  def test_reject_is_equivalent_to_assume_false
    integers = Hegel.integers(min_value: 0, max_value: 100)
    accepted_with_assume = []
    accepted_with_reject = []

    Hegel.test(test_cases: 10, seed: 1234) do |test_case|
      value = test_case.draw(integers)
      test_case.assume(value.odd?)
      accepted_with_assume << value
    end
    Hegel.test(test_cases: 10, seed: 1234) do |test_case|
      value = test_case.draw(integers)
      test_case.reject unless value.odd?
      accepted_with_reject << value
    end

    assert_equal accepted_with_assume, accepted_with_reject
  end

  def test_shrinks_replays_and_preserves_a_user_failure
    arrays = Hegel.arrays(Hegel.integers(min_value: 0, max_value: 0), min_size: 2, max_size: 2)
    report = nil

    error = assert_raises(RuntimeError) do
      Hegel.test(test_cases: 10, seed: 1234, on_failure: ->(failure) { report = failure }) do |test_case|
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
    arrays = Hegel.arrays(Hegel.integers(min_value: -10, max_value: 10), min_size: 0, max_size: 20)
    report = nil

    assert_raises(RuntimeError) do
      Hegel.test(test_cases: 100, seed: 1234, on_failure: ->(failure) { report = failure }) do |test_case|
        values = test_case.draw(arrays)
        raise "sort lost values" unless values.sort.uniq == values.sort
      end
    end

    assert_equal [ [ 0, 0 ] ], report.drawn_values
    refute_empty report.blob
  end

  def test_reproduces_a_saved_failure_through_the_same_property
    generator = Hegel.integers(min_value: 5, max_value: 5)
    report = discover_integer_failure(generator)
    replay = nil

    replayed = assert_raises(RuntimeError) do
      Hegel.test(reproduce_failure: report.blob, on_failure: ->(failure) { replay = failure }) do |test_case|
        assert_below_five(test_case, generator)
      end
    end

    assert_equal "not below five", replayed.message
    assert_equal report.origin, replay.origin
    assert_equal [ 5 ], replay.drawn_values
  end

  def test_direct_reproduction_rejects_a_property_that_now_passes
    generator = Hegel.integers(min_value: 5, max_value: 5)
    report = discover_integer_failure(generator)

    error = assert_raises(Hegel::ReproductionMismatch) do
      Hegel.test(reproduce_failure: report.blob) { |test_case| test_case.draw(generator) }
    end

    assert_equal "reproduction passed instead of failing", error.message
  end

  def test_direct_reproduction_reports_assumption_rejection_as_a_mismatch
    generator = Hegel.integers(min_value: 5, max_value: 5)
    report = discover_integer_failure(generator)
    failure_callback_called = false

    error = assert_raises(Hegel::ReproductionMismatch) do
      Hegel.test(
        reproduce_failure: report.blob,
        on_failure: ->(*) { failure_callback_called = true }
      ) do |test_case|
        test_case.draw(generator)
        test_case.reject
      end
    end

    assert_equal "reproduction was rejected by an assumption", error.message
    refute failure_callback_called
  end

  def test_direct_reproduction_rejects_an_invalid_blob
    error = assert_raises(Hegel::Native::Error) do
      Hegel.test(reproduce_failure: "not a reproduction blob") {}
    end

    assert_match(/reproduction run failed: .*could not be decoded/, error.message)
  end

  def test_direct_reproduction_accepts_the_current_failure_origin
    generator = Hegel.integers(min_value: 5, max_value: 5)
    report = discover_integer_failure(generator)
    replay = nil

    error = assert_raises(RuntimeError) do
      Hegel.test(reproduce_failure: report.blob, on_failure: ->(failure) { replay = failure }) do |test_case|
        fail_from_another_origin(test_case, generator)
      end
    end

    assert_equal "failure moved", error.message
    assert_match(/RunnerTest#fail_from_another_origin|test\/runner_test\.rb:\d+/, replay.origin)
  end

  def test_direct_reproduction_rejects_an_overrun
    generator = Hegel.integers(min_value: 5, max_value: 5)
    report = discover_integer_failure(generator)

    error = assert_raises(Hegel::ReproductionMismatch) do
      Hegel.test(reproduce_failure: report.blob) do |test_case|
        loop { test_case.draw(generator) }
      end
    end

    assert_equal "reproduction overran while drawing values", error.message
  end

  def test_does_not_classify_interrupt_as_a_property_failure
    assert_raises(Interrupt) do
      Hegel.test(test_cases: 5, seed: 1234) { raise Interrupt, "stop" }
    end
  end

  def test_runner_instances_are_single_use
    runner = Hegel::Runner.new(test_cases: 1, seed: 1234)

    assert runner.test {}.passed?
    error = assert_raises(Hegel::Error) { runner.test {} }
    assert_equal "runner instances can only be used once", error.message
  end

  def test_discovered_failure_replay_rejects_a_changed_origin
    native = ReplayAwareNative.new
    generator = Hegel.integers(min_value: 5, max_value: 5)
    runner = Hegel::Runner.new(
      test_cases: 5,
      seed: 1234,
      native:,
      failure_exceptions: StandardError,
      propagate_exceptions: []
    )

    error = assert_raises(Hegel::ReproductionMismatch) do
      runner.test do |test_case|
        if native.replaying?
          fail_from_another_origin(test_case, generator)
        else
          assert_below_five(test_case, generator)
        end
      end
    end

    assert_match(/reproduction origin changed/, error.message)
  end

  def test_discovered_failure_replay_reports_assumption_rejection_as_a_mismatch
    native = ReplayAwareNative.new
    generator = Hegel.integers(min_value: 5, max_value: 5)
    runner = Hegel::Runner.new(
      test_cases: 5,
      seed: 1234,
      native:,
      failure_exceptions: StandardError,
      propagate_exceptions: []
    )

    error = assert_raises(Hegel::ReproductionMismatch) do
      runner.test do |test_case|
        test_case.draw(generator)
        native.replaying? ? test_case.reject : raise("not below five")
      end
    end

    assert_equal "reproduction was rejected by an assumption", error.message
  end

  def test_unsatisfiable_assumptions_remain_engine_run_errors
    error = assert_raises(Hegel::Native::Error) do
      Hegel.test(test_cases: 1, seed: 1234) { |test_case| test_case.reject }
    end

    assert_match(/property run failed: Unsatisfiable/, error.message)
  end

  def test_excessive_assumption_rejection_remains_an_engine_health_error
    integers = Hegel.integers(min_value: 0, max_value: 100)

    error = assert_raises(Hegel::Native::Error) do
      Hegel.test(test_cases: 5, seed: 1234) do |test_case|
        test_case.assume(test_case.draw(integers) > 100)
      end
    end

    assert_match(/property run failed: FailedHealthCheck: FilterTooMuch/, error.message)
  end

  def test_does_not_classify_frontend_errors_as_property_failures
    error = Hegel::ReproductionMismatch.new("stale blob")

    raised = assert_raises(Hegel::ReproductionMismatch) do
      Hegel.test(test_cases: 5, seed: 1234) { raise error }
    end

    assert_same error, raised
  end

  def test_rejects_draws_after_the_native_test_case_is_freed
    retained_test_case = nil

    Hegel.test(test_cases: 1, seed: 1234) do |test_case|
      retained_test_case = test_case
      test_case.draw(Hegel.integers(min_value: 0, max_value: 0))
    end

    assert_raises(Hegel::ClosedTestCase) do
      retained_test_case.draw(Hegel.integers(min_value: 0, max_value: 0))
    end
  end

  def test_failure_reports_preserve_nested_draws_when_the_property_mutates_them
    integers = Hegel.integers(min_value: 0, max_value: 0)
    inner_arrays = Hegel.arrays(integers, min_size: 1, max_size: 1)
    nested_arrays = Hegel.arrays(inner_arrays, min_size: 1, max_size: 1)
    report = nil

    assert_raises(RuntimeError) do
      Hegel.test(test_cases: 1, seed: 1234, on_failure: ->(failure) { report = failure }) do |test_case|
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
    assert_raises(ArgumentError) { Hegel.integers(min_value: 1, max_value: 0) }
    assert_raises(ArgumentError) { Hegel.integers(min_value: 0, max_value: 2**63) }
    assert_raises(ArgumentError) { Hegel.arrays(INTEGERS, min_size: -1, max_size: 2) }
    assert_raises(ArgumentError) { Hegel.arrays(INTEGERS, min_size: 0, max_size: 2**64) }
  end

  class ReplayAwareNative
    def initialize
      @replaying = false
    end

    def replaying?
      @replaying
    end

    def method_missing(name, *arguments, &block)
      @replaying = true if name == :hegel_test_case_from_blob
      Hegel::Native.public_send(name, *arguments, &block)
    end

    def respond_to_missing?(name, include_private = false)
      Hegel::Native.respond_to?(name, include_private) || super
    end
  end

  private
    def discover_integer_failure(generator)
      report = nil
      assert_raises(RuntimeError) do
        Hegel.test(test_cases: 5, seed: 1234, on_failure: ->(failure) { report = failure }) do |test_case|
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
