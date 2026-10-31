# Haskell template for Ivy Apps

An opinionated, reproducible starting point for Haskell projects at Ivy Apps. The
toolchain and every dependency are pinned with Nix, the code targets `GHC2024`
with a curated set of extensions, uses a custom [`relude`](https://hackage.haskell.org/package/relude)
prelude and [`effectful`](https://hackage.haskell.org/package/effectful) for
effects, and ships with an hspec / hedgehog / golden testing stack.

It's also designed to be agent-friendly - see [`CLAUDE.md`](./CLAUDE.md) for the
canonical command reference used by AI tooling.

## Key decisions

- **Nix is the source of truth for the toolchain.** `flake.lock` pins nixpkgs →
  the `ghc9103` package set → every Haskell dependency. The package is built with
  `callCabal2nix` and the dev shell is provided by `shellFor`. No `ghcup` or
  `stack`.
- **Dual dependency pinning.** Nix (`flake.lock`) governs the `nix build`, while
  `cabal.project` (`index-state`) + a committed `cabal.project.freeze` pin the
  same versions for Cabal - so the project also builds reproducibly without Nix.
  See [How dependency pinning works](#how-dependency-pinning-works).
- **Custom `relude` prelude.** `src/Prelude.hs` re-exports `Relude` via the
  `mixins: base hiding (Prelude)` trick, hiding the mtl/STM names that would
  clash with `effectful`. `Text` and the usual helpers are in scope without
  imports.
- **`effectful`** for effect management.
- **`GHC2024`** plus a curated `default-extensions` set (`OverloadedRecordDot`,
  `OverloadedStrings`, `NoFieldSelectors`, …) and `-Wall -Werror`.
- **Testing stack:** `hspec` (+ `hspec-discover`), `hedgehog` for property tests,
  and `hspec-golden` for golden tests. Effects such as `Effects.FileSystem` and
  `Effects.System` come with test doubles under `test/Doubles/`.
- **The Justfile is the source of truth for CI.** Every CI step is a `just`
  recipe run in the lean `ci` dev shell, cheapest first, and `just check` runs
  the same recipes locally. See [`docs/adr/`](./docs/adr/).
- **Spell checking** with [`typos`](https://github.com/crate-ci/typos), with a
  committed `.typos.toml` allowlist for genuine false positives.
- **Benchmarks** with `criterion` and a regression gate against a committed
  `bench/reference.yaml`. Local-only: CI compiles them but never runs them.
- **Agent-friendly fast feedback.** `nix run .#quick-typecheck` keeps a warm
  `ghcid` session and answers "does this typecheck" in about a second, and
  `nix run .#quick-test -- <filter>` runs the selected specs in that same
  session.
- **direnv.** `.envrc` (`use flake`) auto-loads the dev shell.

## Project layout

```
app/Main.hs            -- executable entrypoint
src/App.hs             -- library code
src/Effects/           -- effectful effects and their IO interpreters
src/FileSystem/        -- pure path vocabulary (AbsPath, OsPath/Text encoding)
src/Prelude.hs         -- custom relude-based prelude
test/                  -- hspec specs mirroring src/ (auto-discovered)
test/Doubles/          -- test doubles for the effects
bench/                 -- criterion benchmark + bench/reference.yaml
nix/ghcid/             -- the ghcid daemon behind quick-typecheck and quick-test
nix/mutation.nix       -- mutation testing; nix/mutation.yaml is its plugin config
docs/                  -- DEVELOPMENT.md and architecture decision records
haskell-app.cabal      -- package definition
cabal.project(.freeze) -- Cabal pins (index-state + frozen versions)
flake.nix / flake.lock -- Nix toolchain + dependency pins
Justfile               -- developer commands
.typos.toml            -- spell-check allowlist
```

## Getting started

1. Install Nix (the [Determinate Systems installer](https://github.com/DeterminateSystems/nix-installer)
   is recommended).
2. **Recommended:** install [direnv](https://direnv.net) and run `direnv allow`.
   The `.envrc` (`use flake`) then auto-loads the dev shell whenever you `cd` into
   the project. Manual alternative: `nix develop`.
3. Build, test, and lint (see below).

See [`docs/DEVELOPMENT.md`](./docs/DEVELOPMENT.md) for the full developer guide
and [`CONTRIBUTING.md`](./CONTRIBUTING.md) for how changes get reviewed.

## Common commands

From inside the dev shell (`just --list` shows them all):

| Task                   | Command                                   |
| ---------------------- | ----------------------------------------- |
| Run all checks (= CI)  | `just check`                              |
| Build                  | `just build`                              |
| Test                   | `just test`                               |
| Spell check            | `just typos`                              |
| Format / check format  | `just fmt` / `just fmt-check`             |
| Lint workflows         | `just lint-actions`                       |
| Audit workflows        | `just zizmor`                             |
| Architecture rules     | `just deslop`                             |
| Benchmark              | `just benchmark` / `just update-benchmark`|
| Compile the benchmark  | `just build-bench`                        |
| Quick typecheck        | `just quick-typecheck` / `just stop-ghcid`|
| Quick test             | `just quick-test [filter]`                |
| Mutation testing       | `just mutation`                           |
| Update deps            | `just update-deps`                        |
| Update golden          | `just update-golden`                      |
| Regenerate `hie`       | `just update-hie`                         |

Nix-driven shortcuts that work from anywhere (no shell needed - these are also
what AI tooling uses, see [`CLAUDE.md`](./CLAUDE.md)):

| Task            | Command                                |
| --------------- | -------------------------------------- |
| Build           | `nix run .#build`                      |
| Test            | `nix run .#test` (or `-- AppSpec`)     |
| Lint            | `nix run .#lint` (hlint + typos)       |
| Quick typecheck | `nix run .#quick-typecheck`            |
| Quick test      | `nix run .#quick-test` (or `-- AppSpec`) |
| Update golden   | `nix run .#update-golden`              |

## Mutation testing

`just mutation` breaks the library in small ways and checks that a test notices.
It runs [sydtest-mutation](https://github.com/NorfairKing/sydtest) over the hspec
suite through `fromHspec`, on x86_64-linux, and is not part of `just check`. It is
pinned in `flake.nix` and only `checks.<system>.mutation` evaluates it, so the
normal build, the dev shells and the `just check` jobs never fetch it.

### Licence warning: read this before you clone the template

sydtest and sydtest-mutation are **not** open source. These are the conditions
of [sydtest's `LICENSE.md`](https://github.com/NorfairKing/sydtest/blob/6ba5347b0f1ec27cc912bb45ca98e0e4f24343ea/sydtest/LICENSE.md),
at the pinned revision, for its `Anyone` grant:

> **Anyone** can use this software to test your software under the following license:
>
> ### Conditions:
>
> * _The software under test is not used for commercial purposes._
>   **OR**
>   _The software under test is open-source software licensed according to an [OSI-approved Open Source license](https://opensource.org/licenses)._
> * Any modifications to the licensed software must be made public under the same license with the same copyright holder.
> * The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

And for anyone else:

> **Contributors listed in [CONTRIBUTORS](./CONTRIBUTORS) or [GitHub sponsors of NorfairKing](https://github.com/sponsors/NorfairKing)** can use this software to test their software under the following conditions:

> **You can [contact me](https://cs-syd.eu/contact) for other arrangements (like a permanent license) on a case-to-case basis.**

What that means here:

- **This template** is BSD-3-Clause, an OSI-approved licence, so it fits the
  `Anyone` grant.
- **A clone under an OSI-approved licence, or one not used commercially,** fits
  it too.
- **A closed-source commercial clone does not fit it.** The condition is on the
  software under test, and the text has no exception for a tool that never ships
  in your product. Such a clone must do one of these: remove mutation testing
  (below), sponsor [NorfairKing](https://github.com/sponsors/NorfairKing), or
  [arrange a licence](https://cs-syd.eu/contact).

This is not legal advice. Read the licence yourself.

### Removing it

1. Delete `nix/mutation.nix`, `nix/mutation.yaml`, `test/MutationMain.hs`,
   `test/Spec.hs` and `docs/adr/0006-mutation-testing-is-advisory-and-outside-check.md`.
2. `flake.nix`: delete the `sydtest` input and the `checks.mutation` attribute,
   then run `nix flake lock`.
3. `haskell-app.cabal`: delete `flag mutation` and its comment. Replace the
   `if flag(mutation)` block, with its comment and `else`, by the two lines
   `type: exitcode-stdio-1.0` and `main-is: Main.hs`.
4. `test/TestUtils.hs`: delete `withActualIn`, the `GOLDEN_ACTUAL_DIR` lookup and
   the `actualFile` import, and let `pathSafeGolden` end in `pure . defaultGolden name`.
5. `Justfile`: delete the `mutation` recipe.
6. `.github/workflows/ci.yaml`: delete the `mutation` job, and `schedule` and
   `workflow_dispatch` from `on:`.
7. `README.md`, `CLAUDE.md`, `docs/DEVELOPMENT.md`, `CHANGELOG.md`: delete what
   mentions it.
8. Run `just fmt`. `rg -il 'mutation|sydtest'` then finds nothing, and `flake.lock`
   has no sydtest left in it.

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
reproducibly **without Nix** - a plain `cabal build` gets the same versions from
the freeze.

`nix build` (the flake's `packages.default`) is the exception: it builds purely from the `ghc9103` set
via `callCabal2nix` and **ignores** the freeze. That's why `just update-deps`
updates both layers at once.

## Updating dependencies

Run `just update-deps`, which:

1. `nix flake update` - refreshes the nixpkgs pin in `flake.lock`.
2. `cabal update` - pulls a fresh Hackage index.
3. `cabal freeze` - re-pins exact versions in `cabal.project.freeze`.

Then commit the updated `flake.lock` and `cabal.project.freeze` together so both
pinning layers stay in sync.
