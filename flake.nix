{
  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://cache.iog.io"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
    ];
    allow-import-from-derivation = true;
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    flake-parts.url = "github:hercules-ci/flake-parts";

    my-nixvim = {
      url = "github:ILIYANGERMANOV/my-nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, my-nixvim, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      perSystem = { config, pkgs, system, ... }:
        let
          projectName = "haskell-app";
          ghcVersion = "ghc9103";

          hlib = pkgs.haskell.lib.compose;
          hpkgs = pkgs.haskell.packages.${ghcVersion}.override {
            overrides = self: super: {
              ${projectName} = self.callCabal2nix projectName ./. { };
              fmt = hlib.dontCheck super.fmt;
            };
          };

          hgold = pkgs.haskell.lib.justStaticExecutables hpkgs.hspec-golden;
          sysLibs = [ pkgs.zlib pkgs.xz ];
          nvim = my-nixvim.lib.mkHaskellNvim pkgs hpkgs;
        in
        {
          # nix build
          packages.default = hlib.justStaticExecutables hpkgs.${projectName};
          # nix run
          apps.default = {
            type = "app";
            program = "${config.packages.default}/bin/${projectName}";
          };

          devShells = {
            ci = hpkgs.shellFor {
              packages = p: [ p.${projectName} ];
              withHoogle = false;

              nativeBuildInputs = [
                pkgs.pkg-config
                pkgs.cabal-install
              ];

              buildInputs = sysLibs;
            };

            default = hpkgs.shellFor {
              packages = p: [ p.${projectName} ];
              withHoogle = false;

              nativeBuildInputs = [
                nvim
                hgold
                pkgs.pkg-config
                pkgs.cabal-install
                pkgs.just
                hpkgs.haskell-language-server
                hpkgs.implicit-hie
              ];

              buildInputs = sysLibs;

              shellHook = ''
                echo "🔮 Haskell Dev env initialized."
                echo "--------------------------------------------------------"

                echo "✅ GHC:     $(ghc --version)"
                CABAL_PATH=$(type -p cabal)
                CABAL_VER=$(cabal --version | head -n 1)
                if [[ "$CABAL_PATH" == *"/nix/store/"* ]]; then
                    echo "✅ Cabal:   $CABAL_VER"
                    echo "            Path: $CABAL_PATH"
                else
                    echo "❌ Cabal:   $CABAL_VER"
                    echo "            ⚠️  WARNING: Not sourced from Nix!"
                    echo "            Path: $CABAL_PATH"
                fi

                HLS_PATH=$(type -p haskell-language-server)
                HLS_VER=$(haskell-language-server --version | head -n 1)
                if [[ "$HLS_PATH" == *"/nix/store/"* ]]; then
                    echo "✅ HLS:     $HLS_VER"
                    echo "            Path: $HLS_PATH"
                else
                    echo "❌ HLS:     $HLS_VER"
                    echo "            ⚠️  WARNING: Not sourced from Nix!"
                    echo "            Path: $HLS_PATH"
                fi
                echo "--------------------------------------------------------"
                echo "🚧 cabal build"
                cabal build
                echo "--------------------------------------------------------"

                echo "Run 'nvim .' to start an IDE."
                echo "Type 'just' to see available commands."
              '';
            };
          };
        };
    };
}
