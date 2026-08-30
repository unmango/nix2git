# AGENTS.md

`nix2git` is a Nix library flake that creates and manages git repositories in a user's home directory.
The primary consumer-facing output is a home-manager module; a flake-parts module offers the same behaviour for project-local repositories.

The canonical remote is `git@gitlab.com:unmango/nix/2git.git`, so CI lives in `.gitlab-ci.yml`
and renovate reads `renovate.json` at the repository root. There is no GitHub mirror;
`.github/` holds only the Copilot instructions pointer.

## Commands

`nix flake check` is the whole test suite, and the only thing CI runs. The `Makefile` wraps it.

```
make check     # nix flake check
make fmt       # nix fmt (treefmt + nixfmt)
make update    # nix flake update
```

Run `nix fmt` before committing; `checks.treefmt` fails the build otherwise.

## Architecture

```
flake.nix                 inputs and outputs only
.gitlab-ci.yml            CI, a single `nix flake check` job
```

Scaffolded from the `default` template of `github:UnstoppableMango/nix`, with the
template's GitHub Actions workflow swapped for `.gitlab-ci.yml`.

## Conventions

Prefer `inherit (foo) bar;` over `bar = foo.bar;`.
