# MotionGen library captures

Three mechanisms from the MotionGen library, captured as **model geometry plus MotionGen's own
solved joint paths**, for cross-checking PMKS+'s new joint types (floating slots, the pure
prismatic Slide, and sealed cylinders) against a second independent engine.

| Case | What it exercises | Solved paths captured |
| --- | --- | --- |
| `gripper/` | a **cylinder** driving a plate, and **two grounded slots carrying two riders each** | yes — 47 poses, 11 moving joints |
| `elliptical-crank/` | a six-bar whose coupler end rides a **grounded slot**, rotary-driven | geometry only |
| `running-horse/` | 45 joints, 28 links, no sliders — a scale test for the pin machinery | geometry only (upstream asset) |

## Why these are not v1 cases

This directory is deliberately **outside** `reference-data/v1/`. The v1 contract admits a MotionGen
series only through the normalized-XLSX pipeline with a per-graph receipt (original filename, source
SHA-256, quantization bounds, normalizer hash), and `tools/motiongen/README.md` records that the
historical normalizer is **not approved for new exports** until it is replaced with one built on a
public XLSX parser with a committed lock file. None of that is satisfied here, and pretending
otherwise would put unaudited numbers behind an audited label.

What these captures are good for is the thing they are used for in PMKSWeb: asserting that a
mechanism rebuilt from this geometry traces the same joint paths a second engine traces. What they
are not good for is promotion into v1, or any claim of numeric provenance.

## How they were captured

`gripper` and `elliptical-crank` were read out of the running MotionGen client's own model state,
in a browser signed in by the repository owner, rather than exported through the UI. That avoids the
XLSX path entirely — the client already holds both the exact model and its solved curves as
doubles, so a capture is a read rather than a re-serialization, and there is no spreadsheet
quantization to bound.

`running-horse` needed none of that: MotionGen serves it as a **public static asset**
(`https://motiongen.io/assets/horse-EN_hvSSW.motiongen`), committed here byte-for-byte.

Reproducing a capture:

1. Open the model from the MotionGen library.
2. In the page, walk the React tree for the object carrying `joints`, `links`, `slots`,
   `cylinders`, `actuators` — React 18 hangs the root fiber directly off the container element's
   `__reactContainer$…` property, so walk that node itself rather than its `.current`.
3. Two such objects exist; the populated one is the model and the empty one is the new-document
   template, so take the one whose `joints` map is non-empty.
4. Solved paths are in `simulations[…].curves`, keyed by joint id, one `points` array per joint.

The capture is a snapshot of the library as it stood on 2026-08-07 and carries no version stamp
from MotionGen, because the client does not expose one for library models. Treat a mismatch after
an upstream edit as a stale capture rather than as a defect.

## Coordinates

Verbatim MotionGen coordinates, in inches, no transform applied. The v1 cases carry a
`coordinate_transform` because their XLSX exports were taken in a shifted frame; nothing here was
re-framed, so there is nothing to undo.

## What consumes them

`src/tests/verification/motiongen-gripper.spec.ts` in PMKSWeb rebuilds the gripper from
`gripper/model.json` and asserts its solved joint paths against `gripper/motiongen-curves.csv`.
