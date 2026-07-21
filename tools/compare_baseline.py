#!/usr/bin/env python3
"""Compare regenerated data to a committed baseline using the same-source tier."""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path

from reference_data import ContractError, reject_legacy

DEFAULT_RELATIVE_TOLERANCE = 1e-12
# PMKS can choose an algebraically equivalent elimination order between runs. The observed
# Linux-run scatter is 2.073e-12 relative, so its source tables use a documented 8e-12 bound.
PMKS_RELATIVE_TOLERANCE = 8e-12
# A PMKS table perturbation is divided by the cross-source tolerance in this derived diagnostic.
COMPARISON_REPORT_ABSOLUTE_TOLERANCE = 1e-4


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
        elif first.suffix == ".json":
            compare_json(first, second)
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
    relative_tolerance = (
        PMKS_RELATIVE_TOLERANCE if "pmks" in first.parts else DEFAULT_RELATIVE_TOLERANCE
    )
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
            if not same_source_number(first_number, second_number, relative_tolerance):
                raise ContractError(
                    f"{first}:{row_index}:{column_index}: same-source value changed "
                    f"{first_number:.17g} -> {second_number:.17g}"
                )


def compare_json(first: Path, second: Path) -> None:
    expected = json.loads(first.read_text(encoding="utf-8"))
    actual = json.loads(second.read_text(encoding="utf-8"))
    relative_tolerance = (
        PMKS_RELATIVE_TOLERANCE if "pmks" in first.parts else DEFAULT_RELATIVE_TOLERANCE
    )
    if first.name == "comparison-report.json":
        relative_tolerance = COMPARISON_REPORT_ABSOLUTE_TOLERANCE
    compare_json_value(expected, actual, str(first), relative_tolerance)


def compare_json_value(
    expected: object, actual: object, location: str, relative_tolerance: float
) -> None:
    if type(expected) is not type(actual):
        raise ContractError(f"{location}: JSON type changed")
    if isinstance(expected, dict):
        if expected.keys() != actual.keys():
            raise ContractError(f"{location}: JSON keys changed")
        for key in expected:
            compare_json_value(
                expected[key], actual[key], f"{location}.{key}", relative_tolerance
            )
        return
    if isinstance(expected, list):
        if len(expected) != len(actual):
            raise ContractError(f"{location}: JSON array length changed")
        for index, (left, right) in enumerate(zip(expected, actual)):
            compare_json_value(left, right, f"{location}[{index}]", relative_tolerance)
        return
    if isinstance(expected, float):
        if not same_source_number(expected, actual, relative_tolerance):
            raise ContractError(
                f"{location}: same-source value changed {expected:.17g} -> {actual:.17g}"
            )
        return
    if expected != actual:
        raise ContractError(f"{location}: JSON value changed")


def same_source_number(
    first: float, second: float, relative_tolerance: float = DEFAULT_RELATIVE_TOLERANCE
) -> bool:
    scale = max(1.0, abs(first), abs(second))
    ulp = max(math.ulp(first), math.ulp(second))
    return abs(first - second) <= 8 * ulp + relative_tolerance * scale


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--allow-missing", action="store_true")
    arguments = parser.parse_args()
    compare(arguments.baseline, arguments.candidate, arguments.allow_missing)


if __name__ == "__main__":
    main()
