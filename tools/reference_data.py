"""Shared, dependency-free helpers for the PMKS reference-data/v1 contract."""

from __future__ import annotations

import csv
import hashlib
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Iterator, Mapping, Sequence

TRUST_LEVELS = {
    "matlab-pmks",
    "matlab-pmks-motiongen",
    "newton-euler-consistency",
    "diagnostic-only",
    "not-applicable",
}
SAMPLES_HEADER = (
    "sample_id",
    "sweep_id",
    "sweep_index",
    "input_angle_rad",
    "input_direction",
    "time_s",
    "jacobian_condition",
    "eligibility",
)
POINT_HEADER = ("sample_id", "x", "y", "vx", "vy", "ax", "ay")
LINK_HEADER = ("sample_id", "theta_delta_rad", "omega_rad_s", "alpha_rad_s2")
PRISMATIC_HEADER = ("sample_id", "position", "velocity", "acceleration")
REACTION_HEADER = ("sample_id", "fx", "fy")
TORQUE_HEADER = ("sample_id", "torque_nm")


class ContractError(RuntimeError):
    """Raised when candidate data violates the v1 contract."""


@dataclass(frozen=True)
class Sample:
    sample_id: str
    sweep_id: str
    sweep_index: int
    input_angle: float
    direction: int
    time: float
    condition: float
    eligibility: str


def reject_legacy(path: Path) -> None:
    normalized = path.resolve().as_posix()
    if "/legacy/" in normalized or "/CSVOutput" in normalized:
        raise ContractError(f"reference-data/v1 tools reject legacy path: {path}")


def load_json(path: Path) -> dict:
    reject_legacy(path)
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ContractError(f"Could not read JSON {path}: {error}") from error


def dump_json(path: Path, value: object) -> None:
    reject_legacy(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def case_directories(root: Path) -> list[Path]:
    reject_legacy(root)
    cases = root / "cases"
    if not cases.is_dir():
        raise ContractError(f"Missing cases directory: {cases}")
    return sorted(path for path in cases.iterdir() if path.is_dir())


def read_csv(path: Path, expected_header: Sequence[str]) -> list[dict[str, str]]:
    reject_legacy(path)
    if not path.is_file():
        raise ContractError(f"Missing CSV: {path}")
    with path.open(newline="", encoding="utf-8") as stream:
        reader = csv.DictReader(stream)
        actual = tuple(reader.fieldnames or ())
        if actual != tuple(expected_header):
            raise ContractError(f"{path}: header {actual!r} != {tuple(expected_header)!r}")
        rows = list(reader)
    if not rows:
        raise ContractError(f"{path}: file contains no data rows")
    return rows


def write_csv(path: Path, header: Sequence[str], rows: Iterable[Sequence[object]]) -> None:
    reject_legacy(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow(header)
        for row in rows:
            writer.writerow(format_csv_value(value) for value in row)


def format_csv_value(value: object) -> str:
    if isinstance(value, float):
        return format(value, ".17g")
    return str(value)


def parse_float(value: str, path: Path, row: int, column: str) -> float:
    try:
        parsed = float(value)
    except ValueError as error:
        raise ContractError(f"{path}:{row}: {column} is not numeric: {value!r}") from error
    if not math.isfinite(parsed):
        raise ContractError(f"{path}:{row}: {column} must be finite, got {value!r}")
    return parsed


def validate_float_token(value: str, path: Path, row: int, column: str) -> float:
    """Verify decimal-to-binary reread error against the serialization tier."""
    parsed = parse_float(value, path, row, column)
    from decimal import Decimal, InvalidOperation

    try:
        decimal_value = Decimal(value)
    except InvalidOperation as error:
        raise ContractError(f"{path}:{row}: invalid decimal {value!r}") from error
    exact_float = Decimal.from_float(parsed)
    scale = max(1.0, abs(parsed))
    limit = max(math.ulp(parsed), 1e-15 * scale)
    if abs(decimal_value - exact_float) > Decimal.from_float(limit):
        raise ContractError(
            f"{path}:{row}: {column} loses more than serialization tolerance ({value!r})"
        )
    if normalize_number_token(value) != normalize_number_token(format(parsed, ".17g")):
        raise ContractError(
            f"{path}:{row}: {column} is not canonical %.17g serialization ({value!r})"
        )
    return parsed


def normalize_number_token(value: str) -> str:
    mantissa, marker, exponent = value.strip().lower().partition("e")
    if not marker:
        return mantissa
    return f"{mantissa}e{int(exponent)}"


def read_samples(path: Path) -> list[Sample]:
    rows = read_csv(path, SAMPLES_HEADER)
    result: list[Sample] = []
    seen: set[str] = set()
    for row_number, row in enumerate(rows, 2):
        sample_id = row["sample_id"]
        if not sample_id or sample_id in seen:
            raise ContractError(f"{path}:{row_number}: duplicate/empty sample_id {sample_id!r}")
        seen.add(sample_id)
        try:
            sweep_index = int(row["sweep_index"])
            direction = int(row["input_direction"])
        except ValueError as error:
            raise ContractError(f"{path}:{row_number}: invalid integer field") from error
        if direction not in (-1, 1):
            raise ContractError(f"{path}:{row_number}: input_direction must be +/-1")
        if row["eligibility"] not in ("eligible", "singular"):
            raise ContractError(f"{path}:{row_number}: invalid eligibility")
        result.append(
            Sample(
                sample_id,
                row["sweep_id"],
                sweep_index,
                validate_float_token(row["input_angle_rad"], path, row_number, "input_angle_rad"),
                direction,
                validate_float_token(row["time_s"], path, row_number, "time_s"),
                validate_float_token(row["jacobian_condition"], path, row_number, "jacobian_condition"),
                row["eligibility"],
            )
        )
    validate_sweep_order(result, path)
    return result


def validate_sweep_order(samples: Sequence[Sample], path: Path) -> None:
    seen_completed: set[str] = set()
    current: str | None = None
    expected_index = 0
    for sample in samples:
        if sample.sweep_id != current:
            if sample.sweep_id in seen_completed:
                raise ContractError(f"{path}: sweep {sample.sweep_id} is not contiguous")
            if current is not None:
                seen_completed.add(current)
            current = sample.sweep_id
            expected_index = 0
        if sample.sweep_index != expected_index:
            raise ContractError(
                f"{path}: {sample.sweep_id} index {sample.sweep_index} != {expected_index}"
            )
        expected_index += 1


def rows_by_id(path: Path, header: Sequence[str]) -> dict[str, dict[str, str]]:
    rows = read_csv(path, header)
    result: dict[str, dict[str, str]] = {}
    for row_number, row in enumerate(rows, 2):
        sample_id = row["sample_id"]
        if sample_id in result:
            raise ContractError(f"{path}:{row_number}: duplicate sample_id {sample_id}")
        for column in header[1:]:
            validate_float_token(row[column], path, row_number, column)
        result[sample_id] = row
    return result


def require_sample_coverage(
    path: Path, rows: Mapping[str, object], samples: Sequence[Sample]
) -> None:
    expected = [sample.sample_id for sample in samples]
    actual = list(rows)
    if actual != expected:
        missing = sorted(set(expected) - set(actual))
        extra = sorted(set(actual) - set(expected))
        raise ContractError(f"{path}: sample coverage/order mismatch; missing={missing}, extra={extra}")


def circular_difference(first: float, second: float) -> float:
    return abs(math.atan2(math.sin(first - second), math.cos(first - second)))


def signed_area(points: Sequence[tuple[float, float]]) -> float:
    return 0.5 * sum(
        first[0] * second[1] - second[0] * first[1]
        for first, second in zip(points, points[1:] + points[:1])
    )


def sha256_files(root: Path, paths: Iterable[Path]) -> str:
    digest = hashlib.sha256()
    for path in sorted(paths, key=lambda item: item.relative_to(root).as_posix()):
        relative = path.relative_to(root).as_posix()
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def tree_files(root: Path) -> Iterator[Path]:
    yield from (path for path in root.rglob("*") if path.is_file())


def scaled_error(actual: float, expected: float, absolute: float, relative: float) -> float:
    limit = absolute + relative * max(abs(actual), abs(expected))
    return abs(actual - expected) / limit if limit else (0.0 if actual == expected else math.inf)


def tolerance(manifest: dict, quantity: str) -> tuple[float, float]:
    length = float(manifest["characteristic_length"])
    speed = abs(float(manifest["input"]["speed_rad_s"]))
    values = {
        "position": (1e-9 * length, 1e-7),
        "velocity": (1e-8 * length * speed, 1e-6),
        "acceleration": (1e-7 * length * speed * speed, 1e-5),
        "angular_position": (1e-8, 1e-8),
        "angular_velocity": (1e-7 * speed, 1e-7),
        "angular_acceleration": (1e-6 * speed * speed, 1e-6),
    }
    return values[quantity]
