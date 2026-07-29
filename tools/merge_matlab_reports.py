#!/usr/bin/env python3
"""Merge per-shard MATLAB run reports into the single report the pipeline expects.

Sharding the MATLAB job across runners means each shard writes a run report
covering only its own cases. They are combined here rather than in MATLAB so the
runner stays a pure per-case regenerator.

Environment fields (MATLAB version, product list, source commit) must agree
across shards: they describe the toolchain, and a disagreement means the shards
did not run on the same one, which would make the merged candidate a mixture of
two toolchains rather than one result. That is a hard failure, not something to
paper over by picking a winner.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from reference_data import ContractError, dump_json, load_json

# Fields that describe the toolchain rather than the work, and must therefore be
# identical in every shard.
ENVIRONMENT_FIELDS = (
    "schemaVersion",
    "sourceRepository",
    "sourceCommit",
    "matlabVersion",
    "matlabRelease",
    "matlabProducts",
)


def merge(report_paths: list[Path], expected_cases: set[str] | None) -> dict:
    if not report_paths:
        raise ContractError("No MATLAB run reports to merge")

    merged: dict | None = None
    cases: dict[str, dict] = {}
    generated: list[str] = []

    for path in sorted(report_paths):
        report = load_json(path)
        if merged is None:
            merged = {field: report[field] for field in ENVIRONMENT_FIELDS}
        else:
            for field in ENVIRONMENT_FIELDS:
                if report[field] != merged[field]:
                    raise ContractError(
                        f"{path}: {field} differs between shards; "
                        f"{report[field]!r} versus {merged[field]!r}"
                    )
        generated.append(report["generatedAtUtc"])

        # MATLAB serialises a one-element struct array as a bare object.
        shard_cases = report["cases"]
        if isinstance(shard_cases, dict):
            shard_cases = [shard_cases]
        for case in shard_cases:
            case_id = case["name"]
            if case_id in cases:
                raise ContractError(f"{case_id} was produced by more than one shard")
            cases[case_id] = case

    assert merged is not None
    if expected_cases is not None and set(cases) != expected_cases:
        missing = sorted(expected_cases - set(cases))
        unexpected = sorted(set(cases) - expected_cases)
        raise ContractError(
            f"Merged shards do not cover the contract. missing={missing} unexpected={unexpected}"
        )

    # Latest wins: the merged report describes a candidate that was not complete
    # until its last shard finished.
    merged["generatedAtUtc"] = max(generated)
    merged["cases"] = [cases[case_id] for case_id in sorted(cases)]
    merged["shardCount"] = len(report_paths)
    return merged


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reports", type=Path, nargs="+", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--cases-root",
        type=Path,
        help="Assert the merged shards cover exactly the cases under this directory.",
    )
    arguments = parser.parse_args()

    expected = None
    if arguments.cases_root:
        expected = {path.name for path in arguments.cases_root.iterdir() if path.is_dir()}

    merged = merge(arguments.reports, expected)
    dump_json(arguments.output, merged)
    print(f"Merged {merged['shardCount']} MATLAB shards covering {len(merged['cases'])} cases")


if __name__ == "__main__":
    main()
