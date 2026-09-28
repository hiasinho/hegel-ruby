# Hegel research for Ruby

This report records the research behind a possible Hegel frontend for Ruby. It separates statements made by Hegel's maintainers (**documented fact**) from implications drawn for this repository (**conclusion**). The canonical C header and upstream release artifacts should be rechecked before implementation because Hegel is evolving quickly.

## Executive summary

**Documented fact:** Hegel is a universal property-based testing engine and family of language libraries, built from ideas and implementation experience in [Hypothesis](https://hypothesis.works/). Its current reusable engine, `libhegel`, is written in Rust and exposed in-process through a C ABI. Language-specific libraries supply the user-facing testing API.

**Conclusion:** Hegel is not a compiler, a programming language implementation, a Ruby parser, or an AST/IR transformation system. A Hegel-for-Ruby project would be a Ruby property-testing frontend and native binding. Ruby would execute the property body normally while the frontend asks `libhegel` for values and reports outcomes.

## Property-based testing in concrete terms

Example-based tests choose a few inputs and expected outputs by hand. A property-based test instead states an invariant and asks the testing system to try many generated examples. Useful properties include “encoding then decoding preserves the value,” “a result is always sorted,” and “our implementation agrees with a trusted reference implementation.”

Consider a deliberately broken sort:

```ruby
def my_sort(values)
  values.sort.uniq # Incorrectly removes duplicates.
end
```

A property can compare `my_sort(values)` with Ruby's ordinary `values.sort`. Hegel may explore many lists before finding a mismatch. It then **shrinks** the failing input: it probes simpler related inputs while preserving the failure. A large noisy list can therefore become the minimal counterexample `[0, 0]`, for which the reference result is `[0, 0]` but the deduplicating implementation returns `[0]`. Shrinking makes the cause much easier to see; with Hegel's internal shrinking model, frontend authors compose draws rather than writing a bespoke shrinker for every Ruby generator.

Three related persistence/reproduction concepts are worth distinguishing:

- **Replay** executes a previously recorded choice sequence again, recreating the values that drove a test case. Hegel exposes a base64 reproduction blob for this purpose. Such a blob is guaranteed only for the Hegel version that produced it.
- The **example database** persists useful examples, especially failures, under a key for the property. A later normal run can try those examples early and fail quickly before doing fresh exploration. It is a cache of valuable cases, not the user's application database.
- **Final failure replay** is part of reporting: after exploration and shrinking, the frontend reruns the minimal case so it can capture host-language values and re-raise or format the actual host-language failure.

## Motivation and relationship to Hypothesis

**Documented fact:** Hegel's stated goal is to bring Hypothesis-quality property-based testing to many languages without independently rebuilding the expensive engine work in every ecosystem. The maintainers emphasize Hypothesis's generator library, internal shrinking, and example database. A shared engine lets each language reuse generation, shrinking, scheduling, health checks, and persistence while retaining an idiomatic API.

Hegel is maintained primarily by Hypothesis developers through their work at [Antithesis](https://antithesis.com/). It is intended to stand on its own as a family of property-based testing libraries, while also gaining Antithesis-specific capabilities. The name is a philosophy joke: Hypothesis developers working at **Antithesis** named the project **Hegel**.

## Current architecture

**Documented fact:** Every current Hegel language library runs `libhegel` in-process. `libhegel` lives in the [`hegel-rust`](https://github.com/hegeldev/hegel-rust) repository (under `hegel-c`), is implemented in Rust, and is distributed as a native shared library with a C ABI.

The split is approximately:

| `libhegel` owns | A language frontend owns |
| --- | --- |
| Choice generation and typed primitive draws | Idiomatic property, generator, and settings APIs |
| Deciding which test case to run next | Invoking the user's property in the host runtime |
| Shrinking and exploration phases | Converting native results to host-language values |
| Example-database storage and reuse | Assumptions, control-flow sentinels, and exception classification |
| Run budgets, health checks, targeting logic | Stable failure-origin extraction and user-facing diagnostics |
| Minimal choice sequences and reproduction blobs | Test-framework integration and native-library packaging/loading |

The frontend is “thin” relative to the engine, but it is not merely a generated FFI declaration. Compound generators must preserve structure for shrinking, and host-language failures and resources must be handled according to that language's conventions.

### The old architecture is obsolete

**Documented fact:** The archived [`hegel-core`](https://github.com/hegeldev/hegel-core) repository describes the earlier Python implementation and a subprocess protocol using CBOR over process I/O/transport. It has been superseded by the Rust `libhegel` C ABI.

**Conclusion:** A new frontend should not implement that archived protocol. The current Hegel system is not a daemon or network service: it loads a native engine into the test process and calls it directly.

## Exact run lifecycle

The current C API uses the following lifecycle:

1. **Build settings.** Create a settings handle and configure the test-case budget, phases, seed or derandomization, database and database key, health-check suppression, verbosity, backend, and related options. The engine copies settings when a run starts, so the settings handle can then be reused or freed.
2. **Start the run.** `hegel_run_start` creates a run handle and optionally accepts an output callback plus user data. Starting only sets up the run; it does not generate a case yet.
3. **Request a case.** Call `hegel_next_test_case`. This resumes the engine's suspended run loop on the calling thread and returns an owned test-case handle. It returns a null test case when the run has finished. The previous case must have been completed before requesting another.
4. **Execute the property in the frontend.** The frontend calls the Ruby property body. Each draw calls an appropriate typed C primitive—integers, booleans, floats, bytes, strings, collection decisions, and so on—and converts the result into a Ruby value.
5. **Classify and complete the case.** Call `hegel_mark_complete` with:
   - `VALID` when the body finishes normally;
   - `INVALID` when an assumption rejects the example;
   - `INTERESTING` when the property fails, together with a stable origin string; or
   - `OVERRUN` when generation exhausts the case's choice budget (a draw reports stop-test).
6. **Continue exploration and shrinking.** Repeat the next-case/body/completion loop. Cases issued after a failure include the engine's shrinking probes. Rejected and overrun probes inform the search but are not successful valid examples. The frontend still runs every property invocation; `libhegel` decides the choice sequence and what to try next.
7. **Read the result.** Once `hegel_next_test_case` returns null, obtain an owned run-result object. It records pass/fail status and distinct failures. Failures expose their origin, caveat information where applicable, and a minimal reproduction blob.
8. **Replay each final failure.** Create a test case directly from its reproduction blob—there is no run handle or run loop for this step—drive it through the same draw/property machinery, mark it complete, and verify that the failure actually reproduces. This replay supplies the final Ruby-level values and exception/report. A pass or mismatch indicates a stale or flaky reproduction; a changed generator can instead overrun.
9. **Free resources.** Release test cases, failures, results, the run, settings, contexts, generator helpers, and other owned handles with their matching destructor, including exceptional paths.

A failure **origin** must be stable, for example the location of the user's failing assertion rather than an unstable object id or full changing message. `libhegel` treats equal origins as the same bug and shrinks them together; different origins represent distinct bugs.

## C ABI concepts a frontend must understand

The [canonical `hegel.h`](https://github.com/hegeldev/hegel-rust/blob/main/hegel-c/include/hegel.h) is the binding contract.

- **Opaque handles:** contexts, settings, runs, test cases, run results, failures, string generators, collections, pools, and state machines are represented by opaque native handles rather than exposed Rust layouts.
- **Context/error/result convention:** almost every call takes a context first and returns a `hegel_result_t`; zero is success, negative values are errors, and ordinary return data is written through `out_*` parameters. A context retains the latest diagnostic string. A null context opts out of diagnostics but not error codes.
- **Explicit ownership:** constructors and returned owned handles have matching `*_free` functions. Other returned strings are borrowed for a documented lifetime. Input buffers remain caller-owned and are copied if the engine must retain them.
- **Generation primitives:** the ABI exposes typed choices such as booleans, bounded and big integers, floating-point values, bytes, strings, and sampler/selection operations. A stop-test result is control flow for overrun, not an ordinary Ruby exception to expose unchanged.
- **Spans:** labeled, nested spans group multiple draws into one logical structure so the shrinker can understand compound generators. A discarded span supports retrying constructs such as filters. Every opened span must be closed correctly.
- **Collections and recursion:** collection handles coordinate length and element generation; recursive-generation operations bound and regenerate recursive shapes. These facilities let a frontend describe structure instead of reducing everything to unrelated primitive draws.
- **Pools and state machines:** variable pools select previously created values and can consume them; state-machine handles support rule-based/stateful testing. The host frontend retains mappings from engine ids to actual host objects.
- **Targeting and events:** target scores guide search toward extreme values, while events/observations feed statistics and reports.
- **Callbacks:** run and blob-replay output may be redirected through a callback. It runs synchronously on the thread driving the engine and must not re-enter the same run.
- **Threading constraints:** a context is not concurrently shareable; configured settings can be shared but not mutated concurrently; a run is single-driver; and one test-case handle can be driven by only one thread at a time. Cloned test-case handles provide independent choice streams for multiple threads, but shared collection/state objects have their own stricter contracts.

**Documented fact:** the website's libhegel reference explicitly says that the header is canonical and asks readers to report stale reference text.

**Conclusion:** generated/manual Ruby bindings should be pinned to a specific `hegel-rust` release and checked against that release's header. Website prose is useful explanation, but it may lag the ABI.

## Repository map

The [Hegel GitHub organization](https://github.com/hegeldev) currently contains:

- [`hegel-rust`](https://github.com/hegeldev/hegel-rust): Rust frontend plus the Rust engine and `hegel-c` C ABI.
- [`hegel-go`](https://github.com/hegeldev/hegel-go): Go frontend.
- [`hegel-typescript`](https://github.com/hegeldev/hegel-typescript): TypeScript/JavaScript frontend, including native and browser/Wasm paths.
- [`hegel-cpp`](https://github.com/hegeldev/hegel-cpp): C++ frontend.
- [`hegel-java`](https://github.com/hegeldev/hegel-java): Java frontend.
- [`hegel-ocaml`](https://github.com/hegeldev/hegel-ocaml): OCaml frontend.
- [`website`](https://github.com/hegeldev/website): `hegel.dev` documentation source.
- [`hegel-zoo`](https://github.com/hegeldev/hegel-zoo): Hegel property tests against open-source projects across supported languages.
- [`hegel-skill`](https://github.com/hegeldev/hegel-skill): an agent skill for writing Hegel tests.
- [`pbt-book`](https://github.com/hegeldev/pbt-book): property-based-testing book material.
- [`experimental`](https://github.com/hegeldev/experimental): explicitly non-production experiments.
- [`hegel-core`](https://github.com/hegeldev/hegel-core): archived Python core and subprocess/CBOR protocol; historical, not the current binding target.

No Ruby frontend repository is currently listed by the organization. That is an observed repository fact, not proof that no private or third-party experiment exists.

## What a language frontend contains beyond FFI

A useful frontend must provide all of the following layers:

- idiomatic generators and combinators (`map`, `flat_map`, filters, tuples, arrays, recursive data, and stateful rules), with spans/collections that preserve shrink structure;
- conversion between native primitive buffers/ids and ordinary language values;
- assumptions and internal abort control flow that cannot be mistaken for user failures;
- classification of assertions, exceptions, invalid cases, overruns, engine errors, and flaky final replays;
- extraction of stable origins from host-language stack traces or test metadata;
- a runner that guarantees completion and native cleanup even when callbacks or properties raise;
- reproduction-blob replay, example display, diagnostics, and failure reporting;
- integration with the ecosystem's test frameworks and source-location conventions; and
- packaging, selecting, loading, and validating the correct native artifact for the runtime platform.

These responsibilities explain why reading mature frontends is as important as translating `hegel.h`.

## Packaging and platform support

**Documented fact:** upstream publishes `libhegel` artifacts for:

- Linux amd64 and arm64;
- macOS arm64 (Apple Silicon); and
- Windows amd64 and arm64.

Intel macOS does not have a published artifact; users needing it must build `libhegel` from source and point the frontend at that build. Availability of an engine artifact does not imply that every existing language frontend supports every listed platform.

The TypeScript frontend also has a browser path using a Rust WebAssembly engine. Its documented browser constraints include ESM/top-level await, secure-context Web Crypto, main-thread testing/shrinking, and no browser persistence. This demonstrates another engine build target, but does not make Wasm the default or obvious target for Ruby.

## Maturity and stability

**Documented fact:** Hegel's core repositories are MIT-licensed. The project describes itself as **beta** and, in explanatory material, roughly a **developer preview**. Maintainers reserve the right to make breaking API and ABI changes before a stable release and acknowledge rough edges in integration, even while describing the inherited core logic as mature. Compatibility and migration information is published centrally.

**Observation:** the organization and language repositories show active, rapid development and frequent releases. This report intentionally does not quote a “current” version because it would become stale quickly.

**Conclusion:** a Ruby package must pin a matching header and native release rather than bind an unbounded “latest” ABI. Artifact checksums, ABI/version validation, release synchronization, and explicit compatibility tests would be part of responsible packaging.

## Implications for Ruby

At a high level, a Hegel-for-Ruby project would need two connected pieces: bindings to the current C ABI and an idiomatic Ruby property-testing frontend. Ruby—not `libhegel`—would invoke blocks, construct Ruby objects, run assertions, catch exceptions, inspect backtraces, and integrate with Ruby test frameworks. `libhegel` would control generated choices, exploration, shrinking, persistence, and replay.

The target is therefore the in-process C ABI, not Ruby source syntax, an AST or intermediate representation, and not the archived subprocess/CBOR protocol. This is an architectural conclusion, not an implementation plan; FFI library selection, public API design, supported Ruby engines, framework integrations, and gem artifact strategy remain future design work.

## Name collision

This Hegel should not be confused with [JSMonk/hegel](https://github.com/JSMonk/hegel), an unrelated static type checker for JavaScript. Documentation, package metadata, and search terms should qualify this project as the Hegel property-based testing system or Hegel for Ruby.

## Sources

### Project documentation

- [Hegel home](https://hegel.dev/)
- [Getting started](https://hegel.dev/intro/getting-started)
- [How Hegel works](https://hegel.dev/explanation/how-hegel-works)
- [Why Hegel?](https://hegel.dev/explanation/why-hegel)
- [Compatibility and platform support](https://hegel.dev/compatibility)
- [libhegel reference](https://hegel.dev/reference/libhegel)
- [Canonical `hegel.h`](https://github.com/hegeldev/hegel-rust/blob/main/hegel-c/include/hegel.h)
- [Hegel GitHub organization](https://github.com/hegeldev)

### Core language repositories

- [hegel-rust (including `hegel-c`/`libhegel`)](https://github.com/hegeldev/hegel-rust)
- [hegel-go](https://github.com/hegeldev/hegel-go)
- [hegel-typescript](https://github.com/hegeldev/hegel-typescript)
- [hegel-cpp](https://github.com/hegeldev/hegel-cpp)
- [hegel-java](https://github.com/hegeldev/hegel-java)
- [hegel-ocaml](https://github.com/hegeldev/hegel-ocaml)

### Supporting and historical repositories

- [Website/documentation source](https://github.com/hegeldev/website)
- [Hegel Zoo](https://github.com/hegeldev/hegel-zoo)
- [Hegel agent skill](https://github.com/hegeldev/hegel-skill)
- [Property-based testing book](https://github.com/hegeldev/pbt-book)
- [Experimental projects](https://github.com/hegeldev/experimental)
- [Archived hegel-core](https://github.com/hegeldev/hegel-core)
