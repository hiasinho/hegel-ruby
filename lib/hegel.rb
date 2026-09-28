# frozen_string_literal: true

require_relative "hegel/version"
require_relative "hegel/errors"
require_relative "hegel/native"
require_relative "hegel/generators"
require_relative "hegel/runner"

module Hegel
  module_function

  def integers(min:, max:)
    IntegerGenerator.new(min:, max:)
  end

  def arrays(elements, min_size:, max_size:)
    ArrayGenerator.new(elements, min_size:, max_size:)
  end

  def check(max_examples: 100, seed: nil, on_failure: nil, failure_exceptions: StandardError,
    propagate_exceptions: [], native: Native, &property)
    Runner.new(max_examples:, seed:, on_failure:, failure_exceptions:, propagate_exceptions:, native:).check(&property)
  end

  def replay(blob:, expected_origin:, max_examples: 100, seed: nil, on_failure: nil,
    failure_exceptions: StandardError, propagate_exceptions: [], native: Native, &property)
    Runner.new(max_examples:, seed:, on_failure:, failure_exceptions:, propagate_exceptions:, native:).replay(
      blob:, expected_origin:, &property
    )
  end
end
