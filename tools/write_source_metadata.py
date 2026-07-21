#!/usr/bin/env python3
"""Write stable, content-addressed source metadata for a v1 candidate."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path

from reference_data import case_directories, dump_json, load_json, sha256_files, tree_files

MATLAB_REPOSITORY = "https://github.com/PMKS-Web/PMKS_Verification"
PMKS_REPOSITORY = "https://github.com/PMKS-Web/PMKS"
PMKS_COMMIT = "644b26c75b07182ce04dc6466cfec74ee4130c93"
PMKS_UPSTREAM_REPOSITORY = "https://github.com/DesignEngrLab/PMKS"
PMKS_UPSTREAM_COMMIT = "2a0a6fca957dd19844567702af663f607dc15dfe"
PMKS_REPEATABILITY_RELATIVE_TOLERANCE = 8e-12

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


def git_tree(root: Path, revision: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", f"{revision}^{{tree}}"], text=True
    ).strip()


def git_patch_sha256(root: Path, base: str, revision: str = "HEAD") -> str:
    patch = subprocess.check_output(
        ["git", "-C", str(root), "diff", "--binary", f"{base}..{revision}", "--"]
    )
    return hashlib.sha256(patch).hexdigest()


def git_changed_files(root: Path, base: str, revision: str = "HEAD") -> list[str]:
    output = subprocess.check_output(
        ["git", "-C", str(root), "diff", "--name-only", f"{base}..{revision}", "--"],
        text=True,
    )
    return [line for line in output.splitlines() if line]


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
    pmks_source_hash = None
    pmks_tree = None
    upstream_tree = None
    fork_patch_hash = None
    fork_changed_files = None
    if arguments.pmks_root:
        pmks_root = arguments.pmks_root.resolve()
        pmks_files = [
            path
            for path in tree_files(pmks_root / "PlanarMechanismSimulator")
            if "/bin/" not in path.as_posix() and "/obj/" not in path.as_posix()
        ]
        pmks_source_hash = sha256_files(pmks_root, pmks_files)
        pmks_tree = git_tree(pmks_root, "HEAD")
        upstream_tree = git_tree(pmks_root, PMKS_UPSTREAM_COMMIT)
        fork_patch_hash = git_patch_sha256(pmks_root, PMKS_UPSTREAM_COMMIT)
        fork_changed_files = git_changed_files(pmks_root, PMKS_UPSTREAM_COMMIT)

    index: dict[str, object] = {
        "schema_version": 1,
        "matlab_repository": MATLAB_REPOSITORY,
        "pmks_repository": PMKS_REPOSITORY,
        "pmks_commit": PMKS_COMMIT,
        "pmks_upstream_repository": PMKS_UPSTREAM_REPOSITORY,
        "pmks_upstream_commit": PMKS_UPSTREAM_COMMIT,
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
        pmks_metadata["repeatability_relative_tolerance"] = (
            PMKS_REPEATABILITY_RELATIVE_TOLERANCE
        )
        if pmks_source_hash:
            pmks_metadata.update(
                {
                    "source_content_sha256": pmks_source_hash,
                    "source_tree_git": pmks_tree,
                    "upstream_repository": PMKS_UPSTREAM_REPOSITORY,
                    "upstream_base_commit": PMKS_UPSTREAM_COMMIT,
                    "upstream_base_tree_git": upstream_tree,
                    "fork_patch_sha256": fork_patch_hash,
                    "fork_changed_files": fork_changed_files,
                }
            )
        dump_json(pmks_path, pmks_metadata)
        index["cases"][case_id] = {
            "matlab_source_content_sha256": matlab_hash,
            "pmks_adapter_content_sha256": adapter_hash,
            "pmks_source_content_sha256": pmks_source_hash,
            "pmks_source_tree_git": pmks_tree,
            "pmks_upstream_base_tree_git": upstream_tree,
            "pmks_fork_patch_sha256": fork_patch_hash,
        }
    dump_json(root / "source-metadata.json", index)


if __name__ == "__main__":
    main()
