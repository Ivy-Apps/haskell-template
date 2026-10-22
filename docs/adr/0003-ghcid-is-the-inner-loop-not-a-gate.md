# 3. ghcid is the inner loop, not a gate

Date: 2026-10-22

## Status

Accepted

## Context

AI agents iterate by editing a module and then running `nix run .#build`,
filtering the output for `error`. The Nix wrappers are not what makes that
slow: entering the `ci` shell is cheap. The cost is GHC recompiling and
relinking, several seconds per edit even in a small project and growing with
it.

A warm `ghci` session does not pay that cost. A `cabal repl` holding the whole
project in memory answers "does this typecheck" in a fraction of a second,
because it recompiles only the changed module and its dependents to bytecode.
`ghcid` is the standard way to keep such a session alive and, importantly for a
non-interactive agent, its `--outputfile` writes the current verdict to a file
that can be read as ordinary text rather than scraped from a TUI.

## Decision

`nix run .#quick-typecheck` is the inner loop. It answers exactly one question,
"does the project typecheck", and it is never sufficient on its own.
`nix run .#build`, `nix run .#test` and `nix run .#lint` remain the gates, and
`CLAUDE.md` says so at the point where the command is introduced.

The implementation lives in `nix/ghcid.nix`, parameterised by the project name
(from which the components, cabal files and cache namespace default). It is
three small programs composed in Nix rather than one script with a subcommand
dispatcher: `ai-quick-typecheck`, `ghcid-stop` and an internal watchdog. What
the session covers, which files force a restart, and every timing constant are
Nix values, so the shell is left with control flow and nothing else.

`ghcid-stop` deliberately retires *every* daemon on the machine and deletes the
whole cache namespace. Reaching for it means wanting the memory back, not
wanting to reason about which worktree owns which session.

Concurrent callers are made safe by an atomic `mkdir` lock around the spawn.
Without it, several terminals asking at once each observe no daemon and each
start one. A lock whose owner died mid-spawn is reclaimed by taking possession
first with `mv`, which is atomic, so two callers that both saw the same dead
owner cannot both spawn.

The session is started lazily by the first check, not warmed on shell entry:
direnv waits on the `shellHook`'s process group, so warming there would hang
every `cd` into the project behind a `callCabal2nix` evaluation and a full repl
load.

The session loads the library, the executable and the tests. The benchmark is
left out: agents rarely touch it, and CI compiles it (`just build-bench`), so a
change that breaks it still fails the pull request.

### Why `--restart` is not optional

`ghcid` does not notice changes to the `.cabal` file. With a new module
registered in `exposed-modules` and a deliberate type error inside it, the
outputfile keeps reading `All good` indefinitely. Every new module must be
registered in the `.cabal` file, so that is a routine edit, and the failure is
silent and confident. `--restart` on the cabal files fixes it with a full
session restart.

`--restart` cannot cover `flake.nix`, because the daemon runs inside a dev shell
fixed when it spawned. `quick-typecheck` compares `flake.nix` and `flake.lock`
against the daemon's start stamp and respawns instead of reloading.

### Why stopping walks the process tree

ghcid owns a `cabal repl`, which owns a `ghc --interactive` holding hundreds of
MB. That GHC process is invoked through an `@response-file`, so its command line
contains nothing identifying. `pkill`ing ghcid alone leaves it orphaned and
permanently unfindable, and each restart strands another one. `kill_matching`
therefore resolves the ghcid process to its full descendant tree, collecting
every PID before signalling any, and follows `TERM` with `KILL`.

### Why the freshness wait exists

The dangerous failure is not latency, it is a stale verdict. If the daemon was
never started, died, or belongs to another worktree, the outputfile may still
say `All good`. `quick-typecheck` therefore refuses to report until no `.hs` or
cabal file is newer than the outputfile, and gives up loudly rather than
reporting anything at all. Stale green is made structurally impossible rather
than merely unlikely.

The wait ends early, with exit code 2 and a reason, when no answer is coming:
the daemon exited (the end of its log is printed), or it is alive but has not
rewritten its verdict while an input is still newer, which is what an
unregistered new module looks like.

`coreutils` and `findutils` are pinned in the scripts' `runtimeInputs`: inside
the dev shell a GNU `stat` shadows the BSD one on macOS, and the freshness check
is the one thing standing between an agent and a false green.

### Why the daemon's state is not in the worktree

An outputfile whose path lies under the root ghcid watches makes it re-trigger
on its own writes, costing most of the speedup. State therefore lives in
`$XDG_CACHE_HOME/<project>-ghcid/<hash of worktree path>`. Isolation between
worktrees is preserved by the key, nothing is added to `.gitignore`, and
`quick-typecheck` prints the outputfile path when it truncates.

## Rejected alternatives

- **Letting ghcid run the tests** via `--test`. Interpreted `hspec` can diverge
  from the compiled suite, and it would sharpen the incentive to skip the real
  gate. `nix run .#test` stays the only answer on tests.
- **Agent-managed lifecycle**, with documented start, stop and status commands.
  Relies on agents doing bookkeeping correctly across a long session, which is
  what they are worst at. The check is idempotent and self-starting instead.
- **Adding `ghcid` to the `ci` shell.** Every CI run would realise a closure it
  never executes. The app reaches `ghcid` by store path; it is in `default` only
  so humans can run the TUI directly.
- **Making this part of `just check`.** An interpreted typecheck is not a check
  by ADR 1's definition, so it stays out of `check` and out of CI. It does get
  its own recipe, `just quick-typecheck`, as a developer utility next to
  `stop-ghcid` and `fix-hls`.

## Consequences

- Agents get a typecheck verdict in about a second instead of a full build.
- A live session holds hundreds of MB resident, per worktree. A watchdog stops
  the daemon after 30 minutes idle, because nothing else reliably would.
- The first `nix run .#quick-typecheck` of a session pays for loading the repl.
- `quick-typecheck` reports only what `ghci` can see: no optimisation, no link
  errors, no test results, no `hlint`, and no benchmark.
- CI is untouched by this: no workflow calls the app.
