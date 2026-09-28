# frozen_string_literal: true

require_relative "hegel/version"
require_relative "hegel/errors"
require_relative "hegel/native"
require_relative "hegel/generators"
require_relative "hegel/runner"

module Hegel
  module_function

  def integers(min_value: nil, max_value: nil)
    IntegerGenerator.new(min_value:, max_value:)
  end

  def arrays(elements, min_size: 0, max_size: nil)
    ArrayGenerator.new(elements, min_size:, max_size:)
  end

  def test(test_cases: 100, seed: nil, reproduce_failure: nil, on_failure: nil, &property)
    Runner.new(test_cases:, seed:, on_failure:).test(reproduce_failure:, &property)
  end
end
