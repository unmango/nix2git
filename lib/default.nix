{ lib }:
let
  inherit (lib) escapeShellArg optional;

  resolve = base: path: if base == null || lib.hasPrefix "/" path then path else "${base}/${path}";

  # git init already creates missing parent directories, so the guard is the
  # only thing standing between a re-run and clobbering an existing repository.
  initMarker = repository: path: if repository.bare then "${path}/HEAD" else "${path}/.git";

  enabledRepositories =
    repositories: lib.filter (repository: repository.enable) (lib.attrValues repositories);

  enabledRemotes = remotes: lib.filter (remote: remote.enable) (lib.attrValues remotes);

  # `remote get-url` exits non-zero for a remote that is not there, and both
  # callers run the script under `set -e`, so the failure has to be swallowed
  # rather than branched on.
  remoteCommand =
    {
      git,
      run,
      path,
    }:
    remote:
    let
      quotedPath = escapeShellArg path;
      quotedName = escapeShellArg remote.name;
      quotedUrl = escapeShellArg remote.url;
      command =
        verb:
        lib.concatStringsSep " " (
          optional (run != "") run
          ++ [
            git
            "-C"
            quotedPath
            "remote"
            verb
            quotedName
            quotedUrl
          ]
        );
    in
    ''
      nix2gitRemoteUrl="$(${git} -C ${quotedPath} remote get-url ${quotedName} 2>/dev/null || true)"
      if [ -z "$nix2gitRemoteUrl" ]; then
        ${command "add"}
      elif [ "$nix2gitRemoteUrl" != ${quotedUrl} ]; then
        ${command "set-url"}
      fi
    '';
in
{
  inherit enabledRemotes enabledRepositories resolve;

  /**
    Render a POSIX shell script that creates each repository that does not exist
    yet and reconciles the remotes of every repository it manages.

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
          marker = escapeShellArg (initMarker repository path);
          remotes = enabledRemotes repository.remotes;
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
          if [ ! -e ${marker} ]; then
            ${command}
          fi
        ''
        # The repository is missing here whenever `run` did not actually run,
        # which is exactly what home-manager's --dry-run does, so the remotes
        # need a guard of their own rather than riding on the one above.
        + lib.optionalString (remotes != [ ]) ''
          if [ -e ${marker} ]; then
          ${lib.concatMapStringsSep "\n" (remoteCommand { inherit git run path; }) remotes}
          unset nix2gitRemoteUrl
          fi
        '';
    in
    lib.concatMapStringsSep "\n" initRepository (enabledRepositories repositories);
}
