# Compile modules in parallel: GHC builds one at a time otherwise. Bounded at
# four rather than every core, so a many-core machine does not multiply the
# memory one build needs. Passed here, not set in cabal.project, so it stays out
# of the ghcid session's unit files (see nix/ghcid/session.nix). Cabal leaves
# `-j` out of its change detection, so a build with it and one without reuse
# each other's dist-newstyle. The Nix build passes its own -j. flake.nix repeats
# this for `nix run .#build`, `nix run .#test` and `nix run .#quick-test`; keep
# the two in step.
parallel := "--ghc-options=-j4"
mutation_check := ".#checks.x86_64-linux.mutation"

# By default, list all available commands
default:
    @just --list

# Run the full quality suite, cheapest first (use from nix develop); mirrors CI
check:
    just typos
    just fmt-check
    just check-nix
    just lint
    just lint-actions
    just zizmor
    just deslop
    just build
    just build-nix
    just build-bench
    just test

# Spell check every file (typos, reading .typos.toml)
typos:
    typos

# Fail if any file is not formatted (fourmolu + cabal-fmt + nixfmt + typos)
fmt-check:
    treefmt --ci

# Lint Nix files (statix + deadnix)
check-nix:
    statix check .
    deadnix --fail .

# Haskell lint (hlint). -j4 checks four files at a time, with the same output
# as a serial run; bounded at four like `parallel`.
lint:
    hlint -j4 .

# Lint the GitHub Actions workflows (actionlint, with shellcheck over `run:`).
# shellcheck has to be on PATH: without it actionlint silently skips every
# `run:` block, which is where a workflow keeps its logic. SC2153 is off
# because shellcheck cannot see a workflow's `env:` block, so every
# `for X in $XS` over an injected variable reads to it as a typo for the loop
# variable. actionlint 1.7.12 disables the rule by default; until nixpkgs
# catches up we adopt that default by hand.
lint-actions:
    actionlint -shellcheck="shellcheck -e SC2153"

# Audit .github for security problems (zizmor, reading .github/zizmor.yml), which
# fails on an action not pinned to a commit. --offline needs no token, so a pin
# is not checked to be a real commit of its action. --strict-collection fails on
# a file zizmor cannot parse, which it would otherwise skip with a warning.
zizmor:
    zizmor --offline --strict-collection .

# Mutation-test the library: prints the score and leaves the report in
# result/haskell-app/report.{txt,json}. Not part of `check`: a local cold
# build takes about 25 minutes. Fails on a test failing at baseline, on a failed
# control or on a run with no control, never on a survivor. See nix/mutation.nix
mutation:
    nix build {{ mutation_check }} --accept-flake-config
    cat result/score.md

# Mutation-test only the lines this branch adds or edits since its merge-base
# with `base`, uncommitted edits included. Prints the compact report and writes
# it, with mutation-diff.json, to dist-newstyle/mutation-diff/; the JSON's path
# is the last line. Exits 0 whatever survives. Fails only when the run itself
# did: a test failing at baseline, a failed control or a runner that died. Tool
# output goes to run.log there. See nix/mutation-diff.jq
mutation-diff base="origin/main":
    #!/usr/bin/env bash
    set -euo pipefail
    out="$PWD/dist-newstyle/mutation-diff"
    log="$out/run.log"
    fail() { echo "mutation-diff: $1. Full log: $log" >&2; tail -n 30 "$log" >&2; exit 1; }
    rm -rf "$out"
    mkdir -p "$out"
    base_sha="$(git merge-base {{ quote(base) }} HEAD)"
    nix build -L "{{ mutation_check }}.baseline" --accept-flake-config --no-link >> "$log" 2>&1 \
        || fail "a test fails before any mutation, so every kill would be false"
    # The runner exits 1 on a survivor and on a crash alike. Only a run that
    # returned prints its report line, and only then is report.json whole.
    status=0
    nix run "{{ mutation_check }}.diff" --accept-flake-config -- --base "$base_sha" --no-fail-fast --out-dir "$out" >> "$log" 2>&1 || status=$?
    case "$status" in 0 | 1) ;; *) fail "the runner died with exit code $status" ;; esac
    grep -q '^Machine-readable report: ' "$log" || fail "the runner ended without writing its report"
    # A diff selects a control only where it touches one (each module's first
    # mutation site, then every 100th), so zero controls is normal here.
    jq -e '.controls.failed == 0' "$out/report.json" > /dev/null \
        || fail "a control was killed, so the harness kills unmutated code and every kill may be false"
    jq -L nix --arg head "$(git rev-parse HEAD)" --arg base "$base_sha" \
        'include "mutation-diff"; report($head; $base)' "$out/report.json" > "$out/mutation-diff.json"
    jq -j -L nix 'include "mutation-diff"; render' "$out/mutation-diff.json" > "$out/mutation-diff.md"
    cat "$out/mutation-diff.md"
    echo "$out/mutation-diff.json"

# Fetch the Hackage index that cabal.project's pinned index-state requires
update-index:
    cabal update

# Check the architecture rules in deslop/rules/ (import direction, layering)
deslop:
    deslop check .

# Compile the library, the executable and the tests
build:
    cabal build all {{parallel}}

# Build the flake's package exactly as `nix build` users and downstream flakes get it
build-nix:
    nix build . --accept-flake-config

# Compile the benchmark without running it. CI runs this; see docs/adr/0004
build-bench:
    cabal build --enable-benchmarks haskell-app-bench {{parallel}}

# Run the test suite
test:
    cabal test all {{parallel}}

# Measure performance and fail if it regressed against bench/reference.yaml
benchmark:
    cabal bench haskell-app-bench

# Accept the current performance as the new benchmark Reference
update-benchmark:
    cabal bench haskell-app-bench --benchmark-options=--update

# Format Haskell, Cabal, and Nix files (fourmolu + cabal-fmt + nixfmt + typos)
@fmt:
    treefmt

# Does the project typecheck? Fast inner loop, NOT a quality gate: see `check`
@quick-typecheck:
    ai-quick-typecheck

# Do the tests pass? Optionally filtered: `just quick-test FileSystem.Path`. Fast
# inner loop in the quick-typecheck session, NOT a quality gate: see `check`
@quick-test *filter:
    ai-quick-test {{filter}}

# Stop every background ghcid daemon behind `just quick-typecheck` and `just quick-test`
@stop-ghcid:
    ghcid-stop

# Update Dependencies versions by updating the Nix flake input
@update-deps:
    nix flake update
    cabal update
    cabal freeze --enable-tests --enable-benchmarks
    echo "Done! Dependencies updated and securely locked in 'cabal.freeze' ❄️"

# Update the HSpec Golden tests
@update-golden:
    rm -rf .golden/*
    mkdir -p .golden
    cabal test
    hgold
    git add .golden

# Updates hie.yaml (must be in nix develop)
@update-hie:
    gen-hie > hie.yaml
    echo "✅ Hie updated."

# Fixes HLS by purging caches and rebuilding
@fix-hls:
    echo "🛑 Stopping any running HLS instances..."
    -pkill haskell-language-server || true
    
    echo "🧹 Cleaning project-local artifacts..."
    rm -rf .hls/
    rm -rf dist-newstyle/
    
    echo "🔥 Purging global GHCide cache (the usual culprit for ARR_WORDS errors)..."
    rm -rf ~/.cache/ghcide
    
    echo "📦 Re-building project to sync cabal.freeze..."
    cabal build all
    
    echo "✅ Clean complete. Please restart your IDE"
