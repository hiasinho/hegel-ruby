> [!IMPORTANT]
> `hegel-ruby` is an independent, experimental project. It is not affiliated with, maintained by, or endorsed by the Hegel project, its maintainers, or Antithesis.
>
> No gem has been published. The API may change without notice, and the current implementation supports only CRuby on Linux x86-64. Upstream Hegel is also in beta; see its [compatibility notice](https://hegel.dev/compatibility).

# Hegel for Ruby

[![CI](https://github.com/hiasinho/hegel-ruby/actions/workflows/ci.yml/badge.svg)](https://github.com/hiasinho/hegel-ruby/actions/workflows/ci.yml)

- [Hegel documentation](https://hegel.dev/)
- [Upstream Hegel repositories](https://github.com/hegeldev)

`hegel-ruby` is a property-based testing frontend for Ruby. Ruby runs the property and constructs Ruby values; the native [`libhegel`](https://hegel.dev/reference/libhegel) engine chooses examples, searches for failures, shrinks them, and creates reproduction blobs.

This repository is currently pinned to `libhegel` 0.44.0 and provides bounded integers, arrays, a core runner with verified failure replay, and Minitest integration.

## Installation

`hegel-ruby` has not been released as a gem. To try it from source, clone this repository on Linux x86-64 and use Ruby 3.4.10, as specified by `.ruby-version`:

```sh
git clone https://github.com/hiasinho/hegel-ruby.git
cd hegel-ruby
bundle install
./script/fetch-libhegel
```

The fetch script downloads the pinned engine and matching header into `vendor/` and verifies their upstream checksums. Runtime code and tests never download native files automatically.

If you use Mise, enable `.ruby-version` support once and install the selected Ruby before running Bundler:

```sh
mise settings add idiomatic_version_file_enable_tools ruby
mise install
```

Other Ruby managers that honor `.ruby-version` work too. Building Ruby or the `ffi` gem may require the usual compiler and platform development packages. If `bundle` is unavailable for the active Ruby, install it with `gem install bundler`.

## Quickstart

Like the upstream Hegel quickstart, this example tests a deliberately broken sort that incorrectly removes duplicates:

```ruby
require "hegel/minitest"
require "minitest/autorun"

class SortTest < Minitest::Test
  include Hegel::Minitest

  INTEGERS = Hegel.integers(min_value: -10, max_value: 10)
  ARRAYS = Hegel.arrays(INTEGERS, min_size: 0, max_size: 20)

  def test_sort_preserves_values
    hegel(test_cases: 100, seed: 1234) do |test_case|
      values = test_case.draw(ARRAYS)

      assert_equal values.sort, broken_sort(values)
    end
  end

  private
    def broken_sort(values)
      values.sort.uniq
    end
end
```

Run the checked-in example:

```sh
./script/test examples/minitest/broken_sort_test.rb
```

The test fails, and Hegel reports the minimal example showing that the sort drops duplicates:

```text
Hegel shrank a failing example:
  Drawn values: [[0, 0]]
  Origin: Minitest::Assertion at examples/minitest/broken_sort_test.rb:16
  Reproduction blob: AXicY2VgYGBkZOBiZEBhMAAAAd8AIQ==
  Engine: libhegel 0.44.0

Expected: [0, 0]
  Actual: [0]
```

Ruby executes the property and assertions on every candidate. `libhegel` chooses the array and integer values and shrinks the failure; there is no Ruby shrinker. Replacing `values.sort.uniq` with `values.sort` makes the property pass:

```sh
./script/test examples/minitest/fixed_sort_test.rb
```

## A realistic interval example

The interval example models a scheduling system that consolidates overlapping busy periods. It checks that merging preserves occupied time, produces ordered non-overlapping periods, and is idempotent.

Run the deliberately broken implementation:

```sh
./script/test examples/minitest/broken_interval_merger_test.rb
```

Hegel discovers that a nested interval can incorrectly shorten a period already collected, then shrinks the input to:

```text
Drawn values: [[0, 1, 0, 0]]
Expected merging [[0, 2], [0, 1]] to preserve occupied time.
Expected: [0, 1]
  Actual: [0]
```

Run the corrected implementation:

```sh
./script/test examples/minitest/interval_merger_test.rb
```

Read [`examples/minitest/broken_interval_merger_test.rb`](examples/minitest/broken_interval_merger_test.rb) for the property, then compare [`examples/broken_interval_merger.rb`](examples/broken_interval_merger.rb) with [`examples/interval_merger.rb`](examples/interval_merger.rb) to see the one-line correction.

## Core API

Without Minitest, `Hegel.test` treats ordinary `StandardError` exceptions as property failures:

```ruby
numbers = Hegel.integers(min_value: 0, max_value: 100)

Hegel.test(test_cases: 100, seed: 1234) do |test_case|
  number = test_case.draw(numbers)
  raise "too large" unless number < 5
end
```

`test_cases:` defaults to `100` for both `Hegel.test` and Minitest's `hegel` helper. Omitting `seed:` leaves it unset so the engine's active profile chooses the seed: development runs use fresh randomness, while profiles such as `ci` may derandomize. The examples set a seed to keep their output reproducible. Integer bounds may be omitted, and `Hegel.arrays(elements)` defaults to `min_size: 0` with no maximum size. The optional `on_failure:` callback receives the final `Hegel::FailureReport`, including its drawn values, origin, engine version, and reproduction blob.

A final failure is reproduced before it is reported and re-raised. To run a reported failure directly, pass its opaque blob as `reproduce_failure:`:

```ruby
Hegel.test(reproduce_failure: blob) do |test_case|
  number = test_case.draw(numbers)
  raise "too large" unless number < 5
end
```

Reproduction blobs are tied to the `libhegel` version that created them. `Interrupt`, `SystemExit`, native errors, reproduction mismatches, and unconfigured `Exception` subclasses are never mistaken for property failures.

## Development

Run the core test suite:

```sh
./script/test
```

Run one test file, optionally with Minitest arguments:

```sh
./script/test test/runner_test.rb
./script/test test/runner_test.rb --seed 1234
```

Run the same checks as GitHub Actions:

```sh
./script/ci
```

GitHub Actions starts a fresh Ubuntu runner on every push and pull request. It installs Ruby and the locked bundle, downloads and verifies `libhegel`, runs the core suite and passing examples, and confirms that the deliberately broken interval example fails through Hegel shrinking rather than a setup error.

## Code tour

Read these files in order:

1. [`examples/minitest/broken_sort_test.rb`](examples/minitest/broken_sort_test.rb) — the developer-facing API.
2. [`lib/hegel/minitest.rb`](lib/hegel/minitest.rb) — the thin Minitest adapter.
3. [`lib/hegel/runner.rb`](lib/hegel/runner.rb) — run lifecycle, failure classification, and verified replay.
4. [`lib/hegel/test_case.rb`](lib/hegel/test_case.rb) and [`lib/hegel/generators.rb`](lib/hegel/generators.rb) — explicit draws and structured integer-array generation.
5. [`lib/hegel/native/resources.rb`](lib/hegel/native/resources.rb) and [`lib/hegel/native/call.rb`](lib/hegel/native/call.rb) — ownership, cleanup, and centralized native result handling.
6. [`lib/hegel/native.rb`](lib/hegel/native.rb) — the pinned C ABI surface.
7. [`test/`](test) — lifecycle, replay, generator, and Minitest integration behavior.

For the feasibility evidence behind this implementation, see [`docs/ruby-spike-findings.md`](docs/ruby-spike-findings.md). Architectural background is in [`docs/hegel-research.md`](docs/hegel-research.md). The [`upstream compatibility policy`](docs/upstream-compatibility.md) defines how public API, behavior, native ABI, and platform decisions are checked against Hegel. The superseded throwaway code and execution plan remain available in Git history.

## Current scope

This project does not yet promise native-library packaging, platforms beyond Linux x86-64, more generator types, assumptions, example-database persistence, callbacks, concurrency, framework integrations beyond Minitest, or a stable public API. It is an experiment intended to establish what a useful Ruby frontend for Hegel could look like—not an official or production-ready Hegel distribution.
