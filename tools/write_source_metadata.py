#!/usr/bin/env python3
"""Write stable, content-addressed source metadata for a v1 candidate."""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

from reference_data import case_directories, dump_json, load_json, sha256_files, tree_files

MATLAB_REPOSITORY = "https://github.com/PMKS-Web/PMKS_Verification"
PMKS_REPOSITORY = "https://github.com/DesignEngrLab/PMKS"
PMKS_COMMIT = "2a0a6fca957dd19844567702af663f607dc15dfe"

SOURCE_DIRECTORIES = {
    "watt_i": Path("Mechanisms/Watt_I"),
    "stephenson_iii_example_2": Path("Mechanisms/Stephenson_III/Example_2"),
    "teaching_four_bar": Path("Mechanisms/Four_Bar_Mechanism/TeachingLab_Four_Bar"),
    "teaching_slider_crank": Path("Mechanisms/Four_Bar_Slider/TeachingLab_Slider_Crank"),
    "slider_crank_tracer": Path("Mechanisms/Four_Bar_Slider/Slider_Crank_Tracer_Point"),
}


def git_commit(root: Path) -> str:
    return subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "HEAD"], text=True
    ).strip()


def matlab_files(repo: Path, case_id: str) -> list[Path]:
    common = list((repo / "CommonUtils").glob("*.m"))
    verification = list((repo / "verification").glob("*.m"))
    case = list((repo / SOURCE_DIRECTORIES[case_id]).glob("*.m"))
    return [path for path in common + verification + case if path.is_file()]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--pmks-root", type=Path)
    arguments = parser.parse_args()
    repo = arguments.repo_root.resolve()
    root = arguments.root.resolve()
    adapter_files = [
        path
        for path in tree_files(repo / "oracle" / "pmks")
        if "/bin/" not in path.as_posix() and "/obj/" not in path.as_posix()
    ]
    adapter_hash = sha256_files(repo, adapter_files)
    upstream_hash = None
    if arguments.pmks_root:
        pmks_root = arguments.pmks_root.resolve()
        upstream_files = [
            path
            for path in tree_files(pmks_root / "PlanarMechanismSimulator")
            if "/bin/" not in path.as_posix() and "/obj/" not in path.as_posix()
        ]
        upstream_hash = sha256_files(pmks_root, upstream_files)

    index: dict[str, object] = {
        "schema_version": 1,
        "matlab_repository": MATLAB_REPOSITORY,
        "pmks_repository": PMKS_REPOSITORY,
        "pmks_commit": PMKS_COMMIT,
        "cases": {},
    }
    for case_root in case_directories(root):
        manifest = load_json(case_root / "case.json")
        case_id = manifest["case_id"]
        matlab_hash = sha256_files(repo, matlab_files(repo, case_id))
        matlab_metadata = {
            "schema_version": 1,
            "source_repository": MATLAB_REPOSITORY,
            "source_content_sha256": matlab_hash,
            "source_files": sorted(
                path.relative_to(repo).as_posix() for path in matlab_files(repo, case_id)
            ),
            "numeric_format": "%.17g",
        }
        dump_json(case_root / "matlab" / "source-metadata.json", matlab_metadata)

        pmks_path = case_root / "pmks" / "source-metadata.json"
        pmks_metadata = load_json(pmks_path)
        pmks_metadata["adapter_content_sha256"] = adapter_hash
        if upstream_hash:
            pmks_metadata["upstream_source_tree_sha256"] = upstream_hash
        dump_json(pmks_path, pmks_metadata)
        index["cases"][case_id] = {
            "matlab_source_content_sha256": matlab_hash,
            "pmks_adapter_content_sha256": adapter_hash,
            "pmks_upstream_source_tree_sha256": upstream_hash,
        }
    dump_json(root / "source-metadata.json", index)


if __name__ == "__main__":
    main()
