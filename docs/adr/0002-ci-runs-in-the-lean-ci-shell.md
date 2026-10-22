# 2. CI runs in the lean `ci` dev shell

Date: 2026-10-22

## Status

Accepted

## Context

The flake defines two dev shells. `default` is for humans and editors: it
carries `haskell-language-server`, `implicit-hie`, `hspec-golden` and `ghcid`.
`ci` carries only what compiling and testing need.

Running a check in `default` makes the cheapest check pay for the heaviest
closure. Before this decision, `nix run .#lint` entered `default`, so asking
hlint a question realised HLS first, potentially a from-source build on a
cache miss, before hlint could say anything.

## Decision

Every CI step, and every flake app that runs a check (`build`, `test`, `lint`,
`update-golden`), enters the `ci` shell.

The `ci` shell carries exactly the tools the recipes CI calls need: `just`,
`hlint`, `typos`, `statix`, `deadnix`, the treefmt wrapper (fourmolu,
cabal-fmt, nixfmt, typos), `actionlint` with `shellcheck`, and `git`. These are
defined once as `checkTools` in `flake.nix` and added to both shells, so a
recipe never works in one shell and not the other.

A tool only one flake app needs is carried in that app's `runtimeInputs`
instead of the shell: `hspec-golden` rides with `update-golden`, `ghcid` with
`quick-typecheck`. `nix develop` inherits the caller's `PATH`, which is what
puts them in front of the recipe.

## Consequences

- `nix run .#lint` is cheap, which matters because agents run it constantly.
- The `ci` shell is not strictly minimal: `build` and `test` also realise the
  linters they never call. The cost is small next to the GHC package set the
  shell already carries.
- A new recipe that CI calls must have its tool added to `checkTools`, or CI
  fails with "command not found". That failure is loud and immediate, which is
  the right way for it to fail.
- HLS, `implicit-hie` and the ghcid TUI stay out of CI entirely.
