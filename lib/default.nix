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
      fetchKey = escapeShellArg "remote.${remote.name}.fetch";
      command =
        args:
        lib.concatStringsSep " " (
          optional (run != "") run
          ++ [
            git
            "-C"
            quotedPath
          ]
          ++ args
        );
    in
    # `remote add` writes the default refspec, `set-url` does not, so a remote
    # found with only a URL needs one added.
    ''
      nix2gitRemoteUrl="$(${git} -C ${quotedPath} remote get-url ${quotedName} 2>/dev/null || true)"
      if [ -z "$nix2gitRemoteUrl" ]; then
        ${command [
          "remote"
          "add"
          quotedName
          quotedUrl
        ]}
      else
        if [ "$nix2gitRemoteUrl" != ${quotedUrl} ]; then
          ${command [
            "remote"
            "set-url"
            quotedName
            quotedUrl
          ]}
        fi
        if ! ${git} -C ${quotedPath} config --get-all ${fetchKey} >/dev/null; then
          ${command [
            "config"
            "--add"
            fetchKey
            (escapeShellArg "+refs/heads/*:refs/remotes/${remote.name}/*")
          ]}
        fi
      fi
    '';

  # Only while HEAD is unborn when no branch is declared: once a repository
  # has commits, whatever branch is checked out is the user's business.
  trackingCommand =
    {
      git,
      run,
      path,
    }:
    repository:
    let
      quotedPath = escapeShellArg path;
      config =
        args:
        lib.concatStringsSep " " (
          optional (run != "") run
          ++ [
            git
            "-C"
            quotedPath
            "config"
          ]
          ++ args
        );
    in
    (
      if repository.defaultBranch != null then
        ''
          nix2gitBranch=${escapeShellArg repository.defaultBranch}
        ''
      else
        ''
          nix2gitBranch="$(${git} -C ${quotedPath} symbolic-ref --quiet --short HEAD || true)"
          if ${git} -C ${quotedPath} rev-parse --quiet --verify HEAD >/dev/null; then
            nix2gitBranch=
          fi
        ''
    )
    + ''
      if [ -n "$nix2gitBranch" ] \
        && ! ${git} -C ${quotedPath} config --get-all "branch.$nix2gitBranch.remote" >/dev/null; then
        ${config [
          ''"branch.$nix2gitBranch.remote"''
          (escapeShellArg repository.upstream)
        ]}
        ${config [
          ''"branch.$nix2gitBranch.merge"''
          ''"refs/heads/$nix2gitBranch"''
        ]}
      fi
    '';
in
{
  inherit enabledRemotes enabledRepositories resolve;

  /**
    Render a POSIX shell script that creates each repository that does not exist
    yet, reconciles the remotes of every repository it manages, and points the
    branch `git pull` uses at the repository's `upstream` remote.

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
          tracking = !repository.bare && repository.upstream or null != null;
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
        + lib.optionalString (remotes != [ ] || tracking) ''
          if [ -e ${marker} ]; then
          ${lib.concatMapStringsSep "\n" (remoteCommand { inherit git run path; }) remotes}
          ${lib.optionalString tracking (trackingCommand { inherit git run path; } repository)}
          unset nix2gitRemoteUrl nix2gitBranch
          fi
        '';
    in
    lib.concatMapStringsSep "\n" initRepository (enabledRepositories repositories);
}
