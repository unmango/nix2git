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
      description = ''
        Whether to manage this remote.

        Setting this to `false` stops nix2git managing the remote. It does not
        remove a remote already present in the repository, for the same reason
        nix2git never deletes a repository.
      '';
    };

    name = mkOption {
      type = types.str;
      default = name;
      defaultText = lib.literalMD "the attribute name";
      example = "upstream";
      description = "Name the remote is registered under, as `git remote add` takes it.";
    };

    url = mkOption {
      type = types.str;
      example = "git@github.com:unmango/nix2git.git";
      description = ''
        URL the remote points at.

        The URL is reconciled on every run: a missing remote is added, and one
        pointing somewhere else is rewritten.
      '';
    };
  };
}
