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

Scaffolding only. Nothing is implemented yet.
