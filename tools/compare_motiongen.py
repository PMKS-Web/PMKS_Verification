#!/usr/bin/env python3
"""Corroborate canonical mechanisms against committed normalized MotionGen exports."""

from __future__ import annotations

import argparse
import csv
import hashlib
import math
from dataclasses import dataclass
from pathlib import Path

from reference_data import (
    ContractError,
    LINK_HEADER,
    POINT_HEADER,
    case_directories,
    circular_difference,
    dump_json,
    load_json,
    read_samples,
    rows_by_id,
)

MG_JOINT_HEADER = ("sample_id", "time_s", "x", "y", "speed", "acceleration")
MG_LINK_HEADER = ("sample_id", "time_s", "theta_rad", "omega_rad_s", "alpha_rad_s2")


@dataclass(frozen=True)
class MotionSeries:
    angles: list[float]
    rows: list[dict[str, str]]
    receipt: dict


def compare_case(case_root: Path, repo_root: Path) -> dict | None:
    manifest = load_json(case_root / "case.json")
    applicable = manifest["capabilities"]["motiongen"]
    motion_root = case_root / "motiongen"
    if not applicable:
        if motion_root.exists():
            raise ContractError(f"{manifest['case_id']}: MotionGen data is not applicable")
        return None
    if not motion_root.is_dir():
        raise ContractError(f"{manifest['case_id']}: required MotionGen fixtures are missing")

    matlab_samples = read_samples(case_root / "matlab" / "samples.csv")
    motion_samples = read_samples(motion_root / "samples.csv")
    positive_sweep = []
    first_sweep = matlab_samples[0].sweep_id
    for sample in matlab_samples:
        if sample.sweep_id != first_sweep:
            break
        positive_sweep.append(sample)
    if len(positive_sweep) != 360 or any(sample.direction != 1 for sample in positive_sweep):
        raise ContractError(f"{manifest['case_id']}: MotionGen expects a 360-row positive canonical sweep")

    motion_angles = unwrap([sample.input_angle for sample in motion_samples])
    compared = 0
    maximum_ratio = 0.0
    maximum_detail = ""
    excluded_terminal_cells: list[str] = []

    joint_ids = [joint["id"] for joint in manifest["topology"]["joints"]]
    point_ids = [point["id"] for point in manifest["topology"]["points"]]
    for category, identifiers in (("joints", joint_ids), ("points", point_ids)):
        for identifier in identifiers:
            motion_identifier = "B" if manifest["case_id"] == "teaching_slider_crank" and identifier == "E" else identifier
            matlab_category = category
            matlab_rows = rows_by_id(case_root / "matlab" / matlab_category / f"{identifier}.csv", POINT_HEADER)
            motion = load_motion_series(
                motion_root,
                "joint",
                motion_identifier,
                motion_angles,
                MG_JOINT_HEADER,
                repo_root,
            )
            for sample in positive_sweep:
                expected = matlab_rows[sample.sample_id]
                for field, expected_value, bound_name in (
                    ("x", float(expected["x"]), "position"),
                    ("y", float(expected["y"]), "position"),
                    ("speed", math.hypot(float(expected["vx"]), float(expected["vy"])), "speed"),
                    (
                        "acceleration",
                        math.hypot(float(expected["ax"]), float(expected["ay"])),
                        "acceleration",
                    ),
                ):
                    actual, interpolation_bound, terminal = interpolate(
                        motion, sample.input_angle, field
                    )
                    if terminal and field in motion.receipt.get("terminal_null_columns", []):
                        excluded_terminal_cells.append(f"{identifier}:{sample.sample_id}:{field}")
                        continue
                    bound = float(motion.receipt["quantization_bound"][bound_name]) + 2 * interpolation_bound
                    ratio = abs(actual - expected_value) / max(bound, 1e-15)
                    compared += 1
                    if ratio > maximum_ratio:
                        maximum_ratio = ratio
                        maximum_detail = f"{identifier}:{sample.sample_id}:{field}"
                    if ratio > 1:
                        raise ContractError(
                            f"{manifest['case_id']}: MotionGen disagreement at {maximum_detail}; "
                            f"actual={actual:.17g}, expected={expected_value:.17g}, bound={bound:.6g}"
                        )

    for link in manifest["topology"]["links"]:
        identifier = link["id"]
        matlab_rows = rows_by_id(case_root / "matlab" / "links" / f"{identifier}.csv", LINK_HEADER)
        motion = load_motion_series(
            motion_root, "link", identifier, motion_angles, MG_LINK_HEADER, repo_root
        )
        theta = unwrap([float(row["theta_rad"]) for row in motion.rows])
        initial_theta = theta[0]
        for row, value in zip(motion.rows, theta):
            row["theta_delta_rad"] = str(value - initial_theta)
        for sample in positive_sweep:
            expected = matlab_rows[sample.sample_id]
            for field, expected_field, bound_name in (
                ("theta_delta_rad", "theta_delta_rad", "angle"),
                ("omega_rad_s", "omega_rad_s", "angular_velocity"),
                ("alpha_rad_s2", "alpha_rad_s2", "angular_acceleration"),
            ):
                actual, interpolation_bound, terminal = interpolate(motion, sample.input_angle, field)
                if terminal and field in motion.receipt.get("terminal_null_columns", []):
                    excluded_terminal_cells.append(f"{identifier}:{sample.sample_id}:{field}")
                    continue
                expected_value = float(expected[expected_field])
                bound = float(motion.receipt["quantization_bound"][bound_name]) + 2 * interpolation_bound
                difference = (
                    circular_difference(actual, expected_value)
                    if field == "theta_delta_rad"
                    else abs(actual - expected_value)
                )
                ratio = difference / max(bound, 1e-15)
                compared += 1
                if ratio > maximum_ratio:
                    maximum_ratio = ratio
                    maximum_detail = f"{identifier}:{sample.sample_id}:{field}"
                if ratio > 1:
                    raise ContractError(
                        f"{manifest['case_id']}: MotionGen disagreement at {maximum_detail}; "
                        f"actual={actual:.17g}, expected={expected_value:.17g}, bound={bound:.6g}"
                    )

    report = {
        "schema_version": 1,
        "case_id": manifest["case_id"],
        "status": "pass",
        "trust": "matlab-pmks-motiongen",
        "compared_values": compared,
        "maximum_tolerance_ratio": maximum_ratio,
        "maximum_tolerance_detail": maximum_detail,
        "excluded_terminal_cells": excluded_terminal_cells,
        "magnitude_only": ["joint speed", "joint acceleration"],
        "direction_oracle": "pmks",
    }
    dump_json(case_root / "motiongen-comparison-report.json", report)
    return report


def load_motion_series(
    motion_root: Path,
    kind: str,
    identifier: str,
    angles: list[float],
    header: tuple[str, ...],
    repo_root: Path,
) -> MotionSeries:
    plural = "joints" if kind == "joint" else "links"
    data_path = motion_root / plural / f"{identifier}.csv"
    with data_path.open(newline="", encoding="utf-8") as stream:
        reader = csv.DictReader(stream)
        if tuple(reader.fieldnames or ()) != header:
            raise ContractError(f"{data_path}: unexpected MotionGen header")
        rows = list(reader)
    if len(rows) != len(angles):
        raise ContractError(f"{data_path}: row count differs from MotionGen samples")
    receipt_path = motion_root / "receipts" / f"{kind}-{identifier}.json"
    receipt = load_json(receipt_path)
    normalizer = repo_root / "tools" / "motiongen" / "normalize_xlsx.mjs"
    normalizer_hash = hashlib.sha256(normalizer.read_bytes()).hexdigest()
    if receipt.get("normalization_script_sha256") != normalizer_hash:
        raise ContractError(f"{receipt_path}: stale normalizer provenance")
    if receipt.get("graph") != {"kind": kind, "id": identifier}:
        raise ContractError(f"{receipt_path}: graph identity mismatch")
    if not receipt.get("original_discarded") or not receipt.get("original_xlsx_sha256"):
        raise ContractError(f"{receipt_path}: XLSX discard/hash receipt incomplete")
    return MotionSeries(angles, rows, receipt)


def interpolate(series: MotionSeries, target_angle: float, field: str) -> tuple[float, float, bool]:
    angles = series.angles
    target = target_angle
    midpoint = 0.5 * (angles[0] + angles[-1])
    target += round((midpoint - target) / (2 * math.pi)) * 2 * math.pi
    if target < angles[0] - 1e-10 or target > angles[-1] + 1e-10:
        raise ContractError(f"MotionGen angle {target_angle:.17g} is outside retained sweep")
    upper = next((index for index, angle in enumerate(angles) if angle >= target), len(angles) - 1)
    lower = max(0, upper - 1)
    if abs(angles[upper] - target) < 1e-12:
        lower = upper
    first = float(series.rows[lower][field])
    second = float(series.rows[upper][field])
    if upper == lower:
        value = first
    else:
        fraction = (target - angles[lower]) / (angles[upper] - angles[lower])
        value = first + fraction * (second - first)
    local = []
    for center in range(max(1, lower - 1), min(len(series.rows) - 1, upper + 2)):
        previous = float(series.rows[center - 1][field])
        current = float(series.rows[center][field])
        following = float(series.rows[center + 1][field])
        local.append(abs(following - 2 * current + previous))
    interpolation_bound = max(local, default=0.0)
    return value, interpolation_bound, upper == len(series.rows) - 1


def unwrap(values: list[float]) -> list[float]:
    result = values[:]
    for index in range(1, len(result)):
        while result[index] - result[index - 1] > math.pi:
            result[index] -= 2 * math.pi
        while result[index] - result[index - 1] < -math.pi:
            result[index] += 2 * math.pi
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    arguments = parser.parse_args()
    reports = 0
    for case_root in case_directories(arguments.root):
        report = compare_case(case_root, arguments.repo_root.resolve())
        if report:
            reports += 1
            print(
                f"PASS MotionGen: {case_root.name} "
                f"(max ratio {report['maximum_tolerance_ratio']:.4g})"
            )
    if reports != 2:
        raise ContractError(f"Expected two MotionGen cases, checked {reports}")


if __name__ == "__main__":
    main()
