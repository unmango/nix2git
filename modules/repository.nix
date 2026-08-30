{ name, lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options = {
    enable = mkOption {
      type = types.bool;
      default = true;
      example = false;
      description = "Whether to manage this repository.";
    };

    path = mkOption {
      type = types.str;
      default = name;
      defaultText = lib.literalMD "the attribute name";
      example = "src/gitlab.com/unmango/nix/2git";
      description = ''
        Location of the working tree, or of the repository itself when {option}`bare` is set.

        A relative path is resolved against a base directory chosen by the consuming
        module: the user's home directory for the home-manager module, and the working
        directory of the generated app for the flake module.
      '';
    };

    bare = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = "Create the repository with `git init --bare`.";
    };

    defaultBranch = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "main";
      description = ''
        Branch to point `HEAD` at on creation. When `null`, git's own
        `init.defaultBranch` configuration decides.
      '';
    };
  };
}
