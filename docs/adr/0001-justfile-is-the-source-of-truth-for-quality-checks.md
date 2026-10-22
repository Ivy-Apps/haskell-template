# 1. The Justfile is the source of truth for quality checks

Date: 2026-10-22

## Status

Accepted

## Context

CI has to run the same checks a developer runs locally, but as separate steps,
so a spelling or lint error fails in seconds instead of after a full build.

There are already two ways to run a check. The flake exposes
`apps.{build,test,lint}` (thin wrappers documented in `CLAUDE.md` and used by
AI agents), and the `Justfile` exposes `just check`. Before this decision CI
used neither consistently: it called `nix build`, `nix fmt` and a `cabal`
one-liner directly, and `just check` was a single opaque recipe, so the two
could drift without anyone noticing.

## Decision

The `Justfile` holds the check definitions. Each check is its own recipe
(`typos`, `fmt-check`, `check-nix`, `lint`, `lint-actions`, `build`, `build-nix`,
`build-bench`, `test`) and `check` is their sequence, cheapest first.

Every CI step is `nix develop .#ci --accept-flake-config -c just <recipe>`,
spelled out in full, one recipe per step, in the same order as `check`.

The flake's apps remain the documented agent-facing entry points. They are
convenience wrappers, not the definition of a check.

## Rejected: entering the dev shell once

Repeating `nix develop` per step costs a few seconds of re-evaluation each.
Two ways to avoid it were considered and dropped:

- **`defaults.run.shell`** at the job level. Removes the repetition but still
  runs `nix develop` per step, so it saves nothing.
- **`nix print-dev-env .#ci > "$BASH_ENV"`** in a setup step. Works, and is
  much faster per step, but it is an unusual pattern that needs a footnote to
  read, and `print-dev-env` output has a history of shell-compatibility bugs
  (NixOS/nix#10263, #8309).

If the per-step cost ever becomes material, the maintained
`nicknovitski/nix-develop` action does the same job through `$GITHUB_ENV` and
`$GITHUB_PATH`.

## Consequences

- `just check` locally and the CI workflow cannot drift: editing a recipe
  changes both.
- Steps fail in cost order: spelling, formatting and lints, then compilation,
  then tests.
- Anyone adding a new check adds a recipe, adds it to `check`, and adds a CI
  step for it. They wire a flake app only if agents need it.
- Two entry points for the same work still exist (`nix run .#test` vs
  `just test`). This ADR fixes which one is authoritative.
- The one deliberate exception is the benchmark, which CI compiles but never
  runs. See ADR 4.
