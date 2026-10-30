# CLAUDE.md

## Commands

All cabal/GHC commands must run inside the Nix dev shell using our `nix run` commands.

### The check ladder

1. While iterating: `nix run .#quick-typecheck`, then
   `nix run .#quick-test [-- <filter>]` once it is green. They cover every
   `.hs` edit, so never run a full `just check` mid-work.
2. Once, before handing back: `nix develop .#ci -c just check`, in the
   background. It already runs the build, the tests and the linters, so never
   run `nix run .#build`, `.#test` or `.#lint` before it.
3. After an edit that touches no code (docs only), or only a `git commit`, run
   nothing: rerun the full check only after a code edit.
4. Several `cabal` or `just` commands in a row share one shell,
   `nix develop .#ci -c bash -c '...'`, instead of a `nix run .#test`,
   `.#build` or `.#lint` each (they wrap those commands), which pays the
   `nix develop` start-up on every call.

### Fast feedback

```bash
nix run .#quick-typecheck
nix run .#quick-test -- FileSystem.Path    # or no filter for the whole suite
```

Both keep one warm `ghcid` session per worktree over the library, the
executable and the tests (not the benchmark, which CI compiles), so an edit
costs a reload instead of a recompile and relink.

`quick-typecheck` answers "does the project typecheck". It prints either
`All good (<N> modules)` and exits 0, or the GHC errors verbatim and exits 1.
There is no need to pipe it through `grep`. A fraction of a second when
nothing broke and a couple of seconds when something did. The first call
starts the session and takes longer; every call after that is fast, so just
run it and keep going.

`quick-test` typechecks the same way, then runs the hspec suite inside the
session, filtered like `nix run .#test -- <filter>`. After the typecheck's
`All good (<N> modules)` it prints only failures and the summary line, and
exits 0 when they pass, 1 on a GHC error, a failing test or a filter that
matches nothing. A filtered run costs a reload rather than a rebuild. With no
filter it runs the compiled suite through `cabal test` instead, which beats
running the whole suite interpreted.

**Neither is a quality gate.** The session is interpreted, so it does not run
`hlint`, does not link, and does not compile with optimisations: step 2 of
the ladder is the gate.

Notes:

- Editing `haskell-app.cabal` restarts the session, so that check costs about
  as much as a build.
- A new module is invisible to the session until it is registered in
  `haskell-app.cabal`. Register it there first; until then the check refuses to
  report and names the file.
- Long output is truncated; the printed path holds the full text.
- Exit code 2 means no usable verdict; the reason goes to stderr.
- You should not normally need to stop the daemon: it retires itself after 2
  hours idle. To reclaim its memory now, run `nix develop -c just stop-ghcid`
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

CI runs every recipe in `just check`, one step each, in the lean `ci` shell,
split across parallel jobs (lint, build and test, benchmark).
To run exactly what CI runs (on a fresh machine, fetch the Hackage index once
first):

```bash
nix develop .#ci -c just update-index   # once per machine
nix develop .#ci -c just check
```

Individual recipes: `just typos`, `just fmt-check`, `just check-nix`,
`just lint`, `just lint-actions` (actionlint + shellcheck over
`.github/workflows/`), `just zizmor` (security audit of `.github`), `just deslop`, `just build`, `just build-nix`, `just build-bench`, `just test`.

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

## Architecture rules

`just deslop` enforces the import rules below (`deslop/rules/`); the rest are
on you.

- **Imports point inward.** Features depend on infrastructure, never the other
  way: `src/Effects/` and `src/FileSystem/` never name a domain type.
- **IO only through `Effects/`.** Nothing else in the library reaches the
  outside world, so every test can run against an in-memory double.
- **Test helpers stay in tests.** Nothing under `src/`, `app/` or `bench/`
  imports a test double or test utility (`Doubles.*`, `TestUtils`).
- **Keep core logic and rendering pure.** Compute values and build the output
  text in pure functions; the edge performs the IO.
- **Test through the public interface.** Assert what a caller can observe, so
  a refactor that keeps the behaviour keeps the tests green.
- **Never golden a derived `Show`.** It dumps internal structure, so every
  refactor churns the snapshot and it gets re-recorded blindly. Golden
  user-facing output or a deliberate renderer.

## Tests

Tests mirror `src/`:

- `src/FileSystem/Path.hs` -> `test/FileSystem/PathSpec.hs`, whose root
  `describe` is the full module name, `"FileSystem.Path"`. That is what makes
  `nix run .#test -- FileSystem.Path` select what its name says.
- Variants suffix the module name: `FooPropSpec` for property tests next to
  `FooSpec`.
- No test spawns the `haskell-app` executable: a `build-tool-depends` on it
  breaks `quick-typecheck` on a fresh checkout, because `cabal repl` would
  have to build the executable before the session can load. Test through the
  library instead.
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
