# PMKS Verification

This repository produces the reviewed `reference-data/v1` contract used by PMKSWeb. A result is
trusted only when the MATLAB implementation agrees with the pinned
[PMKS-Web/PMKS](https://github.com/PMKS-Web/PMKS) fork, every eligible row aligns,
and every applicable independent check passes. There is no majority vote: an unexplained
disagreement fails the pipeline.

## Pinned sources

- MATLAB R2024a plus Symbolic Math Toolbox on `ubuntu-24.04`
- PMKS-Web/PMKS commit `644b26c75b07182ce04dc6466cfec74ee4130c93`, based on
  DesignEngrLab/PMKS `2a0a6fca957dd19844567702af663f607dc15dfe`
- .NET SDK `8.0.129`
- One-degree input increments and exact `rpm * pi / 30` speeds

All GitHub Actions are referenced by immutable commit SHA. Stable generator/source metadata is
content-addressed under v1; timestamps, workflow identities, MATLAB builds/toolboxes, runner
images, PR-head SHAs, and tested merge SHAs are kept in the separately published
`run-report.json`.

## Contract and trust

Each case owns source-specific sample tables. `alignment.csv` is the only cross-source join; row
numbers are never assumed to match. Reversals and cycle endpoints are distinct MATLAB samples,
while a canonical PMKS branch may be reused by adjacent MATLAB sweeps. The input assembly is
checked using a signed-area signature for every independent loop.

The three tolerance tiers are encoded in the tools:

1. CSV serialization: one ULP or `1e-15 * scale`, with canonical `%.17g` text.
2. Same-source regeneration: eight ULP plus `1e-12 * scale`. Pinned PMKS tables use the
   separately documented `8e-12 * scale` repeatability bound for algebraically equivalent
   elimination orders; derived comparison-report maxima allow the corresponding `1e-4` absolute
   scatter. These do not change the MATLAB–PMKS acceptance tolerances.
3. MATLAB–PMKS: the position/velocity/acceleration and angular limits declared in the v1 plan.

A row is singular only when the dimensionless assembly Jacobian condition number exceeds
`1e10`. Positions remain comparable. Any derivative or source-only exclusion must identify the
exact case, sample, series, input angle, threshold evidence, and reason in `case.json`; broad
windows and percentage alignment are rejected.

Teaching CoMs are diagnostic-only because their historical coordinates and inertias are not in
a coherent unit system. Watt I and Stephenson III Example 2 dynamics are labeled only
`newton-euler-consistency`: an independent Python checker verifies per-link force/moment balance
and global power from serialized data, but there is no external dynamics oracle. Static,
friction, stress, teaching dynamics, and slider reactions are out of scope and hard-fail if
requested.

## Local PMKS oracle

Check out the exact merged fork revision:

```bash
git clone https://github.com/PMKS-Web/PMKS .external/PMKS
git -C .external/PMKS checkout 644b26c75b07182ce04dc6466cfec74ee4130c93
dotnet restore oracle/pmks/PmksOracle.csproj --locked-mode
dotnet run --project oracle/pmks/PmksOracle.csproj -c Release -- \
  --cases-root reference-data/v1/cases \
  --output-root artifacts/candidate/reference-data/v1
```

The adapter runs both speed signs. PMKS inserts full-cycle endpoints from concurrent
forward/backward tasks, so raw output can contain 362 or 363 rows. The reviewed adapter groups
by exact one-degree input tick, deterministically collapses only duplicate ticks, and proves the
canonical 360-row result is repeatable within the same-source tier. The adapter never modifies
the checked-out fork source.

## MATLAB candidate

Run from a clean MATLAB R2024a session:

```matlab
addpath(fullfile(pwd, 'verification'));
run_verification(fullfile(pwd, 'artifacts', 'candidate', 'reference-data', 'v1'));
```

The runner copies source into an empty scratch directory, builds every case from explicit
definitions, runs solver-specific regression gates, and writes only v1 CSV. Scratch
`Mechanism.mat` files never enter the candidate.

Pass a case list to run a subset:

```matlab
run_verification(outputRoot, {'watt_i', 'teaching_four_bar'});
```

CI uses that to put **one case on one runner**. Cases were already independent — each gets its own
scratch directory and clears the previous case's functions before running — so sharding is a
scheduling change rather than a semantic one, and it isolates cases more strictly than sharing a
single MATLAB session did.

The shard list is read from `reference-data/v1/cases`, so adding a case adds a runner with no
registry to update. Each shard writes a run report covering only its own cases;
`tools/merge_matlab_reports.py` combines them and fails if two shards disagree on the MATLAB
version or product list, if a case appears twice, or if the shards do not cover the contract.

The practical effect is that MATLAB wall time is now the *slowest single case* rather than the sum
of all of them, so it no longer grows as cases are added.

## MotionGen evidence

The two canonical cases use retained signed-in MotionGen models:

- Teaching four-bar: `OocSpHMBTmcRQwFSJE9x`, A–I and all moving links, exact 10.31 RPM
- Teaching slider-crank: `MEjogZJd5srJlJ7nmOXN`, A–C and all moving links, exact 15.1 RPM;
  coincident tracer E maps to B

Both actuators use a flat variable-velocity profile with 3,600 values, producing 3,601 graph
rows at 60 Hz. The slider model terminates its grounded horizontal slot at fixed pivot A. Extending
that same guide through A is kinematically equivalent, but the endpoint form prevents MotionGen's
hidden slot-link hit target from blocking A during graph export. The exact model identity, source
units, actuation, scale, and coordinate transform are pinned in each `case.json` and repeated in
every receipt.

Use Joint Graph (or Link Graph), select one object, open the graph overflow menu, and choose
`Download as XLSX`. The committed exports were normalized with
`tools/motiongen/normalize_xlsx.mjs`. That provenance-locked script depends on the non-public
`@oai/artifact-tool` runtime and is not executable from a clean public clone; it must not be used
for new exports. A future refresh requires a fresh retained-model export and a replacement based
on a public, locked XLSX parser, as detailed in `tools/motiongen/README.md`. The historical tool
records the model URL/ID, units, graph identity, original filename and SHA-256, sheet/header
inventory, download time, transform, speed ratio, row count, and its own content hash. It deletes
the original only when `--discard-input true` is passed. Per the project decision, the XLSX is not
committed; every receipt states that future re-normalization therefore requires a fresh export.

MotionGen x/y and link angular values are directional. Its scalar joint speed is speed magnitude;
its scalar `Linear Accel.` is signed tangential acceleration, not vector acceleration magnitude.
MotionGen computes the derivative columns with forward differences: velocity/omega are centered
half a 60-Hz timestep ahead of the position timestamp, while acceleration/alpha are centered one
timestep ahead. The comparator applies those exact input-angle offsets before comparison. PMKS
remains the independent vector-direction check. Tangential acceleration is undefined at the two
zero-speed slider extrema; those exact cells are declared in `motiongen_exclusions`, and their
vector accelerations remain covered by MATLAB–PMKS comparison.

The tolerance converts MotionGen's three-decimal ordinate and input-angle quantization into the
target coordinates, propagates angle quantization with the local slope, and adds twice the local
second-difference interpolation bound. A reviewed source-numeric guard equal to 5% of ordinate
quantization covers the two sub-quantization pilot overages; the measurements and rationale are in
[`reference-data/v1/MOTIONGEN_PILOT.md`](reference-data/v1/MOTIONGEN_PILOT.md). Relative link
angles include quantization from both the current and initial rows. Only named terminal derivative
cells observed as MotionGen null-to-zero conversions may otherwise be excluded.

## Validation commands

Given a complete candidate:

```bash
python3 tools/write_source_metadata.py --root artifacts/candidate/reference-data/v1 \
  --repo-root . --pmks-root .external/PMKS
python3 tools/validate_provenance.py --root artifacts/candidate/reference-data/v1 \
  --repo-root . --pmks-root .external/PMKS
python3 tools/validate_v1.py --root artifacts/candidate/reference-data/v1 --require-sources
python3 tools/compare_oracles.py --root artifacts/candidate/reference-data/v1
python3 tools/check_dynamics.py --root artifacts/candidate/reference-data/v1
python3 tools/compare_motiongen.py --root artifacts/candidate/reference-data/v1 --repo-root .
python3 tools/perturbation_tests.py --root artifacts/candidate/reference-data/v1 \
  --repo-root . --pmks-root .external/PMKS
```

The perturbation suite proves independent detection of wrong assembly branch, velocity sign,
an altered otherwise-unaligned negative-speed PMKS branch, tracer acceleration, slider-axis drift,
truncated/restarted sweeps, duplicate mishandling, missing files, force ownership, load point,
gravity, torque, CSV precision, and stale provenance.

## Promotion

Promotion is deliberately two-phase:

1. Commit code, schemas, configuration, and reviewed MotionGen fixtures.
2. Run `workflow_dispatch` at that exact commit, download the successful
   `trusted-reference-data-v1-*` artifact, and commit only its `reference-data/v1` tree.

Committed data must reproduce within the same-source tier. Failed candidates are uploaded under
a diagnostic artifact name and are never promoted. PMKSWeb may pin only a verification commit
reachable from `PMKS_Verification/master`.

## Legacy and deferred scope

Historical MAT/CSV output lives under `legacy/reference-output` and is not a supported input.
New tools reject legacy paths, and regenerated historical output under `Mechanisms` is ignored.
Stephenson III Example 1 and OTIS remain follow-up work; neither is represented as passing or
expected-failing coverage in v1.
