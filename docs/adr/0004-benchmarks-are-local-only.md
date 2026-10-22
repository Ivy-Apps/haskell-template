# 4. Benchmarks are local-only and excluded from CI

Date: 2026-10-22

## Status

Accepted

## Context

`just benchmark` measures the cases in `bench/Bench/Cases.hs` with criterion
and fails when the numbers regress against `bench/reference.yaml`. Every other
quality check runs in CI, and ADR 1 makes the Justfile the source of truth for
those checks. A benchmark that CI never runs is therefore a deliberate
exception, and one a future reader is entitled to question.

The exception exists because a wall-clock measurement is only comparable to
another taken on the same machine:

- **The Reference is machine-specific.** It is recorded by
  `just update-benchmark` on a developer's machine. A GitHub runner is different
  hardware with a different core count; its timings differ from the recorded
  ones by far more than any threshold worth setting, so the gate would fail on
  hardware rather than on code.
- **Shared runners are noisy.** Run-to-run variance from co-tenanted workloads
  is commonly larger than the regression the gate is meant to detect. A
  threshold above that noise floor detects nothing; one below it flaps.

## Decision

`just benchmark` and `just update-benchmark` are run by hand, on a machine the
developer knows. No CI workflow invokes them.

CI does run `just build-bench`, which compiles the benchmark without running
it, so a change that breaks its code fails the pull request instead of rotting
silently until someone next reaches for it.

`bench/reference.yaml` records the environment it was taken under (compiler
version, OS, architecture, processor and capability count) and a run whose
environment differs says so before printing its comparison.

Each case is judged on its own new-over-old ratio, and the suite on the
geometric mean of those ratios, for both time and allocations. Allocations are
held to a much tighter limit than time, because the same work allocates the
same bytes run after run.

## Considered options

- **Benchmark `main` and the branch in the same CI job, then compare.** The only
  wall-clock design that is statistically sound on shared hardware. Rejected on
  cost: it doubles the benchmark time and adds a second full build of `main` to
  every pull request, for a signal a developer can obtain locally.
- **Commit a Reference per machine, keyed by a fingerprint.** Rejected because
  the CI entry has to be refreshed by a human, and an entry nobody refreshes
  rots silently into a gate that is either permanently red or meaningless.
- **Gate on allocations only, which are machine-independent.** Rejected as the
  *sole* metric, because it cannot see a regression that costs time without
  allocating, such as a worse constant factor or new contention. Allocations are
  instead gated alongside time.

## Consequences

- A performance regression can reach `main`. Nothing automated will catch it;
  whoever changes code they believe to be hot must run `just benchmark`. This is
  accepted.
- The Reference is only meaningful next to the machine that produced it. Moving
  to new hardware, or upgrading GHC, invalidates it and requires a fresh
  `just update-benchmark`; the recorded environment is what makes that visible
  rather than mysterious.
- A green benchmark says nothing about correctness: a change that stopped doing
  half the work would read as a large speedup. Benchmark results are only
  meaningful after a green `just check`.
