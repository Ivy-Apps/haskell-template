# Revision history for haskell-template

## Unreleased

* Every action in `.github` is pinned to a commit, and `zizmor`
  (`.github/zizmor.yml`, `just zizmor`) fails `just check` and CI on one that
  is not.
* `QA.md`: how the `qa` skill checks this repository.
* Mutation testing: `just mutation` runs sydtest-mutation over the hspec suite
  through `fromHspec`, behind the cabal flag `mutation` and the flake check
  `checks.<system>.mutation`. Outside `just check` and the aggregate `Check`:
  a new x86_64 CI job runs it on every push and PR, weekly and by hand, shows
  the score in the job summary and uploads the report. A test failing at
  baseline fails it, a survivor never does. Read the licence conditions in the
  README before cloning this template for closed-source commercial work.
* `Effects.System` has a spec, added for a mutant nothing covered.

## 1.3.0 -- 2026-10-28

* `nix run .#quick-test [-- <filter>]` (and `just quick-test`): runs the tests,
  or only the specs a filter matches, in the warm quick-typecheck session.
* The ghcid tooling moves to `nix/ghcid/` and grows sturdier: a session goes
  stale when `haskell-app.cabal` changes and is never reported "All good",
  "Ghcid has stopped." exits 2, daemons from an older version are respawned,
  sessions compile with `-j4` and retire after 2 hours idle.
* Builds and tests compile with `-j4`; `hlint` checks four files at a time.
* `deslop`, the architecture checker, from its flake: `deslop/rules/` states
  the import rules, `just deslop` checks them and runs in `just check` and CI.
* CI runs Lint, Build and test, and Benchmark as parallel jobs sharing a cabal
  store cache (`.github/actions/cabal-store`), behind one aggregate `Check`.
* `Doubles.FileSystem`: an in-memory file system (`InMemoryFileSystem`) that
  records writes by path, next to the read-only mock (`mockFileSystem` is now
  `mockTree`, `runMockWrFileSystem` is now `runWritesInMemory`).
* `CLAUDE.md`: the check ladder and an "Architecture rules" section.

## 1.2.0 -- 2026-10-22

* `nix run .#quick-typecheck` (and `just quick-typecheck` / `just stop-ghcid`):
  a warm ghcid daemon that answers "does this typecheck" in about a second.
  Defined in `nix/ghcid.nix`, parameterised by the project name.
* `nix run .#update-golden`, re-recording the golden snapshots from the `ci` shell.
* `typos` spell checker: `.typos.toml`, `just typos`, wired into `treefmt`,
  `nix run .#lint` and CI.
* Benchmarks: a criterion harness under `bench/` with a regression gate against
  the committed `bench/reference.yaml` (`just benchmark`, `just update-benchmark`).
  CI compiles it (`just build-bench`) but never runs it.
* Granular Justfile recipes (`typos`, `fmt-check`, `check-nix`, `lint`,
  `lint-actions`, `build`, `build-nix`, `build-bench`, `test`), composed by
  `just check`.
* CI runs every step as `just <recipe>` in the lean `ci` dev shell, cheapest
  first, cancels superseded PR runs, and lints its own workflows with
  actionlint + shellcheck. `nix run .#lint` now uses the `ci` shell too.
* `FileSystem.Path` (`AbsPath`, OsPath/Text encoding) and the
  `Effects.FileSystem` effect (read/write split) with its test double
  `Doubles.FileSystem`.
* `TestUtils`: `requireJust`, `requireRight`, `pathSafeGolden`, `snapshot`,
  `copyDir`, `listFixtures`.
* The test suite enables `QuasiQuotes` and `TemplateHaskell` by default.
* Docs: `CLAUDE.md` sections on fast feedback, golden tests, test layout and
  where new code goes; `docs/DEVELOPMENT.md`, `CONTRIBUTING.md`,
  architecture decision records in `docs/adr/`, and GitHub PR and issue
  templates.

## 0.1.0.0 -- YYYY-mm-dd

* First version. Released on an unsuspecting world.
