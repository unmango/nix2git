# AGENTS.md

`nix2git` is a Nix library flake that creates and manages git repositories in a user's home directory.
The primary consumer-facing output is a home-manager module; a flake-parts module offers the same behaviour for project-local repositories.

The only implemented feature is initializing empty repositories at a given path.
Anything that mutates an existing repository is out of scope until it is asked for.

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
lib/default.nix          pure functions, takes `lib`, no flake inputs
modules/repository.nix    submodule shared by both consumer modules
modules/home-manager.nix  home-manager module, `nix2git.*`
modules/flake.nix         flake-parts module, `perSystem.nix2git.*`
checks/                   flake-parts module holding the test suite
flake.nix                 inputs and outputs only
.gitlab-ci.yml            CI, a single `nix flake check` job
```

`lib/default.nix` owns the one piece of real logic: `mkInitScript` turns a set of repository
submodule values into a POSIX shell script that runs `git init` for each repository that does
not exist yet. Both consumer modules are thin wrappers that supply a git path, a base directory,
and a command prefix. Keeping the script generation in `lib` is what makes it testable without
evaluating home-manager.

`modules/repository.nix` is a plain submodule so the two consumer modules cannot drift apart on
option names or defaults.

Per the house rule, modules take what they need as module arguments and never reference `inputs`
or `self`. `checks/default.nix` is the deliberate exception, stated in a comment at the top of the
file: it is a flake module, and it has to reach for `home-manager` and `flake-parts` to evaluate
the consumer modules the way a downstream flake would.

The checks cover three layers: the rendered script actually creating repositories in a sandbox,
the home-manager module producing the right activation text, and the flake-parts module producing
a working app via `evalFlakeModule`.

## Conventions

Prefer `inherit (foo) bar;` over `bar = foo.bar;`.

Idempotence is the contract. Every effectful command sits behind a guard that checks for
`.git` (or `HEAD`, when bare) so a re-run is a no-op.

Paths reaching the shell go through `lib.escapeShellArg`.
