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

### Running MATLAB without a licence

**You do not need a MATLAB licence, or MATLAB installed, to add or change a case.** The
`MATLAB R2024a candidate` job is the only part of the pipeline that genuinely requires MATLAB, and
it runs on GitHub-hosted runners under MathWorks' own actions:

```yaml
- name: Set up MATLAB R2024a
  uses: matlab-actions/setup-matlab@<pinned sha>   # v3
  with:
    release: R2024a
    products: Symbolic_Math_Toolbox
    cache: true

- name: Generate MATLAB v1 source tables from clean definitions
  uses: matlab-actions/run-command@<pinned sha>    # v3
  with:
    command: addpath(fullfile(pwd, 'verification')); run_verification(...)
```

`setup-matlab` installs MATLAB and the Symbolic Math Toolbox on the runner; `run-command` then
executes in batch mode against it. On a **public** repository this needs no licence and no secret —
nothing to configure, no `MLM_LICENSE_FILE`, no login, no self-hosted runner. `cache: true` keeps
the installation between runs, which is most of why the job takes about seven minutes rather than
twenty.

Consequences worth planning around:

- **This depends on the repository staying public.** A private repository, or a fork with Actions
  disabled, needs a MathWorks batch licence supplied as a secret instead. If this repo is ever made
  private, that job is the first thing to break.
- **The runner is the only MATLAB oracle here.** There is no local fallback, so a contributor
  without MATLAB cannot pre-check the MATLAB half directly — push the branch and read the log.
- **Everything else runs locally**, and is worth exhausting before spending a CI cycle. See
  [Validation commands](#validation-commands) and [Local PMKS oracle](#local-pmks-oracle): the PMKS
  oracle, the schema and provenance validators, the dynamics checker, and the perturbation tests all
  run on a laptop. The common failures — a missing case-registry entry, a stale content hash after
  editing shared `verification/*.m` — are caught there in seconds rather than after a full run.
- **A partial pre-check of the MATLAB half is still possible** without the toolbox, by porting the
  case's own solver steps and asserting the properties the case exists for: closure, coupler-length
  drift, and whatever geometric invariant the case is about. That produces no candidate, but it does
  tell you the geometry is sane before you spend the seven minutes finding out.

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

## Adding a case

A new case touches more than its own directory, and none of it fails informatively.
In order:

1. **MATLAB source** under `Mechanisms/`, and an entry in `verification/verification_case_definition.m`,
   `verification/build_verification_case.m`, and the `caseNames` list in `verification/run_verification.m`.
   A per-case regression gate in `verification/validate_verification_case.m` is optional but is what
   stops a later edit silently neutering the case.
2. **`reference-data/v1/cases/<id>/case.json`**, matching the schema. `trust` values must come from
   `TRUST_LEVELS` in `tools/reference_data.py`; a stale label from an older case will be rejected.
3. **Three hardcoded case registries**, each of which fails in a different job with a different
   message: `EXPECTED_CASES` in `tools/validate_v1.py`, `expectedCases` in `oracle/pmks/Program.cs`,
   and `SOURCE_DIRECTORIES` in `tools/write_source_metadata.py` (this one raises a bare `KeyError`).
4. **Generated data**, per the two-phase promotion above.
5. **Provenance for every *other* case.** `matlab_files()` hashes `CommonUtils/*.m` *and*
   `verification/*.m` alongside the case's own folder, so editing the shared verification scripts —
   which step 1 requires — invalidates the recorded source hash of every existing case. Expect to
   update all per-case `source-metadata.json` files plus the root `reference-data/v1/source-metadata.json`,
   which carries its own `cases` map.

Two things that mislead while debugging a run:

- `digest-mismatch: error` in the log is an *input parameter* of `download-artifact`, not a failure.
- The PMKS oracle is not bit-reproducible across runs. Regenerated CSVs can differ from committed
  ones by ~1e-13 on identical rows, which is inside the same-source tier and is tolerated by the
  numeric comparison. Only the JSON metadata is compared exactly, so `diff -rq` overstates what
  actually changed.

The oracle half runs locally, which removes most blind CI iteration:

```bash
# The pinned PMKS-Web fork, not DesignEngrLab upstream. The oracle and every
# recorded pmks_source_content_sha256 are the fork at this commit; building
# against unpatched upstream silently produces numbers CI will not reproduce.
git clone https://github.com/PMKS-Web/PMKS .external/PMKS
git -C .external/PMKS checkout 644b26c75b07182ce04dc6466cfec74ee4130c93

# Prints PMKS_ORACLE=PASS on success. That line is the local gate: the oracle
# runs its own positive/negative sweep per case and fails if either direction
# disagrees.
dotnet run --project oracle/pmks/PmksOracle.csproj -c Release -- \
  --cases-root reference-data/v1/cases --output-root artifacts/candidate/reference-data/v1

# Checks the COMMITTED contract. --root defaults to reference-data/v1, so this
# does not look at the candidate just generated and a broken candidate cannot
# make it fail. Run it for what it does catch: schema, case-set membership,
# trust labels, and stale content hashes after editing shared sources.
python3 tools/validate_v1.py --require-sources
```

**Nothing local compares the candidate against the committed tables.** `compare_baseline.py`
requires a *combined* MATLAB + PMKS candidate — it asserts the whole baseline file set is present,
so an oracle-only candidate fails immediately on every missing `matlab/` path rather than on any
numeric difference. Building that combined tree needs the MATLAB job, so the numeric
MATLAB-versus-PMKS comparison is genuinely CI-only. Locally, `PMKS_ORACLE=PASS` plus a clean
`validate_v1.py` is as far as you can get.

Only MATLAB genuinely requires the runner.

## Legacy and deferred scope

Historical MAT/CSV output lives under `legacy/reference-output` and is not a supported input.
New tools reject legacy paths, and regenerated historical output under `Mechanisms` is ignored.
Stephenson III Example 1 and OTIS remain follow-up work; neither is represented as passing or
expected-failing coverage in v1.
