# frozen_string_literal: true

require "minitest"
require "hegel"

module Hegel
  module Minitest
    DEFAULT_MAX_EXAMPLES = 100
    DEFAULT_SEED = 0

    attr_reader :hegel_failure

    def hegel(max_examples: DEFAULT_MAX_EXAMPLES, seed: DEFAULT_SEED, on_failure: nil, &property)
      @hegel_failure = nil
      report_failure = lambda do |failure|
        @hegel_failure = failure
        print_hegel_failure(failure)
        on_failure&.call(failure)
      end

      Hegel.check(
        max_examples:,
        seed:,
        on_failure: report_failure,
        failure_exceptions: [ StandardError, ::Minitest::Assertion ],
        propagate_exceptions: [ ::Minitest::Skip ],
        &property
      )
    end

    private
      def print_hegel_failure(failure)
        warn <<~MESSAGE

          Hegel shrank a failing example:
            Drawn values: #{failure.drawn_values.inspect}
            Origin: #{failure.origin}
            Reproduction blob: #{failure.blob}
            Engine: libhegel #{failure.engine_version}
        MESSAGE
      end
  end
end
