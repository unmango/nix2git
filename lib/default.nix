{ lib }:
let
  inherit (lib) escapeShellArg optional;

  resolve = base: path: if base == null || lib.hasPrefix "/" path then path else "${base}/${path}";

  # git init already creates missing parent directories, so the guard is the
  # only thing standing between a re-run and clobbering an existing repository.
  initMarker = repository: path: if repository.bare then "${path}/HEAD" else "${path}/.git";

  enabledRepositories =
    repositories: lib.filter (repository: repository.enable) (lib.attrValues repositories);
in
{
  inherit enabledRepositories resolve;

  /**
    Render a POSIX shell script that creates each repository that does not exist yet.

    # Inputs

    `git`
    : Path to the git executable.

    `repositories`
    : Attribute set of repository submodule values, keyed by name.

    `base`
    : Directory relative paths are resolved against, or `null` to leave them relative.

    `run`
    : Prefix placed in front of every effectful command, for example home-manager's `$DRY_RUN_CMD`.
  */
  mkInitScript =
    {
      git,
      repositories,
      base ? null,
      run ? "",
    }:
    let
      initRepository =
        repository:
        let
          path = resolve base repository.path;
          flags =
            optional repository.bare "--bare"
            ++ optional (
              repository.defaultBranch != null
            ) "--initial-branch=${escapeShellArg repository.defaultBranch}";
          command = lib.concatStringsSep " " (
            optional (run != "") run
            ++ [
              git
              "init"
            ]
            ++ flags
            ++ [ (escapeShellArg path) ]
          );
        in
        ''
          if [ ! -e ${escapeShellArg (initMarker repository path)} ]; then
            ${command}
          fi
        '';
    in
    lib.concatMapStringsSep "\n" initRepository (enabledRepositories repositories);
}
