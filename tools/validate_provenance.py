#!/usr/bin/env python3
"""Recompute stable source hashes and reject stale or self-referential provenance."""

from __future__ import annotations

import argparse
from pathlib import Path

from reference_data import ContractError, case_directories, load_json, sha256_files, tree_files
from write_source_metadata import (
    MATLAB_REPOSITORY,
    PMKS_COMMIT,
    PMKS_REPOSITORY,
    matlab_files,
)


def source_files(root: Path) -> list[Path]:
    return [
        path
        for path in tree_files(root)
        if "/bin/" not in path.as_posix() and "/obj/" not in path.as_posix()
    ]


def validate(root: Path, repo: Path, pmks_root: Path) -> None:
    adapter_hash = sha256_files(repo, source_files(repo / "oracle" / "pmks"))
    upstream_hash = sha256_files(pmks_root, source_files(pmks_root / "PlanarMechanismSimulator"))
    for case_root in case_directories(root):
        case_id = case_root.name
        matlab = load_json(case_root / "matlab" / "source-metadata.json")
        expected_matlab_hash = sha256_files(repo, matlab_files(repo, case_id))
        if matlab.get("source_repository") != MATLAB_REPOSITORY or matlab.get(
            "source_content_sha256"
        ) != expected_matlab_hash:
            raise ContractError(f"{case_id}: stale MATLAB provenance")
        if any("reference-data/v1" in path for path in matlab.get("source_files", [])):
            raise ContractError(f"{case_id}: provenance hash includes generated data/self-reference")

        pmks = load_json(case_root / "pmks" / "source-metadata.json")
        expected = {
            "source_repository": PMKS_REPOSITORY,
            "source_commit": PMKS_COMMIT,
            "adapter_content_sha256": adapter_hash,
            "upstream_source_tree_sha256": upstream_hash,
            "license": "MIT",
        }
        wrong = {key: (pmks.get(key), value) for key, value in expected.items() if pmks.get(key) != value}
        if wrong:
            raise ContractError(f"{case_id}: stale PMKS provenance: {wrong}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--pmks-root", type=Path, required=True)
    arguments = parser.parse_args()
    validate(arguments.root.resolve(), arguments.repo_root.resolve(), arguments.pmks_root.resolve())
    print("PASS provenance")


if __name__ == "__main__":
    main()
