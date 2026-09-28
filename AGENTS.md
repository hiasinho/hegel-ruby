# Repository guidance

## Project

This repository implements an early Ruby frontend for the Hegel property-based testing engine.

- Read `docs/hegel-research.md` for the architecture and upstream context.
- Read `docs/ruby-spike-findings.md` for the feasibility evidence behind the current implementation.
- Before changing the public API, generator semantics, settings, native bindings, or platform support, read `docs/upstream-compatibility.md`. Verify changes against its source hierarchy, update compatibility contract tests, and document intentional divergences.
- Keep changes within the current boundaries documented in `README.md` unless deliberately expanding them.
- Verify native ABI details against the pinned `hegel.h`; do not infer them from prose documentation.

## Commits

Use Conventional Commits for all commit messages: `type(scope): imperative summary`.
