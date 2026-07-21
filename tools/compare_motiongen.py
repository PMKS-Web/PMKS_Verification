#!/usr/bin/env python3
"""Corroborate canonical mechanisms against committed normalized MotionGen exports."""

from __future__ import annotations

import argparse
import bisect
import csv
import hashlib
import math
from datetime import datetime
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
    validate_float_token,
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
    expected_motion_rows = int(manifest["motiongen"]["actuation"]["graph_rows"])
    if len(motion_samples) != expected_motion_rows:
        raise ContractError(
            f"{manifest['case_id']}: expected {expected_motion_rows} MotionGen rows, "
            f"found {len(motion_samples)}"
        )
    for index, sample in enumerate(motion_samples):
        if (
            sample.sample_id != f"motiongen_{index:04d}"
            or sample.direction != 1
            or sample.eligibility != "eligible"
            or sample.condition != 0
            or (index and sample.time <= motion_samples[index - 1].time)
        ):
            raise ContractError(f"{manifest['case_id']}: invalid MotionGen sample row {index}")
    positive_sweep = []
    first_sweep = matlab_samples[0].sweep_id
    for sample in matlab_samples:
        if sample.sweep_id != first_sweep:
            break
        positive_sweep.append(sample)
    if len(positive_sweep) != 360 or any(sample.direction != 1 for sample in positive_sweep):
        raise ContractError(f"{manifest['case_id']}: MotionGen expects a 360-row positive canonical sweep")

    motion_angles = unwrap([sample.input_angle for sample in motion_samples])
    source_phase_step = float(manifest["motiongen"]["actuation"]["speed_rad_s"]) / float(
        manifest["motiongen"]["actuation"]["sample_rate_hz"]
    )
    first_cycle = math.ceil(
        (motion_angles[0] - (min(sample.input_angle for sample in positive_sweep) - source_phase_step))
        / (2 * math.pi)
    )
    last_cycle = math.floor(
        (motion_angles[-1] - max(sample.input_angle for sample in positive_sweep))
        / (2 * math.pi)
    )
    motion_cycles = [(cycle, cycle * 2 * math.pi) for cycle in range(first_cycle, last_cycle + 1)]
    if not motion_cycles:
        raise ContractError(f"{manifest['case_id']}: no complete MotionGen cycle is comparable")
    compared = 0
    maximum_ratio = 0.0
    maximum_detail = ""
    excluded_terminal_cells: list[str] = []
    undefined_tangential_cells: list[str] = []
    disagreements: list[str] = []
    declared_motiongen_exclusions = manifest.get("motiongen_exclusions", [])
    used_motiongen_exclusions: set[str] = set()

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
                manifest,
            )
            for sample in positive_sweep:
                expected = matlab_rows[sample.sample_id]
                vx = float(expected["vx"])
                vy = float(expected["vy"])
                ax = float(expected["ax"])
                ay = float(expected["ay"])
                speed = math.hypot(vx, vy)
                tangential_acceleration = tangential_component(vx, vy, ax, ay)
                for field, expected_value, bound_name in (
                    ("x", float(expected["x"]), "position"),
                    ("y", float(expected["y"]), "position"),
                    ("speed", speed, "speed"),
                    ("acceleration", tangential_acceleration, "acceleration"),
                ):
                    if expected_value is None:
                        exclusion = require_motiongen_exclusion(
                            manifest,
                            declared_motiongen_exclusions,
                            identifier,
                            sample.sample_id,
                            sample.input_angle,
                            speed,
                        )
                        used_motiongen_exclusions.add(exclusion["id"])
                        if exclusion["id"] not in undefined_tangential_cells:
                            undefined_tangential_cells.append(exclusion["id"])
                        continue
                    phase_offset = derivative_phase_offset(
                        field,
                        float(motion.receipt["actuation"]["source_rad_s"]),
                        float(manifest["motiongen"]["actuation"]["sample_rate_hz"]),
                    )
                    for cycle, cycle_offset in motion_cycles:
                        actual, interpolation_bound, local_slope, terminal = interpolate(
                            motion, sample.input_angle + cycle_offset - phase_offset, field
                        )
                        detail = f"{identifier}:{sample.sample_id}:{field}:cycle_{cycle:02d}"
                        if terminal and field in motion.receipt.get("terminal_null_columns", []):
                            excluded_terminal_cells.append(detail)
                            continue
                        bound = (
                            float(motion.receipt["quantization_bound"][bound_name])
                            * (
                                1
                                + float(
                                    manifest["motiongen"]["tolerance"][
                                        "source_numeric_guard_fraction_of_ordinate_quantization"
                                    ]
                                )
                            )
                            + local_slope * float(motion.receipt["quantization_bound"]["angle"])
                            + 2 * interpolation_bound
                        )
                        ratio = abs(actual - expected_value) / max(bound, 1e-15)
                        compared += 1
                        if ratio > maximum_ratio:
                            maximum_ratio = ratio
                            maximum_detail = detail
                        if ratio > 1:
                            disagreements.append(
                                f"{detail} actual={actual:.17g} expected={expected_value:.17g} "
                                f"bound={bound:.6g}"
                            )

    for link in manifest["topology"]["links"]:
        identifier = link["id"]
        matlab_rows = rows_by_id(case_root / "matlab" / "links" / f"{identifier}.csv", LINK_HEADER)
        motion = load_motion_series(
            motion_root,
            "link",
            identifier,
            motion_angles,
            MG_LINK_HEADER,
            repo_root,
            manifest,
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
                phase_offset = derivative_phase_offset(
                    field,
                    float(motion.receipt["actuation"]["source_rad_s"]),
                    float(manifest["motiongen"]["actuation"]["sample_rate_hz"]),
                )
                expected_value = float(expected[expected_field])
                for cycle, cycle_offset in motion_cycles:
                    actual, interpolation_bound, local_slope, terminal = interpolate(
                        motion, sample.input_angle + cycle_offset - phase_offset, field
                    )
                    detail = f"{identifier}:{sample.sample_id}:{field}:cycle_{cycle:02d}"
                    if terminal and field in motion.receipt.get("terminal_null_columns", []):
                        excluded_terminal_cells.append(detail)
                        continue
                    ordinate_quantization = float(
                        motion.receipt["quantization_bound"][bound_name]
                    )
                    if field == "theta_delta_rad":
                        ordinate_quantization *= 2
                    bound = (
                        ordinate_quantization
                        * (
                            1
                            + float(
                                manifest["motiongen"]["tolerance"][
                                    "source_numeric_guard_fraction_of_ordinate_quantization"
                                ]
                            )
                        )
                        + local_slope * float(motion.receipt["quantization_bound"]["angle"])
                        + 2 * interpolation_bound
                    )
                    difference = (
                        circular_difference(actual, expected_value)
                        if field == "theta_delta_rad"
                        else abs(actual - expected_value)
                    )
                    ratio = difference / max(bound, 1e-15)
                    compared += 1
                    if ratio > maximum_ratio:
                        maximum_ratio = ratio
                        maximum_detail = detail
                    if ratio > 1:
                        disagreements.append(
                            f"{detail} actual={actual:.17g} expected={expected_value:.17g} "
                            f"bound={bound:.6g}"
                        )

    if disagreements:
        examples = "; ".join(disagreements[:5])
        raise ContractError(
            f"{manifest['case_id']}: {len(disagreements)} MotionGen disagreements; "
            f"maximum ratio={maximum_ratio:.6g} at {maximum_detail}; examples: {examples}"
        )
    unused_motiongen_exclusions = sorted(
        exclusion["id"]
        for exclusion in declared_motiongen_exclusions
        if exclusion["id"] not in used_motiongen_exclusions
    )
    if unused_motiongen_exclusions:
        raise ContractError(
            f"{manifest['case_id']}: unused/stale MotionGen exclusions "
            f"{unused_motiongen_exclusions}"
        )

    report = {
        "schema_version": 1,
        "case_id": manifest["case_id"],
        "status": "pass",
        "trust": "matlab-pmks-fork-motiongen",
        "compared_values": compared,
        "motiongen_cycles_compared": [cycle for cycle, _ in motion_cycles],
        "maximum_tolerance_ratio": maximum_ratio,
        "maximum_tolerance_detail": maximum_detail,
        "excluded_terminal_cells": excluded_terminal_cells,
        "undefined_tangential_cells": undefined_tangential_cells,
        "scalar_channels": ["joint speed magnitude", "joint tangential acceleration"],
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
    manifest: dict,
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
    stable = manifest["motiongen"]
    expected_receipt = {
        "case_id": manifest["case_id"],
        "model_url": stable["model_url"],
        "model_id": stable["model_id"],
        "model_title": stable["model_title"],
        "model_access": stable["model_access"],
        "motiongen_app_version": stable["app_version"],
        "source_units": stable["source_units"],
    }
    for key, expected in expected_receipt.items():
        if receipt.get(key) != expected:
            raise ContractError(f"{receipt_path}: stale or mismatched {key}")
    actuation = receipt.get("actuation", {})
    stable_actuation = stable["actuation"]
    if (
        actuation.get("profile") != stable_actuation["profile"]
        or abs(float(actuation.get("source_rpm", 0)) - float(stable_actuation["rpm"])) > 1e-12
        or abs(float(actuation.get("target_rpm", 0)) - float(stable_actuation["rpm"])) > 1e-12
        or abs(float(actuation.get("source_rad_s", 0)) - float(stable_actuation["speed_rad_s"])) > 1e-12
        or abs(float(actuation.get("target_rad_s", 0)) - float(stable_actuation["speed_rad_s"])) > 1e-12
    ):
        raise ContractError(f"{receipt_path}: actuation provenance mismatch")
    transform = receipt.get("coordinate_transform", {})
    expected_transform = stable["coordinate_transform"]
    if (
        transform.get("rotation") != expected_transform["rotation"]
        or transform.get("translation") != expected_transform["translation"]
        or abs(float(transform.get("spatial_scale", 0)) - float(expected_transform["spatial_scale"])) > 1e-15
        or abs(float(transform.get("speed_ratio", 0)) - 1) > 1e-15
    ):
        raise ContractError(f"{receipt_path}: coordinate transform mismatch")
    expected_columns = (
        ["speed", "acceleration"]
        if kind == "joint"
        else ["omega_rad_s", "alpha_rad_s2"]
    )
    if receipt.get("terminal_null_columns") != expected_columns:
        raise ContractError(f"{receipt_path}: terminal-null declaration mismatch")
    expected_sheet_header = (
        [
            "Time [s]",
            "x [in]",
            "y [in]",
            "Displacement [in]",
            "Linear Vel. [in/s]",
            "Linear Accel. [in/s^2]",
        ]
        if kind == "joint"
        else [
            "Time [s]",
            "Theta [rad]",
            "Angular Vel. [rad/s]",
            "Angular Accel. [rad/s^2]",
        ]
    )
    if receipt.get("sheets") != [
        {"name": "Sheet1", "header": expected_sheet_header, "row_count": len(rows)}
    ]:
        raise ContractError(f"{receipt_path}: sheet/header inventory mismatch")
    if not str(receipt.get("original_filename", "")).endswith(".xlsx"):
        raise ContractError(f"{receipt_path}: original XLSX filename missing")
    try:
        datetime.fromisoformat(str(receipt["download_time_utc"]).replace("Z", "+00:00"))
    except (KeyError, ValueError) as error:
        raise ContractError(f"{receipt_path}: invalid download timestamp") from error
    data_hash = hashlib.sha256(data_path.read_bytes()).hexdigest()
    if receipt.get("normalized_csv_sha256") != data_hash:
        raise ContractError(f"{receipt_path}: normalized CSV content hash mismatch")
    for row_index, row in enumerate(rows, 2):
        if row["sample_id"] != f"motiongen_{row_index - 2:04d}":
            raise ContractError(f"{data_path}:{row_index}: MotionGen sample order mismatch")
        for column in header[1:]:
            validate_float_token(row[column], data_path, row_index, column)
    return MotionSeries(angles, rows, receipt)


def require_motiongen_exclusion(
    manifest: dict,
    exclusions: list[dict],
    identifier: str,
    sample_id: str,
    input_angle: float,
    source_speed: float,
) -> dict:
    series = f"joint:{identifier}:tangential_acceleration"
    matches = [
        exclusion
        for exclusion in exclusions
        if exclusion.get("sample_id") == sample_id and exclusion.get("series") == series
    ]
    if len(matches) != 1:
        raise ContractError(
            f"{manifest['case_id']}: expected one MotionGen exclusion for {sample_id}/{series}"
        )
    exclusion = matches[0]
    required = {"id", "sample_id", "series", "input_angle_rad", "source_speed", "reason"}
    if required - exclusion.keys():
        raise ContractError(f"{manifest['case_id']}: incomplete MotionGen exclusion {exclusion}")
    if abs(float(exclusion["input_angle_rad"]) - input_angle) > 1e-12:
        raise ContractError(f"{manifest['case_id']}: MotionGen exclusion angle mismatch")
    if abs(float(exclusion["source_speed"]) - source_speed) > 1e-12 or source_speed > 1e-12:
        raise ContractError(f"{manifest['case_id']}: MotionGen exclusion is not zero-speed backed")
    return exclusion


def tangential_component(vx: float, vy: float, ax: float, ay: float) -> float | None:
    speed = math.hypot(vx, vy)
    acceleration = math.hypot(ax, ay)
    if speed > 1e-12:
        return (vx * ax + vy * ay) / speed
    if acceleration <= 1e-12:
        return 0.0
    return None


def derivative_phase_offset(field: str, input_speed: float, sample_rate: float) -> float:
    phase_step = input_speed / sample_rate
    if field in {"speed", "omega_rad_s"}:
        return phase_step / 2
    if field in {"acceleration", "alpha_rad_s2"}:
        return phase_step
    return 0.0


def interpolate(
    series: MotionSeries, target_angle: float, field: str
) -> tuple[float, float, float, bool]:
    angles = series.angles
    target = target_angle
    if target < angles[0] - 1e-10 or target > angles[-1] + 1e-10:
        raise ContractError(f"MotionGen angle {target_angle:.17g} is outside retained sweep")
    upper = min(bisect.bisect_left(angles, target), len(angles) - 1)
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
    slopes = []
    for center in range(max(1, lower - 1), min(len(series.rows) - 1, upper + 2)):
        previous = float(series.rows[center - 1][field])
        current = float(series.rows[center][field])
        following = float(series.rows[center + 1][field])
        local.append(abs(following - 2 * current + previous))
        previous_angle = angles[center - 1]
        following_angle = angles[center + 1]
        if following_angle != previous_angle:
            slopes.append(abs(following - previous) / abs(following_angle - previous_angle))
    interpolation_bound = max(local, default=0.0)
    local_slope = max(slopes, default=0.0)
    return value, interpolation_bound, local_slope, upper == len(series.rows) - 1


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
