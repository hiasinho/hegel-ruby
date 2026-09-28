# frozen_string_literal: true

require "minitest"
require "hegel"

module Hegel
  module Minitest
    DEFAULT_TEST_CASES = 100

    attr_reader :hegel_failure

    def hegel(test_cases: DEFAULT_TEST_CASES, seed: nil, &property)
      @hegel_failure = nil
      report_failure = lambda do |failure|
        @hegel_failure = failure
        print_hegel_failure(failure)
      end

      Runner.new(
        test_cases:,
        seed:,
        on_failure: report_failure,
        failure_exceptions: [ StandardError, ::Minitest::Assertion ],
        propagate_exceptions: [ ::Minitest::Skip ]
      ).test(&property)
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
