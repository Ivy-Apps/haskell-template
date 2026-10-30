# Compile modules in parallel: GHC builds one at a time otherwise. Bounded at
# four rather than every core, so a many-core machine does not multiply the
# memory one build needs. Passed here, not set in cabal.project, so it stays out
# of the ghcid session's unit files (see nix/ghcid/session.nix). Cabal leaves
# `-j` out of its change detection, so a build with it and one without reuse
# each other's dist-newstyle. The Nix build passes its own -j. flake.nix repeats
# this for `nix run .#build`, `nix run .#test` and `nix run .#quick-test`; keep
# the two in step.
parallel := "--ghc-options=-j4"

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
