#!/usr/bin/env python3
"""Build MotionGen's source-specific sample table from the input-link graph."""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path

from reference_data import SAMPLES_HEADER, write_csv

LINK_HEADER = ("sample_id", "time_s", "theta_rad", "omega_rad_s", "alpha_rad_s2")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-link", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    with arguments.input_link.open(newline="", encoding="utf-8") as stream:
        reader = csv.DictReader(stream)
        if tuple(reader.fieldnames or ()) != LINK_HEADER:
            raise RuntimeError(f"Unexpected input-link header: {reader.fieldnames}")
        rows = list(reader)
    angles = unwrap([float(row["theta_rad"]) for row in rows])
    directions = [1 if float(row["omega_rad_s"]) >= 0 else -1 for row in rows]
    write_csv(
        arguments.output,
        SAMPLES_HEADER,
        (
            (
                row["sample_id"],
                "motiongen_sweep_00",
                index,
                angles[index],
                directions[index],
                float(row["time_s"]),
                0.0,
                "eligible",
            )
            for index, row in enumerate(rows)
        ),
    )


def unwrap(values: list[float]) -> list[float]:
    result = values[:]
    for index in range(1, len(result)):
        while result[index] - result[index - 1] > math.pi:
            result[index] -= 2 * math.pi
        while result[index] - result[index - 1] < -math.pi:
            result[index] += 2 * math.pi
    return result


if __name__ == "__main__":
    main()
