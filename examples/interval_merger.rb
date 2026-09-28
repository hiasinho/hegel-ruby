# frozen_string_literal: true

class IntervalMerger
  def self.merge(intervals)
    intervals.sort_by(&:first).each_with_object([]) do |(starts_at, ends_at), merged|
      if merged.empty? || starts_at > merged.last.last
        merged << [ starts_at, ends_at ]
      else
        merged.last[1] = [ merged.last.last, ends_at ].max
      end
    end
  end
end
