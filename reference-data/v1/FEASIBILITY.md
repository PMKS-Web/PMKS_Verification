# PMKS oracle feasibility result

Status: **passed; the original PMKS acceleration blocker is closed**.

The initial pilot used byte-unmodified DesignEngrLab/PMKS commit
`2a0a6fca957dd19844567702af663f607dc15dfe`. It built and ran all five topologies,
but its acceleration solver rejected valid analytic solutions near motion reversals because of
fixed magnitude limits. That produced 80 failed Watt I values and 144 failed Stephenson III
Example 2 values even though the affected assembly Jacobians were well below the contract's
`1e10` singularity threshold. The evidence is retained in
[GitHub Actions run 29527397761](https://github.com/PMKS-Web/PMKS_Verification/actions/runs/29527397761).

[PMKS-Web/PMKS PR 1](https://github.com/PMKS-Web/PMKS/pull/1) made the minimum compatibility
change: acceleration validation no longer applies the velocity magnitude heuristic, and the
existing link-velocity guard now checks the link limit rather than the joint limit. The oracle is
pinned to merged fork commit `644b26c75b07182ce04dc6466cfec74ee4130c93`. Its exact one-file
delta from the upstream base is enforced by
[`pmks-fork-delta.json`](pmks-fork-delta.json).

The corrected fork passes both input-speed directions for all five cases using the original
one-degree increment, exact `rpm * pi / 30` speeds, comparison tolerances, and eligibility rules:

| Case | Aligned rows | Maximum scaled error |
| --- | ---: | ---: |
| Slider-crank tracer | 361 / 361 | `1.061e-5` |
| Stephenson III Example 2 | 201 / 201 | `9.512e-7` |
| Teaching four-bar | 361 / 361 | `1.736e-5` |
| Teaching slider-crank | 361 / 361 | `1.281e-5` |
| Watt I | 23 / 23 | `4.391e-7` |

`1.0` is the failure threshold for scaled error. No tolerance was enlarged and no exclusion was
added to obtain these results. Watt I and Stephenson III now agree for all eligible acceleration
rows, while the three cases that already passed have no position, velocity, acceleration,
prismatic, tracer, or CoM regression.

The fork remains useful cross-implementation corroboration, but it is not a wholly independent
upstream oracle: it derives from the DesignEngrLab implementation and carries a targeted
compatibility fix maintained by PMKS-Web. MATLAB constraint residuals, independent serialized
Newton–Euler/power checks, and MotionGen evidence retain their separate roles in the promotion
pipeline. Any later fork delta, unexplained disagreement, exclusion, or tolerance change still
blocks promotion.
