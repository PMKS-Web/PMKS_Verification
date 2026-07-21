#!/usr/bin/env python3
"""Validate the pinned PMKS fork identity, ancestry, and minimal source delta."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

from reference_data import ContractError, load_json
from write_source_metadata import (
    PMKS_COMMIT,
    PMKS_REPOSITORY,
    PMKS_UPSTREAM_COMMIT,
    PMKS_UPSTREAM_REPOSITORY,
    git_changed_files,
    git_patch_sha256,
    git_tree,
)


def git_output(root: Path, *arguments: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(root), *arguments], text=True
    ).strip()


def validate(
    pmks_root: Path,
    allowlist_path: Path,
    upstream_root: Path | None = None,
) -> dict:
    allowlist = load_json(allowlist_path)
    expected_identity = {
        "repository": PMKS_REPOSITORY,
        "commit": PMKS_COMMIT,
        "upstream_repository": PMKS_UPSTREAM_REPOSITORY,
        "upstream_base_commit": PMKS_UPSTREAM_COMMIT,
    }
    for key, expected in expected_identity.items():
        if allowlist.get(key) != expected:
            raise ContractError(
                f"PMKS fork allowlist {key}={allowlist.get(key)!r}, expected {expected!r}"
            )

    head = git_output(pmks_root, "rev-parse", "HEAD")
    if head != PMKS_COMMIT:
        raise ContractError(f"PMKS checkout is {head}, expected {PMKS_COMMIT}")
    ancestor = subprocess.run(
        [
            "git",
            "-C",
            str(pmks_root),
            "merge-base",
            "--is-ancestor",
            PMKS_UPSTREAM_COMMIT,
            "HEAD",
        ],
        check=False,
    )
    if ancestor.returncode != 0:
        raise ContractError("Pinned PMKS fork does not descend from the declared upstream base")

    if upstream_root is not None:
        upstream_head = git_output(upstream_root, "rev-parse", "HEAD")
        if upstream_head != PMKS_UPSTREAM_COMMIT:
            raise ContractError(
                f"DesignEngrLab upstream checkout is {upstream_head}, "
                f"expected {PMKS_UPSTREAM_COMMIT}"
            )
        upstream_tree = git_tree(upstream_root, "HEAD")
        declared_tree = allowlist.get("upstream_base_tree_git")
        fork_base_tree = git_tree(pmks_root, PMKS_UPSTREAM_COMMIT)
        if upstream_tree != declared_tree or upstream_tree != fork_base_tree:
            raise ContractError(
                "Declared fork base does not match the independently checked out "
                f"DesignEngrLab commit: upstream={upstream_tree}, "
                f"fork_base={fork_base_tree}, declared={declared_tree}"
            )

    changed = git_changed_files(pmks_root, PMKS_UPSTREAM_COMMIT)
    allowed = allowlist.get("allowed_paths", [])
    if changed != allowed:
        raise ContractError(f"Unexpected PMKS fork delta: {changed!r}, expected {allowed!r}")
    patch_hash = git_patch_sha256(pmks_root, PMKS_UPSTREAM_COMMIT)
    if patch_hash != allowlist.get("patch_sha256"):
        raise ContractError(
            f"PMKS fork patch hash {patch_hash}, expected {allowlist.get('patch_sha256')}"
        )

    result = {
        "source_tree_git": git_tree(pmks_root, "HEAD"),
        "upstream_base_tree_git": git_tree(pmks_root, PMKS_UPSTREAM_COMMIT),
        "fork_patch_sha256": patch_hash,
        "fork_changed_files": changed,
    }
    expected_result = {
        key: allowlist.get(key)
        for key in (
            "source_tree_git",
            "upstream_base_tree_git",
            "patch_sha256",
        )
    }
    actual_result = {
        "source_tree_git": result["source_tree_git"],
        "upstream_base_tree_git": result["upstream_base_tree_git"],
        "patch_sha256": result["fork_patch_sha256"],
    }
    if actual_result != expected_result:
        raise ContractError(
            f"PMKS fork object identity changed: {actual_result!r}, expected {expected_result!r}"
        )
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pmks-root", type=Path, required=True)
    parser.add_argument("--upstream-root", type=Path)
    parser.add_argument(
        "--allowlist",
        type=Path,
        default=Path("reference-data/v1/pmks-fork-delta.json"),
    )
    arguments = parser.parse_args()
    validate(
        arguments.pmks_root.resolve(),
        arguments.allowlist.resolve(),
        arguments.upstream_root.resolve() if arguments.upstream_root else None,
    )
    print("PASS PMKS fork identity and delta")


if __name__ == "__main__":
    main()
