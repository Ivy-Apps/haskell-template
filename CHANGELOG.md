# Revision history for haskell-template

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
