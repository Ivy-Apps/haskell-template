# Haskell template for Ivy Apps

An opinionated, reproducible starting point for Haskell projects at Ivy Apps. The
toolchain and every dependency are pinned with Nix, the code targets `GHC2024`
with a curated set of extensions, uses a custom [`relude`](https://hackage.haskell.org/package/relude)
prelude and [`effectful`](https://hackage.haskell.org/package/effectful) for
effects, and ships with an hspec / hedgehog / golden testing stack.

It's also designed to be agent-friendly — see [`CLAUDE.md`](./CLAUDE.md) for the
canonical command reference used by AI tooling.

## Key decisions

- **Nix is the source of truth for the toolchain.** `flake.lock` pins nixpkgs →
  the `ghc9103` package set → every Haskell dependency. The package is built with
  `callCabal2nix` and the dev shell is provided by `shellFor`. No `ghcup` or
  `stack`.
- **Dual dependency pinning.** Nix (`flake.lock`) governs the `nix build`, while
  `cabal.project` (`index-state`) + a committed `cabal.project.freeze` pin the
  same versions for Cabal — so the project also builds reproducibly without Nix.
  See [How dependency pinning works](#how-dependency-pinning-works).
- **Custom `relude` prelude.** `src/Prelude.hs` re-exports `Relude` via the
  `mixins: base hiding (Prelude)` trick, hiding the mtl/STM names that would
  clash with `effectful`. `Text` and the usual helpers are in scope without
  imports.
- **`effectful`** for effect management.
- **`GHC2024`** plus a curated `default-extensions` set (`OverloadedRecordDot`,
  `OverloadedStrings`, `NoFieldSelectors`, …) and `-Wall -Werror`.
- **Testing stack:** `hspec` (+ `hspec-discover`), `hedgehog` for property tests,
  and `hspec-golden` for golden tests.
- **direnv + CI.** `.envrc` (`use flake`) auto-loads the dev shell; GitHub Actions
  builds via `nix build` and runs the tests with `cabal test`.

## Project layout

```
app/Main.hs            -- executable entrypoint
src/App.hs             -- library code
src/Prelude.hs         -- custom relude-based prelude
test/AppSpec.hs        -- hspec specs (auto-discovered)
haskell-app.cabal      -- package definition
cabal.project(.freeze) -- Cabal pins (index-state + frozen versions)
flake.nix / flake.lock -- Nix toolchain + dependency pins
Justfile               -- developer commands
```

## Getting started

1. Install Nix (the [Determinate Systems installer](https://github.com/DeterminateSystems/nix-installer)
   is recommended).
2. **Recommended:** install [direnv](https://direnv.net) and run `direnv allow`.
   The `.envrc` (`use flake`) then auto-loads the dev shell whenever you `cd` into
   the project. Manual alternative: `nix develop`.
3. Build, test, and lint (see below).

## Common commands

From inside the dev shell:

| Task              | Command                          |
| ----------------- | -------------------------------- |
| Run all checks    | `just check`                     |
| Build             | `cabal build`                    |
| Test              | `cabal test`                     |
| Update deps       | `just update-deps`               |
| Update golden     | `just update-golden`             |
| Regenerate `hie`  | `just update-hie`                |

Nix-driven shortcuts that work from anywhere (no shell needed — these are also
what AI tooling uses, see [`CLAUDE.md`](./CLAUDE.md)):

| Task   | Command                                |
| ------ | -------------------------------------- |
| Build  | `nix run .#build`                      |
| Test   | `nix run .#test` (or `-- AppSpec`)     |
| Lint   | `nix run .#lint`                       |

## How dependency pinning works

There are two pinning layers, with **Cabal driving the dev build**:

- `flake.lock` pins nixpkgs → the `ghc9103` set → pre-built versions of every
  dependency.
- `cabal.project` (`index-state`) + `cabal.project.freeze` pin the same versions
  for Cabal.

When you run `cabal build`, Cabal resolves every dependency to the version pinned
in `cabal.project.freeze`. For each one it first looks in the **Nix store** (the
dev shell exposes the pre-built `ghc9103` packages); if the pinned version is
already there it's reused with no rebuild, otherwise Cabal downloads and builds it
from Hackage at the pinned `index-state`. This is what lets the project build
reproducibly **without Nix** — a plain `cabal build` gets the same versions from
the freeze.

`nix build` (used in CI) is the exception: it builds purely from the `ghc9103` set
via `callCabal2nix` and **ignores** the freeze. That's why `just update-deps`
updates both layers at once.

## Updating dependencies

Run `just update-deps`, which:

1. `nix flake update` — refreshes the nixpkgs pin in `flake.lock`.
2. `cabal update` — pulls a fresh Hackage index.
3. `cabal freeze` — re-pins exact versions in `cabal.project.freeze`.

Then commit the updated `flake.lock` and `cabal.project.freeze` together so both
pinning layers stay in sync.
