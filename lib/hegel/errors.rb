# frozen_string_literal: true

module Hegel
  class Error < StandardError; end
  class ReproductionMismatch < Error; end
  class ClosedTestCase < Error; end
end
