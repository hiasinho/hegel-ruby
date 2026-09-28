# Hegel for Ruby

A small Ruby frontend for the [Hegel](https://hegel.dev/) property-based testing engine. Ruby runs your test and builds Ruby values; `libhegel` chooses examples, searches, shrinks failures, and creates replay blobs.

This is an early Linux x86-64 implementation pinned to `libhegel` 0.44.0. It currently supports bounded integers, arrays, the core runner, verified failure replay, and Minitest assertions.

## Try the developer experience

```sh
ruby "$(ruby -e 'print Gem.user_dir')/bin/bundle" install
./script/fetch-libhegel
./script/test

# Intentionally fails and shrinks the input to [0, 0]
ruby "$(ruby -e 'print Gem.user_dir')/bin/bundle" exec ruby -Ilib examples/minitest/broken_sort_test.rb

# The corrected implementation passes
ruby "$(ruby -e 'print Gem.user_dir')/bin/bundle" exec ruby -Ilib examples/minitest/fixed_sort_test.rb
```

The property looks like ordinary Minitest:

```ruby
require "hegel/minitest"
require "minitest/autorun"

class SortTest < Minitest::Test
  include Hegel::Minitest

  INTEGERS = Hegel.integers(min: -10, max: 10)
  ARRAYS = Hegel.arrays(INTEGERS, min_size: 0, max_size: 20)

  def test_sort_preserves_values
    hegel(max_examples: 100, seed: 1234) do |test_case|
      values = test_case.draw(ARRAYS)

      assert_equal values.sort, my_sort(values)
    end
  end
end
```

When the assertion fails, Hegel keeps rerunning the block while it shrinks the generated choices. The integration prints the final Ruby values, stable assertion origin, engine version, and reproduction blob, then re-raises the replayed `Minitest::Assertion` so Minitest reports the failure normally.

## A realistic interval-merging example

The interval example models a scheduling system that consolidates overlapping busy periods. It checks three properties: merging preserves occupied time, produces ordered non-overlapping periods, and is idempotent.

First run the deliberately broken implementation:

```sh
ruby "$(ruby -e 'print Gem.user_dir')/bin/bundle" exec \
  ruby -Ilib examples/minitest/broken_interval_merger_test.rb
```

Hegel finds that shortening an existing period to the end of a nested period loses occupied time, then shrinks the input to:

```text
Drawn values: [[0, 1, 0, 0]]
Expected merging [[0, 2], [0, 1]] to preserve occupied time.
Expected: [0, 1]
  Actual: [0]
```

The integers are paired and normalized into nonempty half-open intervals. Run the corrected implementation with:

```sh
ruby "$(ruby -e 'print Gem.user_dir')/bin/bundle" exec \
  ruby -Ilib examples/minitest/interval_merger_test.rb
```

Read [`examples/minitest/broken_interval_merger_test.rb`](examples/minitest/broken_interval_merger_test.rb) for the property, then compare [`examples/broken_interval_merger.rb`](examples/broken_interval_merger.rb) with [`examples/interval_merger.rb`](examples/interval_merger.rb) to see the one-line correction.

## A short code tour

Read these files in order:

1. [`examples/minitest/broken_sort_test.rb`](examples/minitest/broken_sort_test.rb) — the developer-facing API.
2. [`lib/hegel/minitest.rb`](lib/hegel/minitest.rb) — the thin Minitest adapter.
3. [`lib/hegel/runner.rb`](lib/hegel/runner.rb) — run lifecycle, failure classification, and verified replay.
4. [`lib/hegel/test_case.rb`](lib/hegel/test_case.rb) and [`lib/hegel/generators.rb`](lib/hegel/generators.rb) — explicit draws and structured integer-array generation.
5. [`lib/hegel/native/resources.rb`](lib/hegel/native/resources.rb) and [`lib/hegel/native/call.rb`](lib/hegel/native/call.rb) — ownership/cleanup and centralized native result handling.
6. [`lib/hegel/native.rb`](lib/hegel/native.rb) — the small pinned C ABI surface.
7. [`test/`](test) — lifecycle, replay, generator, and Minitest integration behavior.

For the feasibility evidence behind this implementation, see [`docs/ruby-spike-findings.md`](docs/ruby-spike-findings.md). Architectural background is in [`docs/hegel-research.md`](docs/hegel-research.md). The superseded throwaway code and execution plan remain available in Git history.

## Core API

Without Minitest, `Hegel.check` treats ordinary `StandardError` exceptions as property failures:

```ruby
numbers = Hegel.integers(min: 0, max: 100)

Hegel.check(max_examples: 100, seed: 1234) do |test_case|
  number = test_case.draw(numbers)
  raise "too large" unless number < 5
end
```

A final failure is replayed before it is reported and re-raised. `Interrupt`, `SystemExit`, native errors, replay mismatches, and unconfigured `Exception` subclasses are never mistaken for property failures.

## Current boundary

This first implementation deliberately does not yet promise native-library packaging, platforms beyond Linux x86-64, more generator types, assumptions, persistence, callbacks, concurrency, or framework integrations beyond Minitest. Runtime code never downloads native artifacts; setup is explicit and checksum-verified.
