# PMKS Verification

MATLAB reference calculations for PMKS mechanisms. The supported verification runner starts
from explicit source definitions, writes into an empty scratch directory, validates physical
invariants, and publishes regenerated data as a GitHub Actions artifact.

## Run locally

MATLAB R2024a with Symbolic Math Toolbox is the pinned environment:

```matlab
addpath(fullfile(pwd, 'verification'));
run_verification(fullfile(pwd, 'artifacts', 'matlab'));
```

The runner does not read committed `Mechanism.mat` files, experimental sensor data, or existing
CSV output. It generates a `manifest.json` containing the source commit and MATLAB release. CI
also adds `SHA256SUMS` for every generated artifact.

## CI

`.github/workflows/matlab-verification.yml` runs real MATLAB on GitHub-hosted Linux runners.
MathWorks automatically licenses MATLAB and requested products for public GitHub projects, so
the workflow does not require a license secret. The MATLAB release is pinned to prevent output
drift caused by silently changing runtimes.

The workflow runs on pushes, pull requests, and manual dispatch. Its artifact contains fresh CSV
output, the in-memory mechanism state for diagnosis, provenance metadata, and checksums. Normal
consumers should continue using committed reference data so their tests do not depend on MATLAB
or network access.

## Supported scope

| Case | Runner coverage |
| --- | --- |
| Watt I | Position, velocity, acceleration, and Newton–Euler dynamics with gravity on/off |
| Stephenson III Example 2 | Position, velocity, acceleration, and Newton–Euler dynamics with gravity on/off |
| Teaching four-bar | Kinematics only |
| Teaching slider-crank | Kinematics only |
| Slider-crank tracer point | Kinematics only |

Every case must produce finite three-column trajectories with a consistent row count. The runner
also checks rigid-link length preservation plus the differential velocity and acceleration
constraints for each rigid point pair.

Teaching-mechanism dynamics are intentionally excluded until their position, center-of-mass,
inertia, and gravity units are documented in a common system. Stephenson III Example 1 and OTIS
remain outside the supported verification set. These exclusions are scope boundaries, not claims
that the omitted results are correct.
