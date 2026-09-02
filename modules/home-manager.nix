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

  # The manifest is written through xdg.stateFile so that files.nix places a
  # copy in the generation, which is what makes `$oldGenPath` comparable to
  # `$newGenPath` at activation. systemd.nix and dconf.nix read their own
  # previous state out of the generation the same way.
  manifestName = "nix2git/repositories";
  manifest = config.xdg.stateFile.${manifestName};

  declared = map (repository: nix2git.resolve config.home.homeDirectory repository.path) (
    nix2git.enabledRepositories cfg.repositories
  );
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

    orphans = mkOption {
      type = types.enum [
        "warn"
        "ignore"
      ];
      default = "warn";
      example = "ignore";
      description = ''
        What to do about a repository the previous generation declared and this
        one does not.

        `warn` prints the path of every such repository that still exists on disk.
        `ignore` says nothing.

        nix2git never deletes a repository. It cannot prove it created the one it
        finds at a path, and a repository's contents exist nowhere else, so
        removal is left to the user.
      '';
    };

    repositories = mkOption {
      type = types.attrsOf (types.submodule ./repository.nix);
      default = { };
      example = lib.literalExpression ''
        {
          "src/github.com/unmango/nix2git" = { };
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

  config = mkIf cfg.enable {
    xdg.stateFile.${manifestName}.text = lib.concatLines (lib.sort (a: b: a < b) declared);

    home.activation = {
      nix2git = mkIf (cfg.repositories != { }) (
        lib.hm.dag.entryAfter [ "writeBoundary" ] (
          nix2git.mkInitScript {
            git = "${cfg.package}/bin/git";
            base = config.home.homeDirectory;
            run = "$DRY_RUN_CMD";
            inherit (cfg) repositories;
          }
        )
      );

      # After linkGeneration, so the manifest this run is compared against is
      # the one already on disk rather than one this entry raced into place.
      nix2gitOrphans = mkIf (cfg.orphans == "warn") (
        lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          if [[ -v oldGenPath && -e "$oldGenPath/home-files/${manifest.target}" ]]; then
            while IFS= read -r nix2gitRepository; do
              if [[ -z "$nix2gitRepository" ]]; then
                continue
              fi

              if grep -qxF -- "$nix2gitRepository" \
                  "$newGenPath/home-files/${manifest.target}"; then
                continue
              fi

              if [[ ! -e "$nix2gitRepository" ]]; then
                continue
              fi

              warnEcho "nix2git: $nix2gitRepository is no longer declared but still exists. Delete it yourself if you no longer want it."
            done < "$oldGenPath/home-files/${manifest.target}"
          fi

          unset nix2gitRepository
        ''
      );
    };
  };
}
