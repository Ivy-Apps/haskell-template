# By default, list all available commands
default:
    @just --list

# Run HLint then tests (use from nix develop); fails on lint or test errors
check:
    hlint .
    nix fmt --accept-flake-config -- --ci
    cabal test all
    cabal build

# Format Haskell, Cabal, and Nix files (fourmolu + cabal-fmt + nixfmt)
@fmt:
    treefmt

# Update Dependencies versions by updating the Nix flake input
@update-deps:
    nix flake update
    cabal update
    cabal freeze
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
