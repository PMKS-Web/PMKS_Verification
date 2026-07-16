# PMKS oracle feasibility result

Status: **blocked; no v1 data may be promoted**.

The byte-unmodified DesignEngrLab/PMKS source at
`2a0a6fca957dd19844567702af663f607dc15dfe` builds on .NET SDK `8.0.129` and
runs all five topologies in both speed directions. The first complete MATLAB R2024a pilot is
[GitHub Actions run 29527397761](https://github.com/PMKS-Web/PMKS_Verification/actions/runs/29527397761).
It used the exact one-degree increment and `rpm * pi / 30` speed contract.

Three cases meet the proposed MATLAB-PMKS tolerances for every row and every applicable series:

| Case | Aligned rows | Compared values | Maximum scaled error |
| --- | ---: | ---: | ---: |
| Slider-crank tracer | 361 / 361 | 18,405 | `1.061e-5` |
| Teaching four-bar | 361 / 361 | 22,743 | `1.736e-5` |
| Teaching slider-crank | 361 / 361 | 14,073 | `1.281e-5` |

`1.0` is the failure threshold for scaled error, so these maxima retain more than four orders of
magnitude of tolerance margin.

Watt I and Stephenson III Example 2 align completely for position and velocity, but the pinned
PMKS acceleration solver disagrees near motion reversals:

| Case | Affected MATLAB samples | Failed values | Recorded condition range | Example |
| --- | --- | ---: | ---: | --- |
| Watt I | `0005`, `0006`, `0016`, `0017` | 80 | 35.90–47.49 | EF angular acceleration: PMKS `-198.284`, MATLAB `-605.723` |
| Stephenson III Example 2 | `0041`, `0042`, `0139`–`0144` | 144 | 40.80–85.44 | FG angular acceleration at `0139`: PMKS `-74.0504`, MATLAB `-97.1250` |

All failures are linear or angular acceleration. None meets the contract's singularity threshold
of `1e10`, so adding exclusions would violate the reviewed plan. The discrepancy also extends
beyond duplicate reversal rows in Stephenson III Example 2. As a diagnostic cross-check, a local
seven-point differentiation of the serialized positions at sample `0139` gives FG angular
acceleration `-95.6357`, which is close to MATLAB and not PMKS; this diagnostic is not promoted
as a new oracle.

The MATLAB candidate remains internally strong: its maximum assembly acceleration-constraint
residual is `2.092e-11`, and the independent serialized Newton-Euler/power checker passes with
maximum scaled residuals of `8.417e-13` for Stephenson III Example 2 and `3.254e-15` for Watt I.

The agreed no-majority-vote rule therefore blocks promotion. Resolving this requires either an
upstream PMKS acceleration fix followed by review of a new source pin, or an explicit revision of
the oracle contract. Tolerances and conditioning thresholds have not been enlarged, and no
unsupported exclusion has been added.
