#!/usr/bin/env python3
"""Assemble volatile CI identity separately from stable v1 source metadata."""

from __future__ import annotations

import argparse
import os
import platform
import subprocess
from pathlib import Path

from reference_data import dump_json, load_json


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--v1-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--matlab-report", type=Path)
    parser.add_argument("--dotnet-version")
    arguments = parser.parse_args()
    matlab = load_json(arguments.matlab_report) if arguments.matlab_report and arguments.matlab_report.exists() else None
    source_metadata = load_json(arguments.v1_root / "source-metadata.json")
    report = {
        "schema_version": 1,
        "repository": os.getenv("GITHUB_REPOSITORY"),
        "workflow_run_id": os.getenv("GITHUB_RUN_ID"),
        "workflow_run_attempt": os.getenv("GITHUB_RUN_ATTEMPT"),
        "pr_head_sha": os.getenv("PR_HEAD_SHA") or os.getenv("GITHUB_SHA"),
        "tested_merge_sha": os.getenv("TESTED_MERGE_SHA") or os.getenv("GITHUB_SHA"),
        "runner_image": os.getenv("ImageOS"),
        "runner_image_version": os.getenv("ImageVersion"),
        "python": platform.python_version(),
        "dotnet": arguments.dotnet_version,
        "matlab": matlab,
        "source_metadata": source_metadata,
    }
    dump_json(arguments.output, report)


if __name__ == "__main__":
    main()
