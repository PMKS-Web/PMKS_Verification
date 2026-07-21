# Reference data v1

The original PMKS acceleration incompatibility is closed by the pinned PMKS-Web fork described
in [FEASIBILITY.md](FEASIBILITY.md). The first trusted v1 baseline has been promoted from a
successful workflow artifact and is committed in this directory.

This directory is the only supported machine-readable reference-data contract. Consumers must
reject `legacy/reference-output` and the historical `Mechanisms/**/CSVOutput` layouts.

Each source owns its own sample table. Rows are joined by the generated `alignment.csv`; row
numbers are never treated as cross-source identities. Numeric CSV values use `%.17g` and must
round-trip within one ULP or `1e-15 * max(1, |value|)`.

Every PMKS row is accounted for. Rows at MATLAB input directions are matched directly and
one-to-one. In the three full-cycle MATLAB cases, the otherwise unused negative-speed PMKS branch
is paired one-to-one with the MATLAB-aligned positive branch at the same input angle. Position and
acceleration must agree, velocity must reverse sign, link angles are compared circularly, and the
same checks cover joints, tracer points, CoMs, links, and prismatic state. The comparison report
records direct, symmetry-covered, and unverified PMKS row counts; unverified rows must be zero.

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
