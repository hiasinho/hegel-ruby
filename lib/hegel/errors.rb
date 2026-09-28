# frozen_string_literal: true

module Hegel
  class Error < StandardError; end
  class ReproductionMismatch < Error; end
  class ClosedTestCase < Error; end

  module Control
    class Rejected < Exception; end
  end
  private_constant :Control
end
