# Upstream compatibility policy

This project is an independent Ruby frontend for Hegel. It aims to make the
features it implements behave like the official Hegel frontends, but it is not
an official frontend and does not yet implement their full public surface.
Compatibility here means a compatible implemented subset, not feature parity.

Hegel is currently beta. Its [compatibility policy](https://hegel.dev/compatibility)
allows breaking changes in minor `0.N.0` releases and reserves patch releases
for non-breaking changes. This repository therefore pins an exact `libhegel`
release and reviews compatibility deliberately rather than following the latest
release automatically.

## Sources of truth

Use these sources in order when making a decision:

1. **The pinned `vendor/libhegel-v0.44.0/hegel.h`** defines the native ABI,
   including signatures, result codes, ownership, lifetimes, and run lifecycle.
   Website prose and other frontends must not override the pinned header.
2. **The matching `hegel-rust` release** defines engine and generator
   semantics. For the current pin, this is `libhegel-v0.44.0` at commit
   `09c6c0b9aa82f20b4f522ef45b646948f2e793bc`.
3. **Official Hegel frontends** establish the shared public interface. Compare
   Rust first, then Go and TypeScript, for names, arguments, defaults,
   validation, and observable behavior. Do not infer a convention from only
   one frontend when the others are available.
4. **Ruby conventions** decide presentation only where upstream has no shared
   answer or Ruby requires a different mechanism. Ruby syntax may be
   idiomatic, but it must preserve upstream meaning.

Third-party frontends can provide useful implementation ideas, but they are not
a compatibility authority.

## Compatibility rules

For every feature exposed publicly by this repository:

- Use upstream names, option names, defaults, and semantics unless a documented
  Ruby-specific reason prevents it.
- Validate at the same conceptual stage as upstream and preserve meaningful
  error distinctions.
- Keep engine control flow, property failures, fatal exceptions, and binding
  failures distinct.
- Let `libhegel` own generation, exploration, shrinking, and reproduction data;
  do not add a competing Ruby shrinker.
- Treat reproduction blobs as opaque and scoped to the `libhegel` version that
  produced them.
- Keep binding adapters, exception-classification hooks, and test seams out of
  the public API.
- Prefer an explicitly missing feature over an incompatible approximation.

A deliberate divergence requires all of the following:

1. a concrete Ruby or platform constraint;
2. a note in the compatibility matrix below;
3. tests that pin the divergent behavior; and
4. user-facing documentation when callers can observe it.

## Current public API alignment

The project is unpublished, so the existing experimental surface can still be
corrected without a compatibility alias. The following changes are the current
alignment plan:

| Concern | Current surface | Upstream-compatible target | Status |
| --- | --- | --- | --- |
| Property entry point | `Hegel.check` | `Hegel.test` | Planned |
| Case budget | `max_examples:` | `test_cases:` | Planned |
| Integer bounds | `integers(min:, max:)` | `integers(min_value: nil, max_value: nil)` | Planned |
| Array bounds | Both bounds required | `arrays(elements, min_size: 0, max_size: nil)` | Planned |
| Reproduction | `Hegel.replay(blob:, expected_origin:)` | `Hegel.test(reproduce_failure: blob)` | Planned |
| Default seed | Core unset; Minitest uses `0` | Unset and nondeterministic | Planned |
| Adapter controls | Public keywords on `Hegel.check` | Internal runner/adapter seams | Planned |
| Assumptions and observations | Not implemented | Reserve `assume`, `reject`, `note`, `target`, `event`, and `event_value` | Reserved |

Until these planned changes land, the README documents the API that actually
runs. Contract tests for the target behavior should be added before changing
that implementation and its examples.

Missing generators and settings are omissions, not divergences. Add them only
when their upstream behavior and the relevant native lifecycle are understood
and tested.

## Required review for changes

Before changing public methods, generator semantics, settings, native calls,
or platform support:

1. Read this document and the pinned `hegel.h` sections involved.
2. Identify the matching `hegel-rust` behavior.
3. Compare the public shape in the official Go and TypeScript frontends.
4. Record the exact upstream tags or commits reviewed.
5. Add or update contract tests for names, defaults, validation, and behavior.
6. Add native lifecycle and error-path tests when the C boundary changes.
7. Update this matrix, the README, and migration notes as applicable.

Review the policy again whenever:

- the pinned `libhegel` version changes;
- upstream publishes a potentially breaking minor release;
- an official frontend changes a shared name, default, or semantic rule; or
- this project adds a platform or starts distributing native binaries.

Do not make CI depend on the moving heads of upstream repositories. Pin review
references and update them intentionally. CI should instead exercise the
checked-in contract against the pinned engine and header.

## Compatibility dimensions

### Native ABI

The binding must match the pinned header exactly, load only its expected engine
version, and test ownership and cleanup on success, failure, overrun, replay,
and escaping exceptions. An engine upgrade is an ABI review even when the
binding still loads.

### Ruby public API

Contract tests should pin public method names, keyword names, defaults, return
behavior, validation timing, and exception behavior. Framework adapters may add
Ruby-specific ergonomics, but must delegate to the same core semantics.

### Platforms and packaging

The upstream compatibility page lists where prebuilt `libhegel` artifacts are
available and which official frontends support each platform. Artifact
availability does not imply support by this repository. The README is the
authority for this project's narrower support policy until CI and packaging
prove additional platforms.

### Version and reproduction compatibility

The native engine and header must be upgraded together. Because upstream beta
minor releases may break compatibility, each such upgrade requires a new audit
of the binding, public defaults, and replay behavior. Reproduction blobs must
never be promised to work across engine versions.

## Last reviewed upstream references

The initial public API review used:

- `hegel-rust` `libhegel-v0.44.0`, commit
  `09c6c0b9aa82f20b4f522ef45b646948f2e793bc`;
- `hegel-go` commit `5de2df7c28606290b1971573ddee2ca7359fcb62`;
- `hegel-typescript` `v0.4.7`, commit
  `f9f7950fa101091cba591aea2880b3ab7843f4c9`; and
- the upstream [compatibility policy](https://hegel.dev/compatibility).

Update this list as part of each compatibility audit.
