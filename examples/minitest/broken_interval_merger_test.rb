# frozen_string_literal: true

require "hegel/minitest"
require "minitest/autorun"
require_relative "../broken_interval_merger"

class BrokenIntervalMergerTest < Minitest::Test
  include Hegel::Minitest

  TIMES = Hegel.arrays(Hegel.integers(min: 0, max: 23), min_size: 0, max_size: 12)

  def test_merging_preserves_occupied_time
    hegel(max_examples: 200, seed: 1234) do |test_case|
      intervals = intervals_from(test_case.draw(TIMES))
      merged = BrokenIntervalMerger.merge(intervals)

      assert_equal occupied_slots(intervals), occupied_slots(merged),
        "Expected merging #{intervals.inspect} to preserve occupied time"
    end
  end

  private
    def intervals_from(times)
      times.each_slice(2).filter_map do |pair|
        next unless pair.length == 2

        starts_at, ends_at = pair.minmax
        [ starts_at, ends_at + 1 ]
      end
    end

    def occupied_slots(intervals)
      intervals.flat_map { |starts_at, ends_at| (starts_at...ends_at).to_a }.uniq.sort
    end
end
