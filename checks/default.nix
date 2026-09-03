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
                  demo.remotes.origin.url = "https://example.invalid/demo.git";
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
                "src/example".remotes = {
                  origin.url = "git@github.com:unmango/example.git";
                  ignored = {
                    enable = false;
                    url = "https://example.invalid/ignored.git";
                  };
                };
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
                    remotes = { };
                  };
                  mirror = {
                    enable = true;
                    path = "nested/mirror.git";
                    bare = true;
                    defaultBranch = null;
                    remotes = { };
                  };
                  existing = {
                    enable = true;
                    path = "existing";
                    bare = false;
                    defaultBranch = null;
                    remotes = { };
                  };
                  skipped = {
                    enable = false;
                    path = "skipped";
                    bare = false;
                    defaultBranch = null;
                    remotes = { };
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

        # Remotes are reconciled rather than created, so the script has to reach
        # a repository it did not make, and has to be safe to run twice.
        remotes =
          let
            remote = url: {
              origin = {
                enable = true;
                name = "origin";
                inherit url;
              };
            };

            repository = path: remotes: {
              enable = true;
              bare = false;
              defaultBranch = null;
              inherit path remotes;
            };

            script = nix2git.mkInitScript {
              git = "git";
              repositories = {
                fresh = repository "fresh" (remote "https://example.invalid/fresh.git");
                adopted = repository "adopted" (remote "https://example.invalid/adopted.git");
                stale = repository "stale" (remote "https://example.invalid/stale.git");
                disabled = repository "disabled" {
                  origin = {
                    enable = false;
                    name = "origin";
                    url = "https://example.invalid/disabled.git";
                  };
                };
              };
            };

            assertions = ''
              [ "$(git -C fresh remote get-url origin)" = https://example.invalid/fresh.git ]
              [ "$(git -C adopted remote get-url origin)" = https://example.invalid/adopted.git ]
              [ "$(git -C stale remote get-url origin)" = https://example.invalid/stale.git ]
              [ "$(git -C stale remote)" = origin ]
              [ -z "$(git -C disabled remote)" ]
            '';
          in
          pkgs.runCommand "nix2git-remotes"
            {
              nativeBuildInputs = [ pkgs.git ];
            }
            ''
              export HOME="$PWD"

              # adopted and stale exist already, so the script only ever touches
              # their remotes.
              git init adopted
              git init stale
              git -C stale remote add origin https://example.invalid/outdated.git

              ${script}

              ${assertions}

              # Idempotence: a second run leaves everything as it was.
              ${script}

              ${assertions}

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
              [ "$(git -C demo remote get-url origin)" = https://example.invalid/demo.git ]

              touch "$out"
            '';

        # Removal is warn-only: the script must name a dropped repository that
        # still exists, and stay quiet about everything else.
        orphans =
          let
            manifest = home.config.xdg.stateFile."nix2git/repositories";
            target = manifest.target;
            expected = pkgs.writeText "expected-manifest" ''
              /home/nix2git/mirrors/example.git
              /home/nix2git/src/example
            '';
          in
          pkgs.runCommand "nix2git-orphans"
            {
              nativeBuildInputs = [ pkgs.gnugrep ];
            }
            ''
              # The manifest lists every enabled repository resolved against the
              # home directory, sorted, and nothing else.
              diff -u ${expected} ${manifest.source}

              mkdir -p \
                old/home-files/${builtins.dirOf target} \
                new/home-files/${builtins.dirOf target} \
                repos/kept \
                repos/dropped

              printf '%s\n' "$PWD/repos/kept" "$PWD/repos/dropped" "$PWD/repos/vanished" \
                > old/home-files/${target}
              printf '%s\n' "$PWD/repos/kept" > new/home-files/${target}

              oldGenPath="$PWD/old"
              newGenPath="$PWD/new"
              warnEcho() { echo "$*"; }

              orphans() {
              ${home.config.home.activation.nix2gitOrphans.data}
              }
              orphans > warnings

              grep -qF "$PWD/repos/dropped" warnings
              ! grep -qF "repos/kept" warnings
              ! grep -qF "repos/vanished" warnings
              [ "$(wc -l < warnings)" -eq 1 ]

              # A first activation has no previous generation to compare against.
              unset oldGenPath
              orphans > first-run
              [ ! -s first-run ]

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
            case "$script" in
              *"remote add origin git@github.com:unmango/example.git"*) ;;
              *) echo "missing origin remote" >&2; exit 1 ;;
            esac
            case "$script" in
              *ignored*) echo "disabled remote was emitted" >&2; exit 1 ;;
            esac

            touch "$out"
          '';
      };
    };
}
