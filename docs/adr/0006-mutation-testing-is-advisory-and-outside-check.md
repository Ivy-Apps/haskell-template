# 6. Mutation testing is advisory and outside `just check`

Date: 2026-10-31

## Status

Accepted

## Context

Coverage says a line ran, not that a test would notice it breaking. Mutation
testing measures that, and this template wants it from the start, with its tests
staying on hspec. sydtest-mutation is the maintained choice for GHC, and its
`fromHspec` bridge runs an hspec tree unchanged. Three things shape how it can be
used here:

- **It is heavy to set up.** Not in nixpkgs or at our Hackage index, it comes from
  sydtest's flake. A local cold build takes about 25 minutes, and a local run
  after it about a minute. A CI run takes minutes: the Nix cache may not hold
  sydtest, so it may rebuild from source.
- **It proves itself on x86_64 only.** Upstream CI does not run aarch64.
- **Its licence is not open source.** See the README. A template must let a
  closed-source clone remove it.

A run has one trap. A test that fails before any mutation makes the mutants it
covers read as killed. The report and the exit code of that run stay clean, and
only a line in the build log says so. Mutation runs happen in a sandbox with a
read-only source tree, so a test can fail there alone.

## Decision

- **Tests stay on hspec.** The cabal flag `mutation`, off by default, swaps the
  test suite's main for `test/MutationMain.hs`. Nothing but
  `checks.<system>.mutation` turns it on or evaluates the `sydtest` input.
- **`just mutation` is a recipe of its own**, outside `just check`, and a CI
  workflow of its own, `mutation.yaml`, on x86_64 and outside the aggregate
  `Check`. A survivor never fails it, so the score is advice for now.
- **Only `mutation.yaml` has the weekly schedule.** In `ci.yaml` it would rerun
  every other job each week, so that file stays as it was.
- **The score counts `skipped` and `uncovered` as not killed.** A mutant skipped
  behind a survivor is not one a test caught.
- **The baseline guard is a build input of the result.** The check runs the
  coverage phase a second time with fail-fast, which aborts on a test failing at
  baseline, and the result depends on that derivation. Nix never stores a failed
  build, so a cached green result cannot have skipped it, and `just mutation` and
  CI need no check of their own. The same run cannot carry fail-fast, because it
  would also abort on the first survivor.
- **PRs run the full check.** The job goes red only on what makes the numbers
  false: a failed baseline or a failed control.

## Considered options

- **Grep the build log for the baseline warning.** Rejected: a cached result has
  no fresh log, and on a CI cache hit `nix log` has nothing to read, so a green
  run would either skip the guard or fail for no reason.
- **The diff-scoped runner on PRs.** It picks the right mutants, but rejected for
  now. Nearly all of a run is the instrumented build, which it needs too: 40s
  against 45s here. It exits 1 for a survivor, for an uncovered mutant and for a
  bad argument alike, so an advisory job could not tell them apart without
  reading its output, and it reports only the subset. Worth another look when a
  full run gets slow.
- **Migrate the tests to native sydtest.** Same verdicts as the bridge on the 63
  outcomes compared, so all cost and no gain. It would also tie every clone to
  the licence for its plain test runs.
- **Gate on a score now.** Rejected until the score has been stable for a while.

## Consequences

- A survivor can land. Whoever reads the job summary decides what to do with it.
- The score means little on the template's few mutants; it is here for what a
  clone grows into.
- `flake.lock` carries sydtest's inputs, about 270 lines nobody fetches outside
  this check.
- The test suite has a second entry point, so anything a test writes to the source
  tree works under `just test` and fails at baseline here. The guard makes that
  loud.
