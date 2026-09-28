# Repository guidance

## Project

This repository is exploring a Ruby frontend for the Hegel property-based testing engine.

- Read `docs/hegel-research.md` for the architecture and upstream context.
- Treat `docs/ruby-spike-plan.md` as the authoritative implementation plan for the first spike.
- Keep spike code isolated under `spike/`.
- Keep the spike narrow: implement the stated checkpoints before expanding its API or platform support.
- Verify native ABI details against the pinned `hegel.h`; do not infer them from prose documentation.

## Commits

Use Conventional Commits for all commit messages: `type(scope): imperative summary`.
