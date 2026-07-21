# Reference data v1

The original PMKS acceleration incompatibility is closed by the pinned PMKS-Web fork described
in [FEASIBILITY.md](FEASIBILITY.md). The contract and generators remain candidate infrastructure
until a successful workflow artifact is promoted as the first trusted v1 baseline.

This directory is the only supported machine-readable reference-data contract. Consumers must
reject `legacy/reference-output` and the historical `Mechanisms/**/CSVOutput` layouts.

Each source owns its own sample table. Rows are joined by the generated `alignment.csv`; row
numbers are never treated as cross-source identities. Numeric CSV values use `%.17g` and must
round-trip within one ULP or `1e-15 * max(1, |value|)`.

Trust labels have deliberately narrow meanings:

- `matlab-pmks-fork`: vector kinematics agreed between MATLAB and the pinned PMKS-Web/PMKS fork.
- `matlab-pmks-fork-motiongen`: the same result also has MotionGen position, scalar-derivative, and
  angular corroboration under the source conventions recorded in the case manifest.
- `newton-euler-consistency`: serialized MATLAB dynamics satisfy an independent equilibrium and
  power check; this is not an external dynamics oracle.
- `diagnostic-only`: useful for investigation but prohibited from trusted consumer suites.
- `not-applicable`: the source or capability does not apply.

Source metadata is stable and content-addressed. Workflow/run SHAs, timestamps, and tool builds
belong in the separately published `run-report.json`, never in `case.json`.
