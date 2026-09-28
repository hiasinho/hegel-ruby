#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("lib", __dir__)
require "fileutils"
require "hegel"

$stdout.sync = true

MODE = ARGV.fetch(0, "broken")
BLOB_PATH = File.expand_path(ARGV.fetch(1, "tmp/broken-sort.blob"), __dir__)
ORIGIN_PATH = "#{BLOB_PATH}.origin"
MAX_EXAMPLES = 100
SEED = 1234

INTEGERS = Hegel.integers(min: -10, max: 10)
ARRAYS = Hegel.arrays(INTEGERS, min_size: 0, max_size: 20)

def broken_sort_property(test_case)
  values = test_case.draw(ARRAYS)
  actual = values.sort.uniq
  raise "sort lost values" unless actual == values.sort
end

def fixed_sort_property(test_case)
  values = test_case.draw(ARRAYS)
  actual = values.sort
  raise "sort lost values" unless actual == values.sort
end

def print_failure(failure, save:)
  values = failure.drawn_values.fetch(0)
  puts "libhegel version: #{failure.engine_version}"
  puts "final failing array: #{values.inspect}"
  puts "failure origin: #{failure.origin}"
  puts "reproduction blob: #{failure.blob}"

  return unless save

  FileUtils.mkdir_p(File.dirname(BLOB_PATH))
  File.write(BLOB_PATH, "#{failure.blob}\n")
  File.write(ORIGIN_PATH, "#{failure.origin}\n")
  puts "saved reproduction: #{BLOB_PATH}"
end

def run_broken_sort
  Hegel.check(max_examples: MAX_EXAMPLES, seed: SEED, on_failure: ->(failure) { print_failure(failure, save: true) }) do |test_case|
    broken_sort_property(test_case)
  end
end

def replay_broken_sort
  blob = File.read(BLOB_PATH).strip
  expected_origin = File.read(ORIGIN_PATH).strip
  Hegel.replay(
    blob:,
    expected_origin:,
    max_examples: MAX_EXAMPLES,
    seed: SEED,
    on_failure: ->(failure) { print_failure(failure, save: false) }
  ) do |test_case|
    broken_sort_property(test_case)
  end
end

def run_fixed_sort
  result = Hegel.check(max_examples: MAX_EXAMPLES, seed: SEED) do |test_case|
    fixed_sort_property(test_case)
  end

  puts "libhegel version: #{result.engine_version}"
  puts "corrected sort: passed #{MAX_EXAMPLES} examples"
end

begin
  case MODE
  when "broken"
    run_broken_sort
  when "replay"
    replay_broken_sort
  when "fixed"
    run_fixed_sort
  else
    warn "usage: ruby broken_sort.rb [broken|replay|fixed] [blob-path]"
    exit 64
  end
rescue RuntimeError => error
  puts "replayed exception: #{error.class}: #{error.message}"
  puts "replayed backtrace starts: #{error.backtrace.first}"
  exit 1
end
