# Development

Everything you need to build, test and lint the project locally. For the rules
that govern what gets reviewed and merged, see
[CONTRIBUTING.md](../CONTRIBUTING.md).

## Setup

The project is written in Haskell (GHC 9.10.3) and uses
[Nix](https://nixos.org/) for a reproducible dev environment.

### 1. Install Nix

**Recommended - the [Determinate Nix installer](https://github.com/DeterminateSystems/nix-installer):**

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

It turns flakes on out of the box, which this project needs, and it can be
undone with `/nix/nix-installer uninstall`. It is also what CI uses, so your
machine matches [`ci.yaml`](../.github/workflows/ci.yaml).

The upstream installer works too, but then you have to enable
`nix-command flakes` in `nix.conf` yourself.

### 2. Enter the dev shell

**Recommended - [direnv](https://direnv.net/):**

```bash
curl -sfL https://direnv.net/install.sh | bash   # binary install
```

Then hook it into your shell (`~/.zshrc` for zsh, `~/.bashrc` for bash) and
allow this project once:

```bash
eval "$(direnv hook zsh)"
direnv allow
```

From then on the Nix dev shell is entered automatically whenever you `cd` into
the project.

**Alternative - manual:**

```bash
nix develop
```

All `cabal`/GHC commands must run inside the dev shell. On a fresh machine,
fetch the Hackage package index once: `just update-index`.

## Commands

```bash
nix run .#build   # build
nix run .#test    # run all tests
nix run .#lint    # lint (hlint + typos)
```

Run tests for a specific module - the argument matches against the root
`describe` block:

```bash
nix run .#test -- FileSystem.Path
```

While iterating, `nix run .#quick-typecheck` answers "does this typecheck" in
about a second by keeping a warm `ghcid` session, and
`nix run .#quick-test -- FileSystem.Path` runs the selected specs in that same
session (with no filter, it runs the compiled suite). They are an inner loop,
not a gate: they do not lint, link or optimise. You are not done until
`just check` passes.

Inside `nix develop`, [`just`](https://github.com/casey/just) provides
additional workflows (`just --list` for all of them):

| Command | What it does |
|---------|-------------|
| `just check` | The full quality suite, exactly the steps CI runs |
| `just typos` | Spell check every file against `.typos.toml` |
| `just fmt` / `just fmt-check` | Format everything / fail if anything is unformatted |
| `just check-nix` | Lint Nix files (statix + deadnix) |
| `just lint` | hlint |
| `just lint-actions` | Lint the GitHub workflows (actionlint + shellcheck) |
| `just zizmor` | Audit `.github` for security problems, unpinned actions included |
| `just deslop` | Check the architecture rules in `deslop/rules/` |
| `just build` / `just test` | Compile / run the test suite |
| `just build-nix` | Build the flake package (`nix build .`) |
| `just build-bench` | Compile the benchmark without running it |
| `just benchmark` | Measure performance; fails on regression against `bench/reference.yaml` |
| `just update-benchmark` | Accept the current numbers into `bench/reference.yaml` |
| `just quick-typecheck` / `just stop-ghcid` | The warm ghcid typecheck / stop every ghcid daemon |
| `just quick-test [filter]` | Run the specs in the warm ghcid session |
| `just update-golden` | Re-record the hspec-golden snapshots in `.golden/` |
| `just update-deps` | Update the Nix flake inputs and re-freeze cabal dependencies |
| `just update-hie` | Regenerate `hie.yaml` |
| `just fix-hls` | Purge caches and rebuild when the language server misbehaves |

## Project layout

| Path | Contents |
|------|----------|
| `app/Main.hs` | Executable entry point, kept thin |
| `src/` | Library code |
| `src/Effects/` | `effectful` effects and their IO interpreters |
| `src/FileSystem/` | Pure path vocabulary (`AbsPath`, OsPath/Text encoding) |
| `src/Prelude.hs` | Custom `relude`-based prelude |
| `test/` | hspec suites mirroring `src/` |
| `test/Doubles/` | Test doubles for the effects |
| `bench/` | criterion benchmark and its regression gate |
| `nix/` | Nix code too large for `flake.nix` (the ghcid daemon) |
| `docs/adr/` | Architecture decision records |

## Coding conventions

- **Custom prelude:** the project uses [`relude`](https://hackage.haskell.org/package/relude), so `Text` is available without importing.
- **Extensions:** `GHC2024` with `OverloadedRecordDot` enabled.
- **Function composition:** prefer `f . g $ a` over `f $ g a`.
- **Warnings are errors:** the build runs with `-Wall -Werror`.
- **Formatting** is handled by `nix fmt` (fourmolu, cabal-fmt, nixfmt, typos).

[`CLAUDE.md`](../CLAUDE.md) documents where new code goes and the test layout in
more detail. It is written for AI agents, and it is also the fastest description
of how this codebase is built.

## Testing

Tests mirror `src/`: `src/FileSystem/Path.hs` is tested by
`test/FileSystem/PathSpec.hs`, whose root `describe` is `"FileSystem.Path"`.
Property tests use Hedgehog through `TestUtils.prop`; a module's property tests
may live in a separate `FooPropSpec`.

Code that reaches the outside world goes through an effect, so tests can run it
against a double from `test/Doubles/` instead of the real machine.

Golden tests compare output against snapshots in `.golden/`. If you
intentionally change output, re-record them with `just update-golden` and review
the diff before committing. A failing golden test is never by itself a reason
to re-record.

## Benchmarks

`just benchmark` measures the cases in `bench/Bench/Cases.hs` and fails if time
or allocations regressed against `bench/reference.yaml`. The Reference is
specific to the machine that recorded it, so benchmarks are local-only: CI only
compiles them. After a deliberate performance change, run
`just update-benchmark` and commit the new Reference. See
[ADR 4](adr/0004-benchmarks-are-local-only.md).
