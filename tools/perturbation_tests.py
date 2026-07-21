#!/usr/bin/env python3
"""Prove independent gates detect the merge-risk perturbations named by the v1 contract."""

from __future__ import annotations

import argparse
import csv
import json
import shutil
import tempfile
from contextlib import contextmanager
from pathlib import Path
from typing import Callable, Iterator

from check_dynamics import check_case
from compare_oracles import compare_case
from compare_motiongen import compare_case as compare_motiongen_case
from reference_data import ContractError
from validate_provenance import validate as validate_provenance
from validate_v1 import validate_case


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--pmks-root", type=Path, required=True)
    arguments = parser.parse_args()
    source = arguments.root.resolve()

    tests: list[tuple[str, Callable[[Path], None], Callable[[Path], None]]] = [
        ("wrong assembly branch", perturb_branch, lambda root: compare_case(case(root, "teaching_four_bar"))),
        ("velocity sign", perturb_velocity, lambda root: compare_case(case(root, "teaching_four_bar"))),
        (
            "negative-speed branch",
            perturb_negative_speed_branch,
            lambda root: compare_case(case(root, "teaching_four_bar")),
        ),
        ("tracer acceleration", perturb_tracer_acceleration, lambda root: compare_case(case(root, "slider_crank_tracer"))),
        ("slider-axis drift", perturb_slider_axis, lambda root: compare_case(case(root, "teaching_slider_crank"))),
        ("truncated sweep", perturb_truncated_sweep, lambda root: compare_case(case(root, "teaching_four_bar"))),
        ("cycle duplicate mishandling", perturb_duplicate, lambda root: compare_case(case(root, "teaching_four_bar"))),
        ("missing required file", perturb_missing_file, lambda root: validate_case(case(root, "watt_i"), True)),
        ("force ownership", perturb_force_ownership, lambda root: check_case(case(root, "watt_i"))),
        ("load application point", perturb_load_point, lambda root: check_case(case(root, "watt_i"))),
        ("gravity convention", perturb_gravity, lambda root: check_case(case(root, "watt_i"))),
        ("input torque", perturb_torque, lambda root: check_case(case(root, "watt_i"))),
        ("CSV precision", perturb_precision, lambda root: validate_case(case(root, "teaching_four_bar"), True)),
        (
            "stale provenance",
            perturb_provenance,
            lambda root: validate_provenance(
                root, arguments.repo_root.resolve(), arguments.pmks_root.resolve()
            ),
        ),
        (
            "MotionGen retained-model provenance",
            perturb_motiongen_provenance,
            lambda root: compare_motiongen_case(
                case(root, "teaching_four_bar"), arguments.repo_root.resolve()
            ),
        ),
    ]
    for label, perturb, gate in tests:
        with candidate_copy(source) as candidate:
            perturb(candidate)
            expect_failure(label, lambda: gate(candidate))
            print(f"PASS perturbation detected: {label}")


@contextmanager
def candidate_copy(source: Path) -> Iterator[Path]:
    with tempfile.TemporaryDirectory(prefix="pmks-v1-perturb-") as directory:
        target = Path(directory) / "v1"
        shutil.copytree(source, target)
        yield target


def case(root: Path, case_id: str) -> Path:
    return root / "cases" / case_id


def expect_failure(label: str, action: Callable[[], object]) -> None:
    try:
        action()
    except (ContractError, OSError, KeyError, ValueError):
        return
    raise RuntimeError(f"Perturbation escaped detection: {label}")


def perturb_branch(root: Path) -> None:
    path = case(root, "teaching_four_bar") / "pmks" / "joints" / "C.csv"
    mutate_csv(path, 0, "y", lambda value: -float(value))


def perturb_velocity(root: Path) -> None:
    path = case(root, "teaching_four_bar") / "pmks" / "points" / "H.csv"
    mutate_csv(path, 10, "vx", lambda value: -float(value))
    mutate_csv(path, 10, "vy", lambda value: -float(value))


def perturb_negative_speed_branch(root: Path) -> None:
    path = case(root, "teaching_four_bar") / "pmks" / "points" / "H.csv"
    mutate_csv_by_sample_id(
        path, "pmks_negative_0010", "vx", lambda value: -float(value)
    )


def perturb_tracer_acceleration(root: Path) -> None:
    path = case(root, "slider_crank_tracer") / "pmks" / "points" / "D.csv"
    mutate_csv(path, 10, "ax", lambda value: float(value) + 1)


def perturb_slider_axis(root: Path) -> None:
    path = case(root, "teaching_slider_crank") / "pmks" / "joints" / "C.csv"
    mutate_csv(path, 10, "y", lambda value: float(value) + 0.1)


def perturb_truncated_sweep(root: Path) -> None:
    path = case(root, "teaching_four_bar") / "matlab" / "samples.csv"
    header, rows = load_csv(path)
    save_csv(path, header, rows[:-1])


def perturb_duplicate(root: Path) -> None:
    path = case(root, "teaching_four_bar") / "matlab" / "samples.csv"
    header, rows = load_csv(path)
    rows[-1]["sweep_id"] = rows[0]["sweep_id"]
    rows[-1]["sweep_index"] = "360"
    save_csv(path, header, rows)


def perturb_missing_file(root: Path) -> None:
    (case(root, "watt_i") / "matlab" / "joints" / "A.csv").unlink()


def perturb_force_ownership(root: Path) -> None:
    path = case(root, "watt_i") / "case.json"
    manifest = json.loads(path.read_text())
    manifest["dynamics"]["reaction_ownership"]["AB"]["B"] = -1
    path.write_text(json.dumps(manifest, indent=2) + "\n")


def perturb_load_point(root: Path) -> None:
    path = case(root, "watt_i") / "case.json"
    manifest = json.loads(path.read_text())
    manifest["dynamics"]["load"]["application_average"] = ["C"]
    path.write_text(json.dumps(manifest, indent=2) + "\n")


def perturb_gravity(root: Path) -> None:
    path = case(root, "watt_i") / "case.json"
    manifest = json.loads(path.read_text())
    manifest["dynamics"]["gravity"] = [0, -8]
    path.write_text(json.dumps(manifest, indent=2) + "\n")


def perturb_torque(root: Path) -> None:
    path = case(root, "watt_i") / "matlab" / "dynamics" / "newton_gravity" / "input_torque.csv"
    mutate_csv(path, 0, "torque_nm", lambda value: float(value) + 10)


def perturb_precision(root: Path) -> None:
    path = case(root, "teaching_four_bar") / "pmks" / "joints" / "B.csv"
    # This decimal is intentionally not the canonical round-trip spelling of its
    # binary64 value, so the serialization gate—not cross-source error—must catch it.
    mutate_csv(path, 10, "x", lambda value: "3.14159", preserve_string=True)


def perturb_provenance(root: Path) -> None:
    path = case(root, "watt_i") / "matlab" / "source-metadata.json"
    metadata = json.loads(path.read_text())
    metadata["source_content_sha256"] = "0" * 64
    path.write_text(json.dumps(metadata, indent=2) + "\n")


def perturb_motiongen_provenance(root: Path) -> None:
    path = case(root, "teaching_four_bar") / "motiongen" / "receipts" / "joint-A.json"
    receipt = json.loads(path.read_text())
    receipt["model_id"] = "wrong-retained-model"
    path.write_text(json.dumps(receipt, indent=2) + "\n")


def mutate_csv(
    path: Path,
    row_index: int,
    column: str,
    transform: Callable[[str], object],
    preserve_string: bool = False,
) -> None:
    header, rows = load_csv(path)
    value = transform(rows[row_index][column])
    rows[row_index][column] = str(value) if preserve_string else format(float(value), ".17g")
    save_csv(path, header, rows)


def mutate_csv_by_sample_id(
    path: Path,
    sample_id: str,
    column: str,
    transform: Callable[[str], object],
) -> None:
    header, rows = load_csv(path)
    matches = [row for row in rows if row["sample_id"] == sample_id]
    if len(matches) != 1:
        raise RuntimeError(f"Expected one row for {sample_id}, found {len(matches)}")
    matches[0][column] = format(float(transform(matches[0][column])), ".17g")
    save_csv(path, header, rows)


def load_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(newline="", encoding="utf-8") as stream:
        reader = csv.DictReader(stream)
        return list(reader.fieldnames or []), list(reader)


def save_csv(path: Path, header: list[str], rows: list[dict[str, str]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=header, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


if __name__ == "__main__":
    main()
