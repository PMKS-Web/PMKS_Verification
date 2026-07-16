#!/usr/bin/env python3
"""Validate schema, coverage, precision, provenance, and explicit v1 scope."""

from __future__ import annotations

import argparse
from pathlib import Path

from reference_data import (
    ContractError,
    LINK_HEADER,
    POINT_HEADER,
    PRISMATIC_HEADER,
    REACTION_HEADER,
    TORQUE_HEADER,
    TRUST_LEVELS,
    case_directories,
    load_json,
    read_samples,
    reject_legacy,
    require_sample_coverage,
    rows_by_id,
)


def validate_case(case_root: Path, require_sources: bool) -> None:
    manifest = load_json(case_root / "case.json")
    case_id = manifest.get("case_id")
    if case_id != case_root.name or manifest.get("schema_version") != 1:
        raise ContractError(f"{case_root}: case identity/schema mismatch")
    required = {
        "topology",
        "input",
        "units",
        "characteristic_length",
        "jacobian",
        "capabilities",
        "trust",
        "exclusions",
    }
    missing = sorted(required - manifest.keys())
    if missing:
        raise ContractError(f"{case_root}: missing manifest fields {missing}")
    for capability, trust in manifest["trust"].items():
        if trust not in TRUST_LEVELS:
            raise ContractError(f"{case_root}: {capability} has invalid trust {trust!r}")
    validate_scope(manifest, case_root)

    if not require_sources:
        return
    for source in ("matlab", "pmks"):
        source_root = case_root / source
        samples = read_samples(source_root / "samples.csv")
        for joint in manifest["topology"]["joints"]:
            validate_series(source_root / "joints" / f"{joint['id']}.csv", POINT_HEADER, samples)
        for point in manifest["topology"]["points"]:
            validate_series(source_root / "points" / f"{point['id']}.csv", POINT_HEADER, samples)
        expected_com = {
            link
            for link in manifest.get("mass_properties", {})
            if link in {spec["id"] for spec in manifest["topology"]["links"]}
        }
        for link in sorted(expected_com):
            validate_series(source_root / "com" / f"{link}.csv", POINT_HEADER, samples)
        for link in manifest["topology"]["links"]:
            validate_series(source_root / "links" / f"{link['id']}.csv", LINK_HEADER, samples)
        if source == "pmks" and manifest["capabilities"]["prismatic"]:
            for joint in manifest["topology"]["joints"]:
                if joint["type"] == "P":
                    validate_series(
                        source_root / "prismatic" / f"{joint['id']}.csv",
                        PRISMATIC_HEADER,
                        samples,
                    )
        if not (source_root / "source-metadata.json").is_file():
            raise ContractError(f"{source_root}: missing source-metadata.json")

    if manifest["capabilities"]["dynamics"]:
        matlab_samples = read_samples(case_root / "matlab" / "samples.csv")
        for scenario in manifest["dynamics"]["scenarios"]:
            scenario_root = case_root / "matlab" / "dynamics" / scenario
            for joint in manifest["topology"]["joints"]:
                validate_series(
                    scenario_root / "joints" / f"{joint['id']}.csv",
                    REACTION_HEADER,
                    matlab_samples,
                )
            validate_series(scenario_root / "input_torque.csv", TORQUE_HEADER, matlab_samples)


def validate_scope(manifest: dict, case_root: Path) -> None:
    capabilities = manifest["capabilities"]
    if capabilities["dynamics"] and manifest["case_id"] not in {
        "watt_i",
        "stephenson_iii_example_2",
    }:
        raise ContractError(f"{case_root}: teaching/slider dynamics are prohibited")
    if capabilities["motiongen"] != (manifest["case_id"] in {"teaching_four_bar", "teaching_slider_crank"}):
        raise ContractError(f"{case_root}: MotionGen applicability is incorrect")
    if manifest["case_id"].startswith("teaching_") and manifest["trust"]["com"] != "diagnostic-only":
        raise ContractError(f"{case_root}: teaching CoM must remain diagnostic-only")
    if manifest["case_id"] in {"watt_i", "stephenson_iii_example_2"}:
        if manifest["trust"]["dynamics"] != "newton-euler-consistency":
            raise ContractError(f"{case_root}: dynamics trust overclaims external corroboration")


def validate_series(path: Path, header: tuple[str, ...], samples: list) -> None:
    rows = rows_by_id(path, header)
    require_sample_coverage(path, rows, samples)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path("reference-data/v1"))
    parser.add_argument("--require-sources", action="store_true")
    arguments = parser.parse_args()
    reject_legacy(arguments.root)
    cases = case_directories(arguments.root)
    if len(cases) != 5:
        raise ContractError(f"Expected five cases, found {len(cases)}")
    for case in cases:
        validate_case(case, arguments.require_sources)
        print(f"PASS schema/coverage: {case.name}")


if __name__ == "__main__":
    main()
