# Ruby spike findings

Both planned checkpoints were completed: Ruby drove the integer example, then a small explicit-draw frontend generated and shrank integer arrays, replayed the final failure, and passed after the property was corrected. The superseded throwaway implementation has since been removed; it remains available in Git history. This document preserves the evidence that informed the current frontend.

## Pinned environment

The spike was run on:

- Linux x86_64
- CRuby 3.4.10
- Bundler 4.0.20
- `ffi` 1.17.4
- Minitest 5.27.0
- `libhegel` 0.44.0, upstream tag `libhegel-v0.44.0` (`09c6c0b9aa82f20b4f522ef45b646948f2e793bc`)

The binding was checked against the release's `hegel.h` and its `hegel-c/examples/failing.c`. The release assets are:

| Asset | URL | SHA-256 |
| --- | --- | --- |
| `hegel.h` | `https://github.com/hegeldev/hegel-rust/releases/download/libhegel-v0.44.0/hegel.h` | `a324eca375a51f0b46b41db6017c6d4f000324c3a6d3ee2563a17a11df4a6944` |
| `libhegel-linux-amd64.so` | `https://github.com/hegeldev/hegel-rust/releases/download/libhegel-v0.44.0/libhegel-linux-amd64.so` | `c2baf69815c3cb7ebbcc690f6d721e21056ce278651d26e9e8c5ba795e2ce48c` |

Those values match the `.sha256` sidecars and digests published on the upstream release. The spike's `script/fetch-libhegel` embedded them, downloaded into its ignored `vendor/libhegel-v0.44.0/` directory, and refused non-Linux or non-amd64 hosts. Runtime code did not download native files. `HEGEL_LIBRARY_PATH` could select another copy of the shared library, whose reported version still had to be 0.44.0.

## Reference frontend

Collection, span, ownership, and final replay patterns were compared with `hegeldev/hegel-go` v0.9.9 at commit `0531b49eda0ae4b8fea0071ce5b74c0776ae340a`, particularly `collections.go`, `generators.go`, `runner.go`, and `internal/libhegel/libhegel.go`. That frontend pins libhegel 0.43.6; no Go revision pinned 0.44.0 when this spike was made. It was therefore used as a protocol-shape reference only, and every function and lifecycle rule used by Ruby was verified separately against the pinned 0.44.0 header.

## Setup

From the repository root:

```sh
cd spike
gem install --user-install bundler -v 4.0.20
BUNDLE="$(ruby -e 'print Gem.user_dir')/bin/bundle"
ruby "$BUNDLE" config set --local path vendor/bundle
ruby "$BUNDLE" install
./script/fetch-libhegel
```

The explicit Bundler path avoids a development-machine `mise` shim which does not have a default Ruby selected. On an ordinary Ruby installation, the equivalent `bundle` commands work directly.

## Checkpoint 1: integer shrinking

Command:

```sh
ruby "$BUNDLE" exec ruby failing_integer.rb
```

Captured result:

```text
libhegel version: 0.44.0
shrunk failing integer: 5
failure origin: n >= 5
reproduction blob: AAEAAAAACgEAAAAF
```

The upstream property says that every integer in `[0, 100]` is less than 5. The demo asserts upstream's expected minimal counterexample, 5, and decodes the returned blob through `hegel_test_case_from_blob` to confirm the same draw fails again.

## Checkpoint 2: broken sort

The demonstration generates arrays of bounded integers through Hegel's collection helpers. Every generator draw has a stable span label, arrays nest their element draws inside the array span, and Ruby explicitly closes spans and frees collection handles on normal and aborted draws.

### Find and replay the failure

Command (exit status 1 is expected because the replayed property exception is propagated):

```sh
ruby "$BUNDLE" exec ruby broken_sort.rb broken || test $? -eq 1
```

Captured result:

```text
libhegel version: 0.44.0
final failing array: [0, 0]
failure origin: RuntimeError at spike/broken_sort.rb:22
reproduction blob: AXicY2VgYGBkZOBiZEBhMAAAAd8AIQ==
saved reproduction: /home/hiasinho/Work/hegel-ruby/spike/tmp/broken-sort.blob
replayed exception: RuntimeError: sort lost values
replayed backtrace starts: broken_sort.rb:22:in 'Object#broken_sort_property'
```

The property used `values.sort.uniq`, which drops duplicate values. Hegel found a duplicate-containing array and shrank it to `[0, 0]`. The runner then replayed the final blob through the same draw and property path, verified the origin, reported the final values, and re-raised the replayed `RuntimeError` with its original message and backtrace. The blob and expected origin were saved under ignored `spike/tmp/` files.

### Replay in a fresh process

A separate Ruby process loaded the saved blob:

```sh
ruby "$BUNDLE" exec ruby broken_sort.rb replay || test $? -eq 1
```

Captured result:

```text
libhegel version: 0.44.0
final failing array: [0, 0]
failure origin: RuntimeError at spike/broken_sort.rb:22
reproduction blob: AXicY2VgYGBkZOBiZEBhMAAAAd8AIQ==
replayed exception: RuntimeError: sort lost values
replayed backtrace starts: broken_sort.rb:22:in 'Object#broken_sort_property'
```

The exact blob is version-specific. A replay that passes, overruns, or changes origin raises `Hegel::ReproductionMismatch` rather than being reported as a confirmed failure.

### Correct the property

Command:

```sh
ruby "$BUNDLE" exec ruby broken_sort.rb fixed
```

Captured result:

```text
libhegel version: 0.44.0
corrected sort: passed 100 examples
```

Replacing `values.sort.uniq` with `values.sort` produced a normal passing run.

## Focused checks

Command:

```sh
ruby "$BUNDLE" exec ruby -Ilib:test test/hegel_test.rb --seed 1234
```

Result:

```text
5 runs, 25 assertions, 0 failures, 0 errors, 0 skips
```

The checks cover normal completion, user failure plus replay, native errors versus stop-test control flow, an overrun while nested spans and a collection are open, and cleanup/abandonment when `Interrupt` escapes. The cleanup checks delegate to the real native binding while recording lifecycle calls; they verify nested resources are released and an interrupted case is not assigned an invented completion status.

## What Ruby and Hegel each do

Ruby constructs generators, opens and closes generator spans, drives collection handles and explicit draws, executes the property block, turns ordinary `StandardError` failures into interesting cases, derives a stable origin from exception class and user source location, verifies replay, reports diagnostics, and explicitly releases every owned handle. `Interrupt`, `SystemExit`, and native binding errors are not classified as property failures.

`libhegel` chooses array lengths and integer values, schedules examples, tracks the structured choice sequence, searches and shrinks failures, and serializes the minimal choices into a reproduction blob. Ruby does not contain a shrinker.

## Assessment

FFI was sufficient for both demonstrations. The explicit `tc.draw(generator)` shape felt natural in Ruby and kept property data flow visible. The awkward parts were the C out-pointers, manual ownership, the distinction between stop-test and real errors, and preserving exception semantics while every native case still follows its completion contract.

There were no blockers. This spike does not establish production memory safety, broad leak safety, portability, acceptable performance, nondeterministic replay, callbacks, assumptions, framework assertions, database persistence, concurrency, or packaging. Aborted nested generator paths have focused coverage but not sanitizer or exhaustive fault-injection coverage.

**Recommended next step:** build a minimal frontend from the proven runner/generator shape, first extracting a dedicated ownership layer and adding CI-backed native lifecycle tests before expanding generator types.
