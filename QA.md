# QA

## Run the app

This repository is a Haskell template. It has no web app, no server and no URL,
so there is no browser run. The executable prints `Hello` and exits. Running it
means building what the PR changes and reading the output.

Start from a checkout of the PR, in the `ci` dev shell. On a fresh machine,
fetch the Hackage index once first:

```sh
nix develop .#ci -c just update-index
nix develop .#ci -c cabal run -v0 haskell-app
```

Ready when it prints `Hello` and exits 0.

| The PR changes | Run | Ready when |
| --- | --- | --- |
| `src/`, `app/`, `test/` | `nix run .#quick-test` | it exits 0 |
| `bench/` | `nix develop .#ci -c just build-bench` | it exits 0 |
| `nix/ghcid/` | `nix run .#quick-typecheck`, then `nix run .#quick-test` | they exit 0 |
| `.github/` | `nix develop .#ci -c bash -c 'just lint-actions && just zizmor'` | it exits 0 |
| `flake.nix`, `Justfile` | `nix develop .#ci -c just check` | it exits 0 |

## Key flows

- `nix develop .#ci -c just check` runs what CI runs. It is the final gate and
  takes minutes: run it once.

## Quirks

- Flakes see only files git tracks. Run `git add -N <new files>` before a build.
- A new module is invisible to `quick-test` until it is in `haskell-app.cabal`.
- Proof is command output, not video.

## Out of scope

- `just benchmark`: benchmarks are local only, and CI compiles them without
  running them. See `docs/adr/0004-benchmarks-are-local-only.md`.
