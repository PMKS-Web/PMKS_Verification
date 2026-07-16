# MotionGen pilot findings

This pilot records the source-specific behavior that had to be established before MotionGen
could be used as corroborating evidence. It is part of the reviewed tolerance contract; future
changes must be investigated and reviewed rather than silently widening the limits.

## Export semantics

MotionGen 1.1.5 exports graph values to three decimal places. Position and link angle use the
graph timestamp directly. The derivative columns are forward differences at 60 Hz:

- scalar speed and link omega are centered half a timestep ahead;
- scalar `Linear Accel.` and link alpha are centered one timestep ahead;
- scalar `Linear Accel.` is signed tangential acceleration, not vector acceleration magnitude.

The last point is observable on the teaching four-bar input joint B: MATLAB's vector acceleration
has magnitude `1.7718141041061379` at the initial row, while constant-speed circular motion has
zero tangential acceleration and MotionGen exports `0`. After applying the half-step/full-step
input-angle offsets, the derivative series agree within the quantization/interpolation bound.

## Quantization pilot

The original limit was converted three-decimal ordinate quantization, propagated input-angle
quantization using the local slope, and twice the local second-difference interpolation bound.
Comparing every eligible MATLAB value against all nine complete retained four-bar cycles produced
145,800 comparisons. Two values barely exceeded that limit:

- `G:matlab_0133:speed:cycle_07`: ratio `1.02097`;
- `I:matlab_0214:y:cycle_02`: ratio just over `1`.

This is source numerical/rounding behavior beyond the idealized half-unit decimal bound, not an
assembly, direction, or sweep disagreement. The reviewed adjustment is a guard equal to 5% of
the applicable ordinate quantization. It is source-specific, absolute, and additive; it is not a
relative tolerance, percentage alignment rule, or row exclusion.

With that guard:

- teaching four-bar: 145,800 values across cycles 1–9, maximum ratio `0.9748`;
- teaching slider-crank: 110,852 values across cycles 1–14, maximum ratio `0.9601`.

All 256,652 eligible comparisons are required. No terminal null-to-zero cell is used by these
comparisons.

## Zero-speed scalar exclusions

Signed tangential acceleration is undefined when speed is zero but vector acceleration is not.
The teaching slider-crank reaches that state at exactly `matlab_0090` and `matlab_0270` for joint
C. Those two scalar cells are named in `motiongen_exclusions`; their vector accelerations remain
covered by independent MATLAB–PMKS comparison. No window or neighboring row is excluded.

MotionGen does not corroborate vector velocity/acceleration direction, CoM data, reactions, or
dynamics. PMKS and the independent Newton–Euler checker retain those responsibilities.
