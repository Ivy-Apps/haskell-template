{
  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://cache.iog.io"
      "https://cache.numtide.com"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
    allow-import-from-derivation = true;
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts
    , treefmt-nix
    , ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ treefmt-nix.flakeModule ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      perSystem =
        { config
        , pkgs
        , ...
        }:
        let
          projectName = "haskell-app";
          ghcVersion = "ghc9103";
          hlib = pkgs.haskell.lib.compose;

          hpkgs = pkgs.haskell.packages.${ghcVersion}.override {
            overrides = self: super: {
              fmt = hlib.dontCheck super.fmt;
              ${projectName} = hlib.dontCheck (
                hlib.appendConfigureFlags [ "--ghc-option=-optP-Wno-nonportable-include-path" ] (
                  self.callCabal2nix projectName ./. { }
                )
              );
            };
          };

          hgold = hlib.justStaticExecutables hpkgs.hspec-golden;

          sysLibs = [
            pkgs.zlib
            pkgs.xz
          ];

          # Convenience runners that delegate to the appropriate dev shell.
          aiTestRunner = pkgs.writeShellApplication {
            name = "ai-test";
            runtimeInputs = [ pkgs.nix ];
            text = ''
              if [ "$#" -eq 0 ]; then
                nix develop ".#ci" --no-warn-dirty --quiet -c \
                  cabal test -v0 --test-show-details=direct \
                  --test-options="--no-color"
              else
                nix develop ".#ci" --no-warn-dirty --quiet -c \
                  cabal test -v0 --test-show-details=direct \
                  "--test-options=--no-color --match $*"
              fi
            '';
          };

          aiBuildRunner = pkgs.writeShellApplication {
            name = "ai-build";
            runtimeInputs = [ pkgs.nix ];
            text = ''
              nix develop ".#ci" --no-warn-dirty --quiet -c cabal build
            '';
          };

          aiLintRunner = pkgs.writeShellApplication {
            name = "ai-lint";
            runtimeInputs = [ pkgs.nix ];
            text = ''
              nix develop ".#default" --no-warn-dirty --quiet -c hlint .
            '';
          };

        in
        {
          packages.default = hpkgs.${projectName};

          # `nix fmt` / `treefmt`: format Haskell, Cabal, and Nix in one shot.
          treefmt = {
            projectRootFile = "flake.nix";
            programs = {
              fourmolu.enable = true;
              cabal-fmt.enable = true;
              nixfmt.enable = true;
            };
          };

          apps = {
            test = {
              type = "app";
              program = "${aiTestRunner}/bin/ai-test";
            };
            build = {
              type = "app";
              program = "${aiBuildRunner}/bin/ai-build";
            };
            lint = {
              type = "app";
              program = "${aiLintRunner}/bin/ai-lint";
            };
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
                hpkgs.haskell-language-server
                hpkgs.implicit-hie
                pkgs.cabal-install
                pkgs.pkg-config
                pkgs.just
                pkgs.hlint
                pkgs.statix
                pkgs.deadnix
                hgold
                config.treefmt.build.wrapper
              ];

              buildInputs = sysLibs;

              shellHook = ''
                export PATH=$(echo $PATH | tr ':' '\n' | grep -v "ghcup" | tr '\n' ':')
                echo "🔮 Dev Environment started."
              '';
            };
          };
        };
    };
}
