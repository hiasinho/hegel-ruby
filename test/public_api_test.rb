# frozen_string_literal: true

require_relative "test_helper"
require "hegel/minitest"

class PublicApiTest < Minitest::Test
  class GeneratorRecorder
    attr_reader :integer_bounds, :array_bounds

    def call_native(operation, min_value, max_value, output)
      raise "unexpected operation: #{operation}" unless operation == :hegel_generate_integer

      @integer_bounds = [ min_value, max_value ]
      output.write_int64(0)
    end

    def new_collection(min_size, max_size)
      @array_bounds = [ min_size, max_size ]
      Object.new
    end

    def collection_more?(_collection)
      false
    end

    def release_collection(_collection, active_error:)
    end
  end

  class SettingsRecorder
    attr_reader :settings_test_cases, :settings_seed

    def method_missing(name, *arguments, &block)
      case name
      when :hegel_settings_set_test_cases
        @settings_test_cases = arguments.drop(2)
      when :hegel_settings_set_seed
        @settings_seed = arguments.drop(2)
      end

      Hegel::Native.public_send(name, *arguments, &block)
    end

    def respond_to_missing?(name, include_private = false)
      Hegel::Native.respond_to?(name, include_private) || super
    end
  end

  def test_core_entry_point_has_the_upstream_keyword_contract
    assert_equal [
      [ :key, :test_cases ],
      [ :key, :seed ],
      [ :key, :reproduce_failure ],
      [ :key, :on_failure ],
      [ :block, :property ]
    ], Hegel.method(:test).parameters

    refute_respond_to Hegel, :check
    refute_respond_to Hegel, :replay
  end

  def test_generator_entry_points_have_upstream_keyword_contracts
    assert_equal [ [ :key, :min_value ], [ :key, :max_value ] ], Hegel.method(:integers).parameters
    assert_equal [ [ :req, :elements ], [ :key, :min_size ], [ :key, :max_size ] ],
      Hegel.method(:arrays).parameters
  end

  def test_assumption_methods_have_the_upstream_contract
    assert_equal [ [ :req, :condition ] ], Hegel::TestCase.instance_method(:assume).parameters
    assert_empty Hegel::TestCase.instance_method(:reject).parameters
  end

  def test_assume_uses_ruby_truthiness_and_reject_never_returns
    test_case = Hegel::TestCase.new(call: nil, resources: nil, handle: Object.new)

    assert_nil test_case.assume(true)
    assert_nil test_case.assume(0)
    assert_nil test_case.assume("")

    [ false, nil ].each do |condition|
      error = assert_raises(Exception) { test_case.assume(condition) }
      assert_equal Exception, error.class.superclass
      refute_kind_of StandardError, error
    end

    assert_raises(Exception) { test_case.reject }
  end

  def test_rejection_control_flow_is_not_caught_by_an_ordinary_rescue
    test_case = Hegel::TestCase.new(call: nil, resources: nil, handle: Object.new)
    rescued = false

    assert_raises(Exception) do
      begin
        test_case.reject
      rescue StandardError
        rescued = true
        raise
      end
    end
    refute rescued
  end

  def test_minitest_adapter_defaults_test_cases_and_only_accepts_seed
    assert_equal [ [ :key, :test_cases ], [ :key, :seed ], [ :block, :property ] ],
      Hegel::Minitest.instance_method(:hegel).parameters
  end

  def test_public_entry_points_reject_old_and_internal_keywords
    %i[ max_examples native failure_exceptions propagate_exceptions ].each do |keyword|
      assert_raises(ArgumentError) { Hegel.test(**{ keyword => 1 }) {} }
    end

    assert_raises(ArgumentError) { Hegel.integers(min: 0, max: 1) }
    assert_raises(ArgumentError) { Hegel.arrays(Hegel.integers, min: 0, max: 1) }
  end

  def test_public_entry_point_validates_upstream_options
    assert_raises(ArgumentError) { Hegel.test(test_cases: 0) {} }
    assert_raises(ArgumentError) { Hegel.test(test_cases: 2**64) {} }
    assert_raises(ArgumentError) { Hegel.test(seed: -1) {} }
    assert_raises(ArgumentError) { Hegel.test(seed: 2**64) {} }
    assert_raises(ArgumentError) { Hegel.test(reproduce_failure: "") {} }
    assert_raises(ArgumentError) { Hegel.test(reproduce_failure: 123) {} }
  end

  def test_minitest_adapter_leaves_the_seed_unset_by_default
    options = nil
    runner = Object.new
    runner.define_singleton_method(:test) { |&property| property.call }
    host = Class.new { include Hegel::Minitest }.new

    Hegel::Runner.stub(:new, ->(**keywords) { options = keywords; runner }) do
      host.hegel {}
    end

    assert_equal 100, options.fetch(:test_cases)
    assert_nil options.fetch(:seed)
  end

  def test_integer_defaults_cover_the_full_signed_64_bit_range
    recorder = GeneratorRecorder.new

    Hegel.integers.draw(recorder)

    assert_equal [ -(2**63), (2**63) - 1 ], recorder.integer_bounds
  end

  def test_array_defaults_cover_zero_through_uint64_max
    recorder = GeneratorRecorder.new

    Hegel.arrays(Hegel.integers).draw(recorder)

    assert_equal [ 0, (2**64) - 1 ], recorder.array_bounds
  end

  def test_runner_defaults_to_one_hundred_cases_with_an_unset_seed
    native = SettingsRecorder.new
    runner = Hegel::Runner.new(
      native:,
      failure_exceptions: StandardError,
      propagate_exceptions: []
    )

    runner.test {}

    assert_equal [ 100 ], native.settings_test_cases
    assert_equal [ 0, false ], native.settings_seed
  end
end
