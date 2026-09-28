# First spike: see Hegel working from Ruby

## Goal

Make Hegel tangible: run a Ruby property, watch it find a bug, inspect the shrunk input, replay the failure, then fix the bug and see the property pass.

Keep the spike bounded by the two demonstration checkpoints below and a short findings document. This is a throwaway feasibility spike, not the start of a production-ready gem. If blocked, stop with a small reproducer and explain what we learned rather than expanding scope.

Based on [the research](hegel-research.md). Verify release details and ABI behavior against the selected release before implementation.

## Fixed choices for this experiment

- One CRuby version on the development machine's Linux architecture.
- The `ffi` gem and only the native functions needed by the demos.
- One pinned `libhegel` release with its matching `hegel.h`.
- Synchronous, single-threaded execution; no nested checks.
- Bounded integers and arrays of integers, with explicit `tc.draw` calls.
- Example database disabled; reproduction uses saved blobs.
- All experimental code under `spike/`; no promised public API.

Do not compare FFI implementations or design packaging in this spike.

## Checkpoint 1: Ruby can drive Hegel

**Outcome: a runnable integer-shrinking demo.**

### Reproducible setup

- Add a minimal Gemfile and lockfile for the spike.
- Provide one explicit setup command, backed by a small `spike/script/fetch-libhegel` script, to download the pinned shared library and matching header and verify their upstream checksums. No automatic downloads while running properties.
- Record the release, artifact URLs/checksums, Ruby/FFI versions, and platform. Allow `HEGEL_LIBRARY_PATH` to override the library location.
- Read the selected release's `hegel-c/examples/failing.c` and the header declarations it uses. If the example has moved, find its equivalent at that revision.

### First demonstration

Port the upstream C example to a small Ruby script before building a generator API. Bind only what it needs, preserving the run lifecycle:

**start → request case → draw integer → execute check → complete case → repeat through shrinking → inspect result.**

Print the shrunk failing integer and reproduction blob. Use the upstream example's expected result for the pinned version rather than assuming a particular number in advance.

**Pause here and show the result:** the Ruby script, its output, and a brief explanation of which work Ruby performs and which work Hegel performs. This is already a useful result even if the second checkpoint hits a blocker.

## Checkpoint 2: property testing feels natural in Ruby

**Outcome: the broken-sort demonstration, verified replay, and a passing corrected property.**

Extract only enough of the first script to support a small runner and integer/array generators. Consult the pinned header and a compatible reference frontend, starting with Go, specifically for collection/span handling, ownership, and final replay. Record the reference revision.

Illustrative API, not a design commitment:

```ruby
integers = Hegel.integers(min: -10, max: 10)
arrays = Hegel.arrays(integers, min_size: 0, max_size: 20)

Hegel.check(max_examples: 100, seed: 1234) do |tc|
  values = tc.draw(arrays)
  actual = values.sort.uniq # Deliberate bug: removes duplicates.
  raise "sort lost values" unless actual == values.sort
end
```

Arrays must use Hegel's collection helpers and appropriate spans so the engine sees their structure. Do not write a Ruby shrinker.

### Show the complete story

1. Run the broken sort and print its final shrunk array. `[0, 0]` would be illustrative, but the requirement is a small duplicate-containing array that still fails.
2. Replay the final blob through the same draw/property path. Verify that it fails with the same origin, then report the final values and re-raise the replayed Ruby exception with its original message and backtrace.
3. Save the blob and demonstrate replay in a fresh process with the same engine and property.
4. Replace `values.sort.uniq` with `values.sort` and show a normal passing run.

Keep values, engine version, and blob in diagnostic output rather than modifying the exception's message. A polished multi-failure report is not required for these single-bug demos.

## Essential correctness, not a hardening project

Keep these rules even in throwaway code:

- Check native result codes centrally. Engine/binding errors are not property failures; stop-test is internal overrun control flow.
- Ordinary user failures become interesting cases. Do not sweep every Ruby `Exception` into that category: `Interrupt` and `SystemExit` must propagate after cleanup. Framework-specific assertion handling is deferred with framework integration.
- Use exception class plus a relevant user source location as the failure origin, not a changing message.
- Complete each case exactly once where required by the pinned contract. Verify abandonment behavior for interrupted/error paths; do not invent a completion status in `ensure`.
- Free owned handles explicitly on success and failure, and copy borrowed data before its owner is freed. Close spans and collections according to the native contract, including aborted draws.
- A replay that passes, changes origin, rejects, or overruns is a reproduction mismatch—not a confirmed failure. Report what happened without guessing that the blob is stale.

Add a few focused automated checks alongside the demos: normal completion, user failure/replay, native-error versus stop-test classification, and cleanup on a raised exception. Injected boundary results can check Ruby branching but do not prove native behavior. Record unverified paths instead of building an exhaustive test matrix.

## Explicitly deferred

Booleans, floats, strings, arbitrary-size integers, `map`/`filter`, a public assumption API, callbacks, framework helpers/adapters, database persistence, recursive/stateful testing, concurrency, packaging, alternative bindings, serious benchmarking, and comprehensive GC/leak/sanitizer testing.

These are not optional extras to squeeze into the spike. Stop after the demonstration and assessment.

## Deliverables and assessment

Deliver runnable scripts, reproducible setup instructions, and `docs/ruby-spike-findings.md` with:

- Exact commands and captured results for integer shrinking, broken sort, fresh-process replay, and corrected sort.
- A brief explanation of generation, shrinking, and replay in terms of what the user just saw.
- What worked, what was awkward, blockers, and unverified safety paths.
- Whether FFI was sufficient for this demonstration and what the explicit-draw API felt like.
- One recommended next step: build a minimal frontend, investigate one specific blocker, or pause.

Success means we have **experienced Hegel working from Ruby** and can make a better-informed next decision. It does not establish production memory safety, acceptable performance for all workloads, portability, or a finished Ruby API.
