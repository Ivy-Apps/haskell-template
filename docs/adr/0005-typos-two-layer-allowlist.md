# 5. typos spell checking with a two-layer allowlist

Date: 2026-10-22

## Status

Accepted

## Context

Spelling mistakes in identifiers, comments and docs are cheap to catch and
expensive to remove once they spread through an API. [typos](https://github.com/crate-ci/typos)
is fast enough to run on every file in every check, and has a low false
positive rate because it only flags known misspellings rather than unknown
words.

It still needs somewhere to record the false positives it does have. Some of
those words are fine to publish (a Haskell function name like `bimap`), and
some are not: a client name or an internal codename hit while working in a
private project must not end up committed to a public repository.

## Decision

typos runs in three places, all reading the same committed `.typos.toml`:
`just typos` (CI and `nix run .#lint`), `treefmt` (so `just fmt` corrects what
it can), and editors through `typos-lsp`.

There are two allowlist layers:

1. **The committed `.typos.toml`** in each repository. It is the only layer CI
   sees. Every entry is a genuine false positive with a comment saying why, and
   it is scoped to the repository: allowing a token that is a common
   misspelling elsewhere would hide every genuine instance of it in prose,
   everywhere, forever.
2. **A private global allowlist** on the developer's machine, for words whose
   disclosure matters. It is passed to typos explicitly (`--config`, or the
   editor's `init_options.config`), which loads it into typos' override layer
   where its `extend-words` merge with the project's. A `typos.toml` in `$HOME`
   would not work: typos stops its ancestor walk at the first config it finds,
   so it would silently stop applying the moment a project grew a
   `.typos.toml` of its own.

`.typos.toml` sets `ignore-hidden = false`, so `just typos` checks dotfiles
(`.github/`, `.claude/`) exactly as treefmt does, and excludes `.git/`.

typos is pinned through `flake.lock` (it comes from the locked nixpkgs in the
`ci` shell), because its dictionary is its product and grows every release.

## Consequences

- **A real typo is fixed, not allowlisted.** Adding a word to `.typos.toml` is
  a reviewed change with a stated reason.
- **Accepted local/CI divergence.** The private layer is invisible to CI by
  design, so a privately allowed word can make a local editor quiet while CI
  fails. `just typos` runs against the committed config only, exactly like CI,
  which is the intended way to catch this before pushing.
- **Bumping `flake.lock` can legitimately surface new findings.** That is the
  pin working as intended; the fix is to correct or allowlist the words, not to
  unpin typos.
