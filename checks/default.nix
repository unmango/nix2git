# Checks are the one place outside flake.nix that reach for `inputs`, because
# they exercise the modules against home-manager and flake-parts themselves.
{ inputs, self, ... }:
{
  perSystem =
    { lib, pkgs, ... }:
    let
      nix2git = self.lib;

      # evalFlakeModule instead of a fixture flake: it exercises the real
      # perSystem options without needing a second flake in the store.
      downstream =
        inputs.flake-parts.lib.evalFlakeModule
          {
            inputs = {
              inherit (inputs) nixpkgs;
              self = {
                inputs = { inherit (inputs) nixpkgs; };
              };
            };
          }
          {
            systems = [ pkgs.stdenv.hostPlatform.system ];
            imports = [ self.flakeModules.nix2git ];
            perSystem = _: {
              nix2git = {
                enable = true;
                repositories = {
                  demo = { };
                  "nested/demo.git".bare = true;
                };
              };
            };
          };

      home = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          self.homeModules.nix2git
          {
            home = {
              username = "nix2git";
              homeDirectory = "/home/nix2git";
              stateVersion = "25.05";
            };

            nix2git = {
              enable = true;
              repositories = {
                "src/example" = { };
                "mirrors/example.git" = {
                  bare = true;
                  defaultBranch = "trunk";
                };
                "src/disabled".enable = false;
              };
            };
          }
        ];
      };
    in
    {
      checks = {
        # The generated script must create every repository and leave an
        # existing one alone.
        init-script =
          pkgs.runCommand "nix2git-init-script"
            {
              nativeBuildInputs = [ pkgs.git ];
            }
            ''
              export HOME="$PWD"
              mkdir -p existing
              git init existing
              touch existing/sentinel

              ${nix2git.mkInitScript {
                git = "git";
                repositories = {
                  fresh = {
                    enable = true;
                    path = "fresh";
                    bare = false;
                    defaultBranch = "trunk";
                  };
                  mirror = {
                    enable = true;
                    path = "nested/mirror.git";
                    bare = true;
                    defaultBranch = null;
                  };
                  existing = {
                    enable = true;
                    path = "existing";
                    bare = false;
                    defaultBranch = null;
                  };
                  skipped = {
                    enable = false;
                    path = "skipped";
                    bare = false;
                    defaultBranch = null;
                  };
                };
              }}

              [ -d fresh/.git ]
              [ "$(git -C fresh symbolic-ref --short HEAD)" = trunk ]
              [ -f nested/mirror.git/HEAD ]
              [ ! -e skipped ]
              [ -f existing/sentinel ]

              touch "$out"
            '';

        # The flake module's generated app has to create the same repositories
        # relative to the directory it is run from.
        flake-module =
          pkgs.runCommand "nix2git-flake-module"
            {
              nativeBuildInputs = [ pkgs.git ];
            }
            ''
              mkdir -p run && cd run
              ${lib.getExe downstream.config.flake.packages.${pkgs.stdenv.hostPlatform.system}.nix2git-init}

              [ -d demo/.git ]
              [ -f nested/demo.git/HEAD ]

              touch "$out"
            '';

        # The home-manager module has to produce an activation entry that
        # resolves relative paths against the home directory and honours enable.
        home-manager-module =
          let
            script = home.config.home.activation.nix2git.data;
          in
          pkgs.runCommand "nix2git-home-manager-module" { } ''
            script=${lib.escapeShellArg script}
            case "$script" in
              *"init /home/nix2git/src/example"*) ;;
              *) echo "missing src/example init" >&2; exit 1 ;;
            esac
            case "$script" in
              *"--bare --initial-branch=trunk /home/nix2git/mirrors/example.git"*) ;;
              *) echo "missing bare mirror init" >&2; exit 1 ;;
            esac
            case "$script" in
              *src/disabled*) echo "disabled repository was emitted" >&2; exit 1 ;;
            esac

            touch "$out"
          '';
      };
    };
}
