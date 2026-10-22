# CLAUDE.md

## Commands

All cabal/GHC commands must run inside the Nix dev shell using our `nix run` commands.

### Fast feedback

While iterating on code, use this instead of a full build:

```bash
nix run .#quick-typecheck
```

It answers exactly one question, "does the project typecheck", by keeping a warm
`ghcid` session over the library, the executable and the tests (not the
benchmark, which CI compiles). It prints either `All good (<N> modules)` and
exits 0, or the GHC errors verbatim and exits 1. There is no need to pipe it
through `grep`.

A fraction of a second when nothing broke and a couple of seconds when
something did, against a full `nix run .#build`. The first call starts the
session and takes longer; every call after that is fast, so just run it and
keep going.

**This is not a quality gate.** The session is interpreted, so it does not run
tests, does not run `hlint`, does not link, and does not compile with
optimisations. Use it to converge quickly, then finish with the real checks
below. **You are not done until `nix run .#build`, `nix run .#test` and
`nix run .#lint` pass.**

Notes:

- Editing `haskell-app.cabal` restarts the session, so that check costs about
  as much as a build.
- A new module is invisible to the session until it is registered in
  `haskell-app.cabal`. Register it there first; until then the check refuses to
  report and names the file.
- Long error output is truncated; the printed path holds the full text.
- Exit codes: 0 typechecks, 1 GHC errors, 2 no usable verdict (the reason goes
  to stderr).
- You should not normally need to stop the daemon: it retires itself after 30
  minutes idle. To reclaim its memory now, run `nix develop -c just stop-ghcid`
  from the repo root. It stops every daemon on the machine, including ones other
  worktrees are still using, so do not run it as routine cleanup.

### Building

```bash
nix run .#build
```

### Running Tests

Run all tests:
```bash
nix run .#test
```

Run tests for a specific module (matches against the root `describe` block):
```bash
nix run .#test -- AppSpec
nix run .#test -- SomeModule
```

### Linting

```bash
nix run .#lint
```

Runs `hlint` and the `typos` spell checker. A typos finding is fixed by
correcting the spelling; only a genuine false positive goes in `.typos.toml`,
with a comment saying why it is one.

### The full quality suite

CI runs every recipe in `just check`, one step each, in the lean `ci` shell.
To run exactly what CI runs (on a fresh machine, fetch the Hackage index once
first):

```bash
nix develop .#ci -c just update-index   # once per machine
nix develop .#ci -c just check
```

Individual recipes: `just typos`, `just fmt-check`, `just check-nix`,
`just lint`, `just lint-actions` (actionlint + shellcheck over
`.github/workflows/`), `just build`, `just build-nix`, `just build-bench`, `just test`.

### Updating golden tests

```bash
nix run .#update-golden
```

Re-records every hspec-golden snapshot in `.golden/` and stages the result.

**A failing golden test is not a reason to run this.** It means the output
changed. Work out whether that change was intended first; only then re-record,
and read the resulting `git diff` before committing it. Re-recording to make a
red test green throws away the only thing the snapshot was protecting.

It starts by emptying `.golden/`, so a run that fails to compile leaves the
directory empty. `git checkout .golden` restores it.

### Benchmarks

```bash
nix develop -c just benchmark          # measure, fail on regression
nix develop -c just update-benchmark   # accept the numbers into bench/reference.yaml
```

Local-only: CI compiles the benchmark (`just build-bench`) but never runs it,
because timings are only comparable on the machine that recorded them. Do not
run `update-benchmark` to silence a regression you have not explained. Cases
live in `bench/Bench/Cases.hs`. See
[ADR 4](docs/adr/0004-benchmarks-are-local-only.md).

## Where new code goes

- **`src/Effects/`** - every effect declaration and its IO interpreter
  (`Effects.System`, `Effects.FileSystem`). Code that reaches the outside world
  does so through an effect here, so tests can swap in a double.
- **`src/FileSystem/`** - pure path vocabulary (`AbsPath`, OsPath/Text
  encoding). Nothing here performs IO.
- **`src/<Feature>/`** - feature code, one module per concept, named for its
  subject. No catch-all `Types.hs` or `Utils.hs` modules.
- **`app/Main.hs`** stays a thin entry point; logic lives in the library so the
  tests can reach it.
- **`bench/Bench/Cases.hs`** is the only project-specific benchmark module.

## Tests

Tests mirror `src/`:

- `src/FileSystem/Path.hs` -> `test/FileSystem/PathSpec.hs`, whose root
  `describe` is the full module name, `"FileSystem.Path"`. That is what makes
  `nix run .#test -- FileSystem.Path` select what its name says.
- Variants suffix the module name: `FooPropSpec` for property tests next to
  `FooSpec`.
- Test doubles for an effect live in `test/Doubles/<Effect>.hs`
  (`Doubles.System`, `Doubles.FileSystem`). Prefer an in-memory fake over a stub.
- A helper stays private in its spec until a **second** spec needs it. Then it
  moves to `Fixtures.<full.module.path>` or `Generators.<full.module.path>`.
- `TestUtils` holds only domain-free plumbing (hspec, Hedgehog, golden and
  filesystem helpers). Nothing that knows the project's own types.

## Coding Conventions

- **Custom Prelude:** The project uses `relude` as a custom prelude and `Text` (Data.Text) is available without importing.
- **Extensions:** Assume `OverloadedRecordDot` is enabled.
- **Function composition:** Prefer `f . g $ a` over `f $ g a`.
- **Decisions:** architectural decisions are recorded in [`docs/adr/`](docs/adr/).
  Read them before changing CI, the dev shells or the Justfile.
