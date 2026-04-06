# By default, list all available commands
default:
    @just --list

# Run HLint then tests (use from nix develop); fails on lint or test errors
check:
    hlint . && cabal test all && cabal build

# Generate a testing '/sandbox' project dir
@sandbox:
    rm -rf sandbox
    mkdir -p sandbox
    cp -a test/fixtures/ts-project-1/. sandbox/
    echo 'Sandbox generated ✅'

# Update Cabal index, get latest versions, and freeze them
@update:
    echo "Updating Cabal index..."
    cabal update
    echo "Resolving fresh dependencies..."
    rm -f cabal.project.freeze
    cabal freeze
    echo "Done! Dependencies updated and locked in 'cabal.project.freeze' ❄️"

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
