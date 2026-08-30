{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf mkOption types;

  nix2git = import ../lib { inherit lib; };
  cfg = config.nix2git;
in
{
  options.nix2git = {
    enable = lib.mkEnableOption "nix2git managed git repositories";

    package = mkOption {
      type = types.package;
      default = pkgs.git;
      defaultText = lib.literalExpression "pkgs.git";
      description = "The git package used to create repositories.";
    };

    repositories = mkOption {
      type = types.attrsOf (types.submodule ./repository.nix);
      default = { };
      example = lib.literalExpression ''
        {
          "src/gitlab.com/unmango/nix/2git" = { };
          "mirrors/dotfiles.git".bare = true;
        }
      '';
      description = ''
        Repositories to create in the user's home directory, keyed by path.

        A repository is only created when it does not already exist; nix2git
        never touches the contents of a repository it finds in place.
      '';
    };
  };

  config = mkIf (cfg.enable && cfg.repositories != { }) {
    home.activation.nix2git = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      nix2git.mkInitScript {
        git = "${cfg.package}/bin/git";
        base = config.home.homeDirectory;
        run = "$DRY_RUN_CMD";
        inherit (cfg) repositories;
      }
    );
  };
}
