# nix2git

Nix support for initializing and managing git repositories in a user's home directory.

The primary output is a home-manager module.
A flake-parts module covers the same ground for repositories that belong to a project rather than a user.

## Usage

```nix
{
  inputs.nix2git.url = "github:unmango/nix2git";
}
```

## Status

The implemented features are creating empty repositories at a given path and keeping their remotes in sync.
Everything else about a repository that already exists is left alone; nix2git never rewrites history, deletes, or fetches.

## home-manager

```nix
{
  imports = [ inputs.nix2git.homeModules.nix2git ];

  nix2git = {
    enable = true;

    repositories = {
      "src/github.com/unmango/nix2git".remotes = {
        origin.url = "git@github.com:unmango/nix2git.git";
      };
      "mirrors/dotfiles.git" = {
        bare = true;
        defaultBranch = "main";
      };
    };
  };
}
```

Relative paths are resolved against `home.homeDirectory`.
The repositories are created by a home-manager activation script that runs after `writeBoundary`, so `home-manager switch --dry-run` reports what it would do without touching the filesystem.

### Removal

nix2git never deletes a repository.
It cannot prove it created the one it finds at a path, and a repository's contents exist nowhere else.

Removing an entry from `repositories` instead prints a warning on the next activation, naming the path so it does not silently become unmanaged.

```
nix2git: /home/erik/src/old-project is no longer declared but still exists. Delete it yourself if you no longer want it.
```

Set `nix2git.orphans = "ignore"` to turn the warning off.

The list of declared repositories is written to `$XDG_STATE_HOME/nix2git/repositories`, which is how activation knows what the previous generation declared.

## flake-parts

```nix
{
  imports = [ inputs.nix2git.flakeModules.nix2git ];

  perSystem = {
    nix2git = {
      enable = true;
      repositories.fixtures = { };
    };
  };
}
```

This adds `packages.nix2git-init` and `apps.nix2git-init`.
Relative paths are resolved against the working directory the app is run from, unless `nix2git.baseDirectory` is set.

## Options

Each entry in `repositories` accepts:

| Option          | Type              | Default            | Meaning                                            |
| --------------- | ----------------- | ------------------ | -------------------------------------------------- |
| `enable`        | bool              | `true`             | Whether to manage this repository                   |
| `path`          | str               | the attribute name | Working tree, or the repository itself when `bare`  |
| `bare`          | bool              | `false`            | Create with `git init --bare`                       |
| `defaultBranch` | null or str       | `null`             | Passed as `--initial-branch`                        |
| `remotes`       | attrs of remote   | `{ }`              | Remotes to register, keyed by name                  |

Each entry in `remotes` accepts:

| Option   | Type | Default            | Meaning                        |
| -------- | ---- | ------------------ | ------------------------------ |
| `enable` | bool | `true`             | Whether to manage this remote  |
| `name`   | str  | the attribute name | Name the remote is registered under |
| `url`    | str  | required           | URL the remote points at       |

Remotes are reconciled on every run, not only when the repository is created.
A declared remote that is missing is added, and one pointing somewhere else is rewritten.
A remote nix2git does not declare is left alone, and disabling one does not remove it.

## Library

`nix2git.lib.mkInitScript` renders the shell script both modules run, and is usable on its own.

```nix
nix2git.lib.mkInitScript {
  git = "git";
  base = "/home/erik";
  repositories = config.nix2git.repositories;
}
```
