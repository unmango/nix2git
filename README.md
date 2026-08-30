# nix2git

Nix support for initializing and managing git repositories in a user's home directory.

The primary output is a home-manager module.
A flake-parts module covers the same ground for repositories that belong to a project rather than a user.

## Usage

```nix
{
  inputs.nix2git.url = "gitlab:unmango/nix%2F2git";
}
```

The subgroup separator is percent-encoded because a flake reference reads the
second path segment as the repository name.

## Status

The only implemented feature is creating empty repositories at a given path.
A repository that already exists is left alone; nix2git never rewrites history, changes remotes, or fetches.

## home-manager

```nix
{
  imports = [ inputs.nix2git.homeModules.nix2git ];

  nix2git = {
    enable = true;

    repositories = {
      "src/gitlab.com/unmango/nix/2git" = { };
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

## Library

`nix2git.lib.mkInitScript` renders the shell script both modules run, and is usable on its own.

```nix
nix2git.lib.mkInitScript {
  git = "git";
  base = "/home/erik";
  repositories = config.nix2git.repositories;
}
```
