# frozen_string_literal: true

class BrokenIntervalMerger
  def self.merge(intervals)
    intervals.sort_by(&:first).each_with_object([]) do |(starts_at, ends_at), merged|
      if merged.empty? || starts_at > merged.last.last
        merged << [ starts_at, ends_at ]
      else
        # Incorrect: a nested interval can shorten the period already collected.
        merged.last[1] = ends_at
      end
    end
  end
end
