# frozen_string_literal: true

require "json"
require "hegel"

MODE, PAYLOAD_PATH = ARGV
GENERATOR = Hegel.integers(min: 0, max: 100)
PROPERTY_INVOCATIONS = []

def property(test_case)
  PROPERTY_INVOCATIONS << true
  value = test_case.draw(GENERATOR)
  raise "not below five" unless value < 5
end

report = nil

begin
  case MODE
  when "discover"
    Hegel.check(max_examples: 100, seed: 1234, on_failure: ->(failure) { report = failure }) do |test_case|
      property(test_case)
    end
  when "replay"
    saved = JSON.parse(File.read(PAYLOAD_PATH))
    Hegel.replay(
      blob: saved.fetch("blob"),
      expected_origin: saved.fetch("origin"),
      max_examples: 100,
      seed: 1234,
      on_failure: ->(failure) { report = failure }
    ) do |test_case|
      property(test_case)
    end
  else
    abort "usage: fresh_process_replay.rb [discover|replay] PAYLOAD_PATH"
  end
rescue RuntimeError => error
  abort "failure was not reported" unless report

  File.write(PAYLOAD_PATH, JSON.generate(
    blob: report.blob,
    drawn_values: report.drawn_values,
    error_message: error.message,
    origin: report.origin,
    process_id: Process.pid,
    property_invocations: PROPERTY_INVOCATIONS.length
  ))
else
  abort "property unexpectedly passed"
end
