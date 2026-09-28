# frozen_string_literal: true

require "hegel/minitest"
require "minitest/autorun"

class BrokenSortTest < Minitest::Test
  include Hegel::Minitest

  INTEGERS = Hegel.integers(min: -10, max: 10)
  ARRAYS = Hegel.arrays(INTEGERS, min_size: 0, max_size: 20)

  def test_sort_preserves_values
    hegel(max_examples: 100, seed: 1234) do |test_case|
      values = test_case.draw(ARRAYS)

      assert_equal values.sort, broken_sort(values)
    end
  end

  private
    def broken_sort(values)
      values.sort.uniq
    end
end
