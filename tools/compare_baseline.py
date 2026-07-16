#!/usr/bin/env python3
"""Compare regenerated data to a committed baseline using the same-source tier."""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path

from reference_data import ContractError, reject_legacy


def compare(baseline: Path, candidate: Path, allow_missing: bool) -> None:
    reject_legacy(baseline)
    reject_legacy(candidate)
    if not any(baseline.glob("cases/*/matlab/samples.csv")):
        if allow_missing:
            print("BASELINE_STATUS=candidate-only")
            return
        raise ContractError("Committed v1 baseline is missing")
    baseline_files = relative_files(baseline)
    candidate_files = relative_files(candidate)
    if baseline_files != candidate_files:
        raise ContractError(
            f"Baseline file set changed; missing={sorted(baseline_files-candidate_files)}, "
            f"extra={sorted(candidate_files-baseline_files)}"
        )
    for relative in sorted(baseline_files):
        first = baseline / relative
        second = candidate / relative
        if first.suffix == ".csv":
            compare_csv(first, second)
        else:
            if first.read_bytes() != second.read_bytes():
                raise ContractError(f"Unexplained baseline change: {relative}")
    print("BASELINE_STATUS=match")


def relative_files(root: Path) -> set[Path]:
    return {
        path.relative_to(root)
        for path in root.rglob("*")
        if path.is_file()
    }


def compare_csv(first: Path, second: Path) -> None:
    with first.open(newline="", encoding="utf-8") as stream:
        expected = list(csv.reader(stream))
    with second.open(newline="", encoding="utf-8") as stream:
        actual = list(csv.reader(stream))
    if len(expected) != len(actual):
        raise ContractError(f"{first}: row count changed")
    for row_index, (expected_row, actual_row) in enumerate(zip(expected, actual), 1):
        if len(expected_row) != len(actual_row):
            raise ContractError(f"{first}:{row_index}: column count changed")
        for column_index, (left, right) in enumerate(zip(expected_row, actual_row), 1):
            try:
                first_number = float(left)
                second_number = float(right)
            except ValueError:
                if left != right:
                    raise ContractError(f"{first}:{row_index}:{column_index}: text changed")
                continue
            scale = max(1.0, abs(first_number), abs(second_number))
            ulp = max(math.ulp(first_number), math.ulp(second_number))
            if abs(first_number - second_number) > 8 * ulp + 1e-12 * scale:
                raise ContractError(
                    f"{first}:{row_index}:{column_index}: same-source value changed "
                    f"{first_number:.17g} -> {second_number:.17g}"
                )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--allow-missing", action="store_true")
    arguments = parser.parse_args()
    compare(arguments.baseline, arguments.candidate, arguments.allow_missing)


if __name__ == "__main__":
    main()
