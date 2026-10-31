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
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # The architecture checker behind `just deslop`: its released binary, not a
    # source build.
    deslop = {
      url = "github:Ivy-Apps/deslop";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
    # sydtest-mutation, behind `checks.<system>.mutation` only. Not on Hackage at
    # our index-state and not in nixpkgs, so its flake is the source of truth.
    # Pinned to a rev because it moves weekly.
    sydtest = {
      url = "github:NorfairKing/sydtest/6ba5347b0f1ec27cc912bb45ca98e0e4f24343ea";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      flake-parts,
      treefmt-nix,
      ...
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
        {
          config,
          inputs',
          pkgs,
          ...
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
          # They compile with the Justfile's `parallel` -j4, for the same
          # reasons; keep the two in step.
          parallel = "--ghc-options=-j4";

          aiTestRunner = pkgs.writeShellApplication {
            name = "ai-test";
            runtimeInputs = [ pkgs.nix ];
            text = ''
              if [ "$#" -eq 0 ]; then
                nix develop ".#ci" --no-warn-dirty --quiet -c \
                  cabal test ${parallel} -v0 --test-show-details=direct \
                  --test-options="--no-color"
              else
                nix develop ".#ci" --no-warn-dirty --quiet -c \
                  cabal test ${parallel} -v0 --test-show-details=direct \
                  "--test-options=--no-color --match $*"
              fi
            '';
          };

          aiBuildRunner = pkgs.writeShellApplication {
            name = "ai-build";
            runtimeInputs = [ pkgs.nix ];
            text = ''
              nix develop ".#ci" --no-warn-dirty --quiet -c cabal build ${parallel}
            '';
          };

          # hlint and the spell checker, through the lean `ci` shell so the
          # cheapest check never realises HLS. See docs/adr/0002.
          aiLintRunner = pkgs.writeShellApplication {
            name = "ai-lint";
            runtimeInputs = [ pkgs.nix ];
            text = ''
              nix develop ".#ci" --no-warn-dirty --quiet -c just lint typos
            '';
          };

          aiUpdateGoldenRunner = pkgs.writeShellApplication {
            name = "ai-update-golden";
            # `hgold` is carried here rather than added to the `ci` shell,
            # because CI never re-records goldens and would realise the closure
            # for nothing. `nix develop` inherits the caller's PATH, which is
            # what puts it in front of the recipe.
            runtimeInputs = [
              pkgs.nix
              hgold
            ];
            text = ''
              nix develop ".#ci" --no-warn-dirty --quiet -c just update-golden
            '';
          };

          # The ghcid daemon behind `nix run .#quick-typecheck` and
          # `nix run .#quick-test`, and the tool `just stop-ghcid` uses to
          # retire every session on the machine.
          ghcidTools = import ./nix/ghcid {
            inherit pkgs projectName parallel;
          };

          # Everything a `just` recipe that CI calls needs, and nothing else.
          # Shared by both shells so a recipe never works in one and not the
          # other.
          checkTools = [
            pkgs.just
            pkgs.hlint
            pkgs.typos
            pkgs.statix
            pkgs.deadnix
            # Behind `just lint-actions`. shellcheck is optional to actionlint
            # but not decorative: with it absent from PATH, actionlint silently
            # skips every `run:` block, which is where a workflow keeps its logic.
            pkgs.actionlint
            pkgs.shellcheck
            # Behind `just zizmor`.
            pkgs.zizmor
            # `just update-golden` stages the re-recorded snapshots.
            pkgs.git
            config.treefmt.build.wrapper
          ]
          # Behind `just deslop`. deslop releases a binary for every system here
          # but x86_64-darwin, whose shells go without it.
          ++ pkgs.lib.optional (inputs'.deslop.packages ? deslop) inputs'.deslop.packages.deslop;

        in
        {
          packages.default = hpkgs.${projectName};

          checks.mutation = import ./nix/mutation.nix {
            inherit
              pkgs
              hpkgs
              projectName
              ;
            inherit (inputs) sydtest;
          };

          # `nix fmt` / `treefmt`: format Haskell, Cabal, and Nix in one shot.
          treefmt = {
            projectRootFile = "flake.nix";
            programs = {
              fourmolu.enable = true;
              cabal-fmt.enable = true;
              nixfmt.enable = true;
              # Reads the committed `.typos.toml`. Pinned through flake.lock,
              # like `just typos`, because the dictionary grows every release.
              typos.enable = true;
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
            quick-typecheck = {
              type = "app";
              program = "${ghcidTools.quickTypecheck}/bin/ai-quick-typecheck";
            };
            quick-test = {
              type = "app";
              program = "${ghcidTools.quickTest}/bin/ai-quick-test";
            };
            update-golden = {
              type = "app";
              program = "${aiUpdateGoldenRunner}/bin/ai-update-golden";
            };
          };

          devShells = {
            ci = hpkgs.shellFor {
              packages = p: [ p.${projectName} ];
              withHoogle = false;

              # CI drives every check through this lean shell instead of the
              # HLS-heavy `default` one. See docs/adr/0002.
              nativeBuildInputs = [
                pkgs.pkg-config
                pkgs.cabal-install
              ]
              ++ checkTools;

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
                hgold
                # For an interactive ghcid TUI; the agent-facing app reaches
                # ghcid by store path and does not need it here. Kept out of the
                # `ci` shell so CI never realises this closure.
                pkgs.ghcid
                # Behind `just quick-typecheck`, `just quick-test` and
                # `just stop-ghcid`. The apps under `nix run` are the same
                # programs; having them here lets the recipes call them
                # directly, as every other recipe calls its tool, and skips a
                # flake evaluation per check.
                ghcidTools.quickTypecheck
                ghcidTools.quickTest
                ghcidTools.stop
              ]
              ++ checkTools;

              buildInputs = sysLibs;

              shellHook = ''
                export PATH=$(echo $PATH | tr ':' '\n' | grep -v "ghcup" | tr '\n' ':')
                # Deliberately does NOT warm the ghcid daemon. direnv waits on
                # this hook's process group, so spawning the session here would
                # hang every `cd` into the project behind a callCabal2nix IFD
                # evaluation and a full repl load. The first
                # `nix run .#quick-typecheck` pays that cost instead.
                echo "🔮 Dev Environment started."
              '';
            };
          };
        };
    };
}
