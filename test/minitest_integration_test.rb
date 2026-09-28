# frozen_string_literal: true

require_relative "test_helper"
require "hegel/minitest"

class MinitestIntegrationTest < Minitest::Test
  class PropertyHost
    include ::Minitest::Assertions
    include Hegel::Minitest

    attr_accessor :assertions

    def initialize
      @assertions = 0
    end
  end

  def test_shrinks_and_reraises_minitest_assertions
    host = PropertyHost.new
    arrays = Hegel.arrays(Hegel.integers(min_value: 0, max_value: 0), min_size: 2, max_size: 2)

    _out, error_output = capture_io do
      error = assert_raises(::Minitest::Assertion) do
        host.hegel(test_cases: 10, seed: 1234) do |test_case|
          values = test_case.draw(arrays)
          host.assert_equal values.sort, values.sort.uniq
        end
      end

      assert_match(/Expected: \[0, 0\]/, error.message)
    end

    assert_equal [ [ 0, 0 ] ], host.hegel_failure.drawn_values
    assert_match(/Minitest::Assertion at test\/minitest_integration_test\.rb:\d+/, host.hegel_failure.origin)
    assert_includes error_output, "Hegel shrank a failing example"
    assert_includes error_output, "Drawn values: [[0, 0]]"
    assert_includes error_output, "Reproduction blob:"
  end

  def test_propagates_minitest_skips_without_shrinking_or_reporting
    host = PropertyHost.new

    _out, error_output = capture_io do
      assert_raises(::Minitest::Skip) do
        host.hegel(test_cases: 10, seed: 1234) do
          host.skip "not supported here"
        end
      end
    end

    assert_nil host.hegel_failure
    assert_empty error_output
  end

  def test_still_shrinks_standard_errors
    host = PropertyHost.new

    error = assert_raises(RuntimeError) do
      capture_io do
        host.hegel(test_cases: 5, seed: 1234) do |test_case|
          value = test_case.draw(Hegel.integers(min_value: 1, max_value: 1))
          raise "ordinary failure" if value == 1
        end
      end
    end

    assert_equal "ordinary failure", error.message
    assert_equal [ 1 ], host.hegel_failure.drawn_values
  end
end
