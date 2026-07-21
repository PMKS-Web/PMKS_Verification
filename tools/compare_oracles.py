#!/usr/bin/env python3
"""Align MATLAB sweeps to pinned PMKS branches and compare every eligible row."""

from __future__ import annotations

import argparse
import math
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

from reference_data import (
    ContractError,
    LINK_HEADER,
    POINT_HEADER,
    PRISMATIC_HEADER,
    Sample,
    case_directories,
    circular_difference,
    dump_json,
    load_json,
    read_samples,
    rows_by_id,
    scaled_error,
    signed_area,
    tolerance,
    write_csv,
)


@dataclass(frozen=True)
class Alignment:
    matlab: Sample
    pmks: Sample | None
    status: str
    reason: str = ""


class Comparison:
    def __init__(self, manifest: dict) -> None:
        self.manifest = manifest
        self.compared_values = 0
        self.max_scaled_error = 0.0
        self.max_detail = ""
        self.exclusions_used: set[str] = set()

    def value(
        self,
        actual: float,
        expected: float,
        quantity: str,
        detail: str,
        circular: bool = False,
    ) -> None:
        absolute, relative = tolerance(self.manifest, quantity)
        if circular:
            difference = circular_difference(actual, expected)
            limit = absolute + relative * max(abs(actual), abs(expected))
            error = difference / limit
        else:
            error = scaled_error(actual, expected, absolute, relative)
        self.compared_values += 1
        if error > self.max_scaled_error:
            self.max_scaled_error = error
            self.max_detail = detail
        if error > 1:
            raise ContractError(
                f"{self.manifest['case_id']}: unexplained {quantity} disagreement at {detail}; "
                f"actual={actual:.17g}, expected={expected:.17g}, scaled_error={error:.6g}"
            )


class SpeedSymmetryComparison:
    """Check PMKS +/- speed symmetry using the documented same-source tier."""

    RELATIVE_TOLERANCE = 8e-12

    def __init__(self, case_id: str) -> None:
        self.case_id = case_id
        self.compared_values = 0
        self.max_scaled_error = 0.0
        self.max_detail = ""

    def value(
        self,
        actual: float,
        expected: float,
        detail: str,
        circular: bool = False,
    ) -> None:
        if not math.isfinite(actual) or not math.isfinite(expected):
            raise ContractError(f"{self.case_id}: nonfinite PMKS speed-symmetry value at {detail}")
        difference = (
            circular_difference(actual, expected) if circular else abs(actual - expected)
        )
        scale = max(1.0, abs(actual), abs(expected))
        limit = (
            8 * max(math.ulp(actual), math.ulp(expected))
            + self.RELATIVE_TOLERANCE * scale
        )
        error = difference / limit
        self.compared_values += 1
        if error > self.max_scaled_error:
            self.max_scaled_error = error
            self.max_detail = detail
        if error > 1:
            raise ContractError(
                f"{self.case_id}: PMKS speed-symmetry disagreement at {detail}; "
                f"actual={actual:.17g}, expected={expected:.17g}, scaled_error={error:.6g}"
            )


def compare_case(case_root: Path) -> dict:
    manifest = load_json(case_root / "case.json")
    matlab_samples = read_samples(case_root / "matlab" / "samples.csv")
    pmks_samples = read_samples(case_root / "pmks" / "samples.csv")
    validate_expected_sweeps(manifest, matlab_samples)
    alignments = align_samples(manifest, matlab_samples, pmks_samples)
    compare = Comparison(manifest)
    for alignment in alignments:
        if alignment.pmks is None:
            exclusion = find_exclusion(manifest, alignment.matlab.sample_id, "alignment")
            if exclusion:
                compare.exclusions_used.add(exclusion["id"])
    validate_assembly_branch(case_root, manifest, matlab_samples, pmks_samples)
    validate_slider_axis(case_root, manifest, "matlab", matlab_samples, compare)
    validate_slider_axis(case_root, manifest, "pmks", pmks_samples, compare)
    compare_point_sources(case_root, manifest, alignments, compare)
    compare_link_sources(case_root, manifest, alignments, compare)
    symmetry = verify_pmks_row_coverage(
        case_root, manifest, pmks_samples, alignments
    )
    verify_exclusion_accounting(manifest, compare)

    write_csv(
        case_root / "alignment.csv",
        (
            "matlab_sample_id",
            "matlab_sweep_id",
            "matlab_sweep_index",
            "input_angle_rad",
            "input_direction",
            "jacobian_condition",
            "eligibility",
            "pmks_sample_id",
            "status",
            "reason",
        ),
        (
            (
                alignment.matlab.sample_id,
                alignment.matlab.sweep_id,
                alignment.matlab.sweep_index,
                alignment.matlab.input_angle,
                alignment.matlab.direction,
                alignment.matlab.condition,
                alignment.matlab.eligibility,
                alignment.pmks.sample_id if alignment.pmks else "",
                alignment.status,
                alignment.reason,
            )
            for alignment in alignments
        ),
    )
    report = {
        "schema_version": 1,
        "case_id": manifest["case_id"],
        "status": "pass",
        "matlab_rows": len(matlab_samples),
        "aligned_rows": sum(alignment.pmks is not None for alignment in alignments),
        "excluded_alignment_rows": sum(alignment.pmks is None for alignment in alignments),
        "pmks_rows": len(pmks_samples),
        "pmks_matlab_aligned_unique_rows": len(
            {alignment.pmks.sample_id for alignment in alignments if alignment.pmks is not None}
        ),
        "pmks_speed_symmetry_rows": symmetry["rows"],
        "pmks_unverified_rows": symmetry["unverified_rows"],
        "pmks_speed_symmetry_status": "pass",
        "pmks_speed_symmetry_compared_values": symmetry["comparison"].compared_values,
        "compared_values": compare.compared_values,
        "max_scaled_error": compare.max_scaled_error,
        "max_scaled_error_detail": compare.max_detail,
        "used_exclusions": sorted(compare.exclusions_used),
        "trust": manifest["trust"],
    }
    dump_json(case_root / "comparison-report.json", report)
    return report


def verify_pmks_row_coverage(
    case_root: Path,
    manifest: dict,
    pmks_samples: list[Sample],
    alignments: list[Alignment],
) -> dict:
    """Corroborate PMKS rows not directly consumed by MATLAB through speed symmetry."""
    aligned_ids = {
        alignment.pmks.sample_id for alignment in alignments if alignment.pmks is not None
    }
    aligned_samples = [sample for sample in pmks_samples if sample.sample_id in aligned_ids]
    unaligned_samples = [sample for sample in pmks_samples if sample.sample_id not in aligned_ids]
    comparison = SpeedSymmetryComparison(manifest["case_id"])
    counterparts: dict[str, Sample] = {}
    used_counterparts: set[str] = set()
    for sample in unaligned_samples:
        candidates = [
            candidate
            for candidate in aligned_samples
            if candidate.direction == -sample.direction
            and circular_difference(candidate.input_angle, sample.input_angle) <= 1e-10
        ]
        if len(candidates) != 1:
            raise ContractError(
                f"{manifest['case_id']}: PMKS row {sample.sample_id} has {len(candidates)} "
                "aligned opposite-speed counterparts; expected exactly one"
            )
        counterpart = candidates[0]
        if counterpart.sample_id in used_counterparts:
            raise ContractError(
                f"{manifest['case_id']}: PMKS symmetry counterpart "
                f"{counterpart.sample_id} is reused"
            )
        used_counterparts.add(counterpart.sample_id)
        counterparts[sample.sample_id] = counterpart
        if sample.eligibility != counterpart.eligibility:
            raise ContractError(
                f"{manifest['case_id']}: PMKS eligibility changes with speed direction at "
                f"{sample.sample_id}/{counterpart.sample_id}"
            )
        comparison.value(
            sample.condition,
            counterpart.condition,
            f"{sample.sample_id}:samples:jacobian_condition",
        )

    compare_pmks_point_symmetry(case_root, manifest, counterparts, comparison)
    compare_pmks_link_symmetry(case_root, manifest, counterparts, comparison)
    compare_pmks_prismatic_symmetry(case_root, manifest, counterparts, comparison)

    covered = aligned_ids | set(counterparts)
    missing = sorted(sample.sample_id for sample in pmks_samples if sample.sample_id not in covered)
    if missing:
        raise ContractError(f"{manifest['case_id']}: unverified PMKS rows: {missing}")
    return {
        "rows": len(counterparts),
        "unverified_rows": len(missing),
        "comparison": comparison,
    }


def compare_pmks_point_symmetry(
    case_root: Path,
    manifest: dict,
    counterparts: dict[str, Sample],
    comparison: SpeedSymmetryComparison,
) -> None:
    categories: list[tuple[str, list[str]]] = [
        ("joints", [joint["id"] for joint in manifest["topology"]["joints"]]),
        ("points", [point["id"] for point in manifest["topology"]["points"]]),
        (
            "com",
            [
                link
                for link in manifest.get("mass_properties", {})
                if link in {spec["id"] for spec in manifest["topology"]["links"]}
            ],
        ),
    ]
    signs = {"x": 1, "y": 1, "vx": -1, "vy": -1, "ax": 1, "ay": 1}
    for category, identifiers in categories:
        for identifier in identifiers:
            rows = rows_by_id(
                case_root / "pmks" / category / f"{identifier}.csv", POINT_HEADER
            )
            compare_pmks_rows(
                rows, counterparts, signs, comparison, f"{category}:{identifier}"
            )


def compare_pmks_link_symmetry(
    case_root: Path,
    manifest: dict,
    counterparts: dict[str, Sample],
    comparison: SpeedSymmetryComparison,
) -> None:
    signs = {"theta_delta_rad": 1, "omega_rad_s": -1, "alpha_rad_s2": 1}
    for link in manifest["topology"]["links"]:
        identifier = link["id"]
        rows = rows_by_id(
            case_root / "pmks" / "links" / f"{identifier}.csv", LINK_HEADER
        )
        compare_pmks_rows(
            rows,
            counterparts,
            signs,
            comparison,
            f"links:{identifier}",
            circular_columns={"theta_delta_rad"},
        )


def compare_pmks_prismatic_symmetry(
    case_root: Path,
    manifest: dict,
    counterparts: dict[str, Sample],
    comparison: SpeedSymmetryComparison,
) -> None:
    if not manifest["capabilities"]["prismatic"]:
        return
    signs = {"position": 1, "velocity": -1, "acceleration": 1}
    for joint in manifest["topology"]["joints"]:
        if joint["type"] != "P":
            continue
        rows = rows_by_id(
            case_root / "pmks" / "prismatic" / f"{joint['id']}.csv",
            PRISMATIC_HEADER,
        )
        compare_pmks_rows(
            rows, counterparts, signs, comparison, f"prismatic:{joint['id']}"
        )


def compare_pmks_rows(
    rows: dict[str, dict[str, str]],
    counterparts: dict[str, Sample],
    signs: dict[str, int],
    comparison: SpeedSymmetryComparison,
    series: str,
    circular_columns: set[str] | None = None,
) -> None:
    circular_columns = circular_columns or set()
    for sample_id, counterpart in counterparts.items():
        actual = rows[sample_id]
        expected = rows[counterpart.sample_id]
        for column, multiplier in signs.items():
            comparison.value(
                float(actual[column]),
                multiplier * float(expected[column]),
                f"{sample_id}:{series}:{column}",
                circular=column in circular_columns,
            )


def validate_expected_sweeps(manifest: dict, samples: list[Sample]) -> None:
    grouped: list[list[Sample]] = []
    for sample in samples:
        if not grouped or grouped[-1][0].sweep_id != sample.sweep_id:
            grouped.append([])
        grouped[-1].append(sample)
    expected = manifest["input"]["expected_sweeps"]
    actual = [(group[0].direction, len(group)) for group in grouped]
    declared = [(int(sweep["direction"]), int(sweep["rows"])) for sweep in expected]
    if actual != declared:
        raise ContractError(
            f"{manifest['case_id']}: MATLAB sweep pattern {actual} != manifest {declared}"
        )


def align_samples(
    manifest: dict, matlab_samples: list[Sample], pmks_samples: list[Sample]
) -> list[Alignment]:
    pmks_by_direction = {
        direction: [sample for sample in pmks_samples if sample.direction == direction]
        for direction in (-1, 1)
    }
    by_sweep: dict[str, list[Sample]] = defaultdict(list)
    sweep_order: list[str] = []
    for sample in matlab_samples:
        if sample.sweep_id not in by_sweep:
            sweep_order.append(sample.sweep_id)
        by_sweep[sample.sweep_id].append(sample)

    threshold = float(manifest["jacobian"]["singular_condition_threshold"])
    result: list[Alignment] = []
    for sweep_id in sweep_order:
        sweep = by_sweep[sweep_id]
        branch = pmks_by_direction[sweep[0].direction]
        previous_index: int | None = None
        used: set[int] = set()
        for sample in sweep:
            candidates = sorted(
                (
                    (circular_difference(sample.input_angle, oracle.input_angle), index, oracle)
                    for index, oracle in enumerate(branch)
                    if index not in used
                ),
                key=lambda value: (value[0], value[1]),
            )
            if not candidates or candidates[0][0] > 1e-10:
                exclusion = find_exclusion(manifest, sample.sample_id, "alignment")
                if (
                    exclusion
                    and sample.condition > threshold
                    and neighbors_align(sweep, sample, branch)
                ):
                    result.append(Alignment(sample, None, "excluded", exclusion["reason"]))
                    continue
                raise ContractError(
                    f"{manifest['case_id']}: no PMKS angle match for eligible MATLAB row "
                    f"{sample.sample_id} ({sample.input_angle:.17g})"
                )
            _, index, oracle = candidates[0]
            if previous_index is not None and index != previous_index + 1:
                raise ContractError(
                    f"{manifest['case_id']}: PMKS branch skips/reorders rows in {sweep_id}: "
                    f"{previous_index} -> {index}"
                )
            used.add(index)
            previous_index = index
            result.append(Alignment(sample, oracle, "matched"))
    if len(result) != len(matlab_samples):
        raise ContractError(f"{manifest['case_id']}: incomplete alignment report")
    return result


def neighbors_align(sweep: list[Sample], sample: Sample, branch: list[Sample]) -> bool:
    index = sweep.index(sample)
    neighbors = [neighbor for neighbor in (index - 1, index + 1) if 0 <= neighbor < len(sweep)]
    return all(
        min(circular_difference(sweep[neighbor].input_angle, oracle.input_angle) for oracle in branch)
        <= 1e-10
        for neighbor in neighbors
    )


def compare_point_sources(
    case_root: Path,
    manifest: dict,
    alignments: list[Alignment],
    comparison: Comparison,
) -> None:
    categories: list[tuple[str, list[str]]] = [
        ("joints", [joint["id"] for joint in manifest["topology"]["joints"]]),
        ("points", [point["id"] for point in manifest["topology"]["points"]]),
    ]
    if manifest["trust"]["com"] != "diagnostic-only":
        physical = {link["id"] for link in manifest["topology"]["links"]}
        categories.append(
            ("com", [link for link in manifest.get("mass_properties", {}) if link in physical])
        )
    for category, identifiers in categories:
        for identifier in identifiers:
            matlab = rows_by_id(case_root / "matlab" / category / f"{identifier}.csv", POINT_HEADER)
            pmks = rows_by_id(case_root / "pmks" / category / f"{identifier}.csv", POINT_HEADER)
            for alignment in alignments:
                if alignment.pmks is None:
                    continue
                expected = matlab[alignment.matlab.sample_id]
                actual = pmks[alignment.pmks.sample_id]
                for column in ("x", "y"):
                    comparison.value(
                        float(actual[column]),
                        float(expected[column]),
                        "position",
                        f"{alignment.matlab.sample_id}:{category}:{identifier}:{column}",
                    )
                compare_derivative_pair(
                    manifest,
                    alignment,
                    comparison,
                    actual,
                    expected,
                    category,
                    identifier,
                    "velocity",
                    ("vx", "vy"),
                )
                compare_derivative_pair(
                    manifest,
                    alignment,
                    comparison,
                    actual,
                    expected,
                    category,
                    identifier,
                    "acceleration",
                    ("ax", "ay"),
                )


def compare_derivative_pair(
    manifest: dict,
    alignment: Alignment,
    comparison: Comparison,
    actual: dict[str, str],
    expected: dict[str, str],
    category: str,
    identifier: str,
    quantity: str,
    columns: tuple[str, str],
) -> None:
    series = f"{category}:{identifier}:{quantity}"
    exclusion = find_exclusion(manifest, alignment.matlab.sample_id, series)
    if exclusion:
        require_conditioned_exclusion(manifest, alignment, exclusion)
        comparison.exclusions_used.add(exclusion["id"])
        return
    for column in columns:
        comparison.value(
            float(actual[column]),
            float(expected[column]),
            quantity,
            f"{alignment.matlab.sample_id}:{category}:{identifier}:{column}",
        )


def compare_link_sources(
    case_root: Path,
    manifest: dict,
    alignments: list[Alignment],
    comparison: Comparison,
) -> None:
    quantities = {
        "theta_delta_rad": "angular_position",
        "omega_rad_s": "angular_velocity",
        "alpha_rad_s2": "angular_acceleration",
    }
    for link in manifest["topology"]["links"]:
        identifier = link["id"]
        matlab = rows_by_id(case_root / "matlab" / "links" / f"{identifier}.csv", LINK_HEADER)
        pmks = rows_by_id(case_root / "pmks" / "links" / f"{identifier}.csv", LINK_HEADER)
        for alignment in alignments:
            if alignment.pmks is None:
                continue
            expected = matlab[alignment.matlab.sample_id]
            actual = pmks[alignment.pmks.sample_id]
            for column, quantity in quantities.items():
                series = f"links:{identifier}:{quantity}"
                exclusion = find_exclusion(manifest, alignment.matlab.sample_id, series)
                if exclusion:
                    require_conditioned_exclusion(manifest, alignment, exclusion)
                    comparison.exclusions_used.add(exclusion["id"])
                    continue
                comparison.value(
                    float(actual[column]),
                    float(expected[column]),
                    quantity,
                    f"{alignment.matlab.sample_id}:links:{identifier}:{column}",
                    circular=(quantity == "angular_position"),
                )


def validate_assembly_branch(
    case_root: Path,
    manifest: dict,
    matlab_samples: list[Sample],
    pmks_samples: list[Sample],
) -> None:
    link = next(item for item in manifest["topology"]["links"] if item["id"] == manifest["input"]["link"])
    joints = {joint["id"]: joint for joint in manifest["topology"]["joints"]}
    first, second = (joints[identifier]["initial"] for identifier in link["angle_basis"])
    initial_angle = math.atan2(second[1] - first[1], second[0] - first[0])
    expected_signatures = [
        sign(signed_area([tuple(joints[identifier]["initial"]) for identifier in loop]))
        for loop in manifest["topology"]["independent_loops"]
    ]
    for source, samples in (("matlab", matlab_samples), ("pmks", pmks_samples)):
        initial = min(samples, key=lambda sample: circular_difference(sample.input_angle, initial_angle))
        series = {
            identifier: rows_by_id(
                case_root / source / "joints" / f"{identifier}.csv", POINT_HEADER
            )[initial.sample_id]
            for identifier in joints
        }
        actual = [
            sign(
                signed_area(
                    [(float(series[identifier]["x"]), float(series[identifier]["y"])) for identifier in loop]
                )
            )
            for loop in manifest["topology"]["independent_loops"]
        ]
        if actual != expected_signatures:
            raise ContractError(
                f"{manifest['case_id']}: {source} initial assembly signatures {actual} != {expected_signatures}"
            )


def validate_slider_axis(
    case_root: Path,
    manifest: dict,
    source: str,
    samples: list[Sample],
    comparison: Comparison,
) -> None:
    for joint in manifest["topology"]["joints"]:
        if joint["type"] != "P":
            continue
        axis = joint["guide_axis"]
        magnitude = math.hypot(*axis)
        normal = (-axis[1] / magnitude, axis[0] / magnitude)
        rows = rows_by_id(case_root / source / "joints" / f"{joint['id']}.csv", POINT_HEADER)
        initial = joint["initial"]
        for sample in samples:
            row = rows[sample.sample_id]
            perpendicular = (float(row["x"]) - initial[0]) * normal[0] + (float(row["y"]) - initial[1]) * normal[1]
            velocity = float(row["vx"]) * normal[0] + float(row["vy"]) * normal[1]
            acceleration = float(row["ax"]) * normal[0] + float(row["ay"]) * normal[1]
            for value, quantity in (
                (perpendicular, "position"),
                (velocity, "velocity"),
                (acceleration, "acceleration"),
            ):
                comparison.value(
                    value,
                    0.0,
                    quantity,
                    f"{sample.sample_id}:{source}:slider-axis:{quantity}",
                )


def find_exclusion(manifest: dict, sample_id: str, series: str) -> dict | None:
    matches = [
        exclusion
        for exclusion in manifest["exclusions"]
        if exclusion.get("sample_id") == sample_id and exclusion.get("series") == series
    ]
    if len(matches) > 1:
        raise ContractError(
            f"{manifest['case_id']}: duplicate exclusions for {sample_id}/{series}"
        )
    return matches[0] if matches else None


def require_conditioned_exclusion(manifest: dict, alignment: Alignment, exclusion: dict) -> None:
    threshold = float(manifest["jacobian"]["singular_condition_threshold"])
    if alignment.matlab.condition <= threshold and (
        alignment.pmks is None or alignment.pmks.condition <= threshold
    ):
        raise ContractError(
            f"{manifest['case_id']}: exclusion {exclusion['id']} is not conditioning-backed"
        )
    required = {"id", "sample_id", "series", "input_angle_rad", "reason"}
    if required - exclusion.keys():
        raise ContractError(
            f"{manifest['case_id']}: exclusion lacks exact sample/series/angle/reason: {exclusion}"
        )
    if abs(float(exclusion["input_angle_rad"]) - alignment.matlab.input_angle) > 1e-12:
        raise ContractError(f"{manifest['case_id']}: exclusion angle does not match its sample")


def verify_exclusion_accounting(manifest: dict, comparison: Comparison) -> None:
    declared = {exclusion["id"] for exclusion in manifest["exclusions"]}
    unused = sorted(declared - comparison.exclusions_used)
    if unused:
        raise ContractError(f"{manifest['case_id']}: unused/stale exclusions: {unused}")


def sign(value: float) -> int:
    if abs(value) < 1e-14:
        raise ContractError("assembly signature has zero signed area")
    return 1 if value > 0 else -1


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    arguments = parser.parse_args()
    for case_root in case_directories(arguments.root):
        report = compare_case(case_root)
        print(
            f"PASS MATLAB/PMKS: {case_root.name} "
            f"({report['aligned_rows']}/{report['matlab_rows']} rows, "
            f"max scaled error {report['max_scaled_error']:.4g})"
        )


if __name__ == "__main__":
    main()
