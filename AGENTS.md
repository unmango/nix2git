# AGENTS.md

`nix2git` is a Nix library flake that creates and manages git repositories in a user's home directory.
The primary consumer-facing output is a home-manager module; a flake-parts module offers the same behaviour for project-local repositories.

The implemented features are initializing empty repositories at a given path and reconciling their remotes.
Remotes are the one thing nix2git changes in a repository it did not create: a declared remote that is
missing is added, and one pointing elsewhere is rewritten, on every run rather than only at creation.
Everything else about a repository it finds in place is left alone until it is asked for.

nix2git never deletes a repository, and that is a deliberate limit rather than a missing feature.
`files.nix` in home-manager only removes a path it can prove it created, meaning a symlink into a
`-home-manager-files` store path. No such proof exists for a git repository, and its contents exist
nowhere else, so removal warns and stops there.

The canonical remote is `git@github.com:unmango/nix2git.git`, so CI lives in
`.github/workflows/ci.yml` and renovate reads `renovate.json` at the repository root.

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
modules/remote.nix        submodule for one remote, nested under a repository
modules/home-manager.nix  home-manager module, `nix2git.*`
modules/flake.nix         flake-parts module, `perSystem.nix2git.*`
checks/                   flake-parts module holding the test suite
flake.nix                 inputs and outputs only
.github/workflows/ci.yml  CI, a single `nix flake check` job
```

`lib/default.nix` owns the one piece of real logic: `mkInitScript` turns a set of repository
submodule values into a POSIX shell script that runs `git init` for each repository that does
not exist yet, and then reconciles the remotes of every repository it manages.
The remote block sits behind its own `[ -e <marker> ]` guard rather than inside the init guard,
because under `--dry-run` the `git init` never actually ran and the path is not there to talk to. Both consumer modules are thin wrappers that supply a git path, a base directory,
and a command prefix. Keeping the script generation in `lib` is what makes it testable without
evaluating home-manager.

`modules/repository.nix` is a plain submodule so the two consumer modules cannot drift apart on
option names or defaults.

Per the house rule, modules take what they need as module arguments and never reference `inputs`
or `self`. `checks/default.nix` is the deliberate exception, stated in a comment at the top of the
file: it is a flake module, and it has to reach for `home-manager` and `flake-parts` to evaluate
the consumer modules the way a downstream flake would.

Removal is detected by diffing generations, the same way `systemd.nix` and `misc/dconf.nix` do it.
The set of declared repositories is written through `xdg.stateFile`, which gets `files.nix` to place
a copy in the generation; the `nix2gitOrphans` activation entry then reads
`$oldGenPath/home-files/<target>` and compares it against `$newGenPath`. `$oldGenPath` is unset on a
first activation, so the entry has to tolerate its absence.

The flake-parts module has no equivalent. There is no generation to diff against, so removal is
invisible to it by construction.

The checks cover five layers: the rendered script actually creating repositories in a sandbox,
the same script adding and rewriting remotes on repositories it did not create, the home-manager
module producing the right activation text, the flake-parts module producing a working app via
`evalFlakeModule`, and the orphan script warning about exactly the repositories that were dropped
and still exist.

## Conventions

Prefer `inherit (foo) bar;` over `bar = foo.bar;`.

Idempotence is the contract. Every effectful command sits behind a guard that checks for
`.git` (or `HEAD`, when bare) so a re-run is a no-op.

Paths reaching the shell go through `lib.escapeShellArg`.
