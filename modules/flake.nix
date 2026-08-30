{ lib, flake-parts-lib, ... }:
let
  inherit (lib) mkIf mkOption types;
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { config, pkgs, ... }:
    let
      nix2git = import ../lib { inherit lib; };
      cfg = config.nix2git;
    in
    {
      options.nix2git = {
        enable = lib.mkEnableOption "the nix2git repository initializer app";

        package = mkOption {
          type = types.package;
          default = pkgs.git;
          defaultText = lib.literalExpression "pkgs.git";
          description = "The git package used to create repositories.";
        };

        baseDirectory = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "/home/erik";
          description = ''
            Directory relative repository paths are resolved against.
            When `null`, they stay relative to the working directory the app is run from.
          '';
        };

        repositories = mkOption {
          type = types.attrsOf (types.submodule ./repository.nix);
          default = { };
          description = "Repositories the generated app creates, keyed by path.";
        };
      };

      config = mkIf (cfg.enable && cfg.repositories != { }) {
        packages.nix2git-init = pkgs.writeShellApplication {
          name = "nix2git-init";
          runtimeInputs = [ cfg.package ];
          text = nix2git.mkInitScript {
            git = "git";
            inherit (cfg) repositories;
            base = cfg.baseDirectory;
          };
        };

        apps.nix2git-init = {
          type = "app";
          program = lib.getExe config.packages.nix2git-init;
          meta.description = "Create the repositories declared in nix2git.repositories";
        };
      };
    }
  );
}
