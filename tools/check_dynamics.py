#!/usr/bin/env python3
"""Independent Newton-Euler and global-power checks over serialized v1 data only."""

from __future__ import annotations

import argparse
import math
from pathlib import Path

from reference_data import (
    ContractError,
    LINK_HEADER,
    POINT_HEADER,
    REACTION_HEADER,
    TORQUE_HEADER,
    case_directories,
    dump_json,
    load_json,
    read_samples,
    rows_by_id,
)

RESIDUAL_LIMIT = 1e-8


def check_case(case_root: Path) -> dict | None:
    manifest = load_json(case_root / "case.json")
    if not manifest["capabilities"]["dynamics"]:
        if "dynamics" in manifest and manifest["dynamics"].get("scenarios"):
            raise ContractError(f"{manifest['case_id']}: out-of-scope dynamics were requested")
        return None
    if manifest["case_id"] not in {"watt_i", "stephenson_iii_example_2"}:
        raise ContractError(f"{manifest['case_id']}: static/teaching/slider dynamics are prohibited")

    samples = read_samples(case_root / "matlab" / "samples.csv")
    joints = {
        joint["id"]: rows_by_id(
            case_root / "matlab" / "joints" / f"{joint['id']}.csv", POINT_HEADER
        )
        for joint in manifest["topology"]["joints"]
    }
    coms = {
        link: rows_by_id(case_root / "matlab" / "com" / f"{link}.csv", POINT_HEADER)
        for link in manifest["mass_properties"]
        if (case_root / "matlab" / "com" / f"{link}.csv").is_file()
    }
    links = {
        link["id"]: rows_by_id(
            case_root / "matlab" / "links" / f"{link['id']}.csv", LINK_HEADER
        )
        for link in manifest["topology"]["links"]
    }
    maximums = {"force": 0.0, "moment": 0.0, "power": 0.0}
    worst = {"force": "", "moment": "", "power": ""}
    checked_rows = 0
    for scenario in manifest["dynamics"]["scenarios"]:
        gravity = (
            tuple(manifest["dynamics"]["gravity"])
            if scenario == "newton_gravity"
            else (0.0, 0.0)
        )
        if scenario not in {"newton_gravity", "newton_no_gravity"}:
            raise ContractError(f"{manifest['case_id']}: unsupported scenario {scenario}")
        scenario_root = case_root / "matlab" / "dynamics" / scenario
        reactions = {
            joint: rows_by_id(scenario_root / "joints" / f"{joint}.csv", REACTION_HEADER)
            for joint in joints
        }
        torque = rows_by_id(scenario_root / "input_torque.csv", TORQUE_HEADER)
        for sample in samples:
            checked_rows += 1
            sample_id = sample.sample_id
            for link_id, ownership in manifest["dynamics"]["reaction_ownership"].items():
                properties = manifest["mass_properties"][link_id]
                mass = float(properties["mass"])
                inertia = float(properties["inertia"])
                com = vector(coms[link_id][sample_id], "x", "y")
                acceleration = vector(coms[link_id][sample_id], "ax", "ay")
                forces: list[tuple[tuple[float, float], tuple[float, float], str]] = []
                for joint_id, direction in ownership.items():
                    reaction = scale(vector(reactions[joint_id][sample_id], "fx", "fy"), direction)
                    position = vector(joints[joint_id][sample_id], "x", "y")
                    forces.append((reaction, position, f"reaction:{joint_id}"))
                if gravity != (0.0, 0.0):
                    forces.append((scale(gravity, mass), com, "gravity"))
                load = manifest["dynamics"]["load"]
                if load["link"] == link_id:
                    application = average(
                        [vector(joints[joint][sample_id], "x", "y") for joint in load["application_average"]]
                    )
                    forces.append((tuple(load["force"]), application, "load"))

                force_sum = sum_vectors([force for force, _, _ in forces])
                inertial_force = scale(acceleration, mass)
                force_residual = subtract(force_sum, inertial_force)
                force_scale = sum(norm(force) for force, _, _ in forces) + norm(inertial_force)
                normalized_force = norm(force_residual) / max(force_scale, 1e-12)
                record(maximums, worst, "force", normalized_force, f"{scenario}:{sample_id}:{link_id}")

                moments = [cross(subtract(position, com), force) for force, position, _ in forces]
                if link_id == manifest["dynamics"]["input_torque_link"]:
                    moments.append(float(torque[sample_id]["torque_nm"]))
                angular_acceleration = float(links[link_id][sample_id]["alpha_rad_s2"])
                inertial_moment = inertia * angular_acceleration
                moment_residual = sum(moments) - inertial_moment
                moment_scale = sum(abs(moment) for moment in moments) + abs(inertial_moment)
                normalized_moment = abs(moment_residual) / max(moment_scale, 1e-12)
                record(maximums, worst, "moment", normalized_moment, f"{scenario}:{sample_id}:{link_id}")

            input_link = manifest["dynamics"]["input_torque_link"]
            input_power = float(torque[sample_id]["torque_nm"]) * float(
                links[input_link][sample_id]["omega_rad_s"]
            )
            load = manifest["dynamics"]["load"]
            load_velocity = average(
                [vector(joints[joint][sample_id], "vx", "vy") for joint in load["application_average"]]
            )
            load_power = dot(tuple(load["force"]), load_velocity)
            gravity_powers: list[float] = []
            inertial_powers: list[float] = []
            for link_id, properties in manifest["mass_properties"].items():
                if link_id not in coms:
                    continue
                mass = float(properties["mass"])
                inertia = float(properties["inertia"])
                velocity = vector(coms[link_id][sample_id], "vx", "vy")
                acceleration = vector(coms[link_id][sample_id], "ax", "ay")
                gravity_powers.append(dot(scale(gravity, mass), velocity))
                inertial_powers.append(
                    mass * dot(velocity, acceleration)
                    + inertia
                    * float(links[link_id][sample_id]["omega_rad_s"])
                    * float(links[link_id][sample_id]["alpha_rad_s2"])
                )
            inputs = [input_power, load_power, *gravity_powers]
            power_residual = sum(inputs) - sum(inertial_powers)
            power_scale = sum(abs(value) for value in inputs + inertial_powers)
            normalized_power = abs(power_residual) / max(power_scale, 1e-12)
            record(maximums, worst, "power", normalized_power, f"{scenario}:{sample_id}")

    failures = {name: value for name, value in maximums.items() if value > RESIDUAL_LIMIT}
    if failures:
        details = ", ".join(
            f"{name}={value:.6g} at {worst[name]}" for name, value in failures.items()
        )
        raise ContractError(f"{manifest['case_id']}: independent dynamics check failed: {details}")
    report = {
        "schema_version": 1,
        "case_id": manifest["case_id"],
        "status": "pass",
        "trust": "newton-euler-consistency",
        "residual_limit": RESIDUAL_LIMIT,
        "checked_rows": checked_rows,
        "maximum_scaled_residual": maximums,
        "worst_location": worst,
    }
    dump_json(case_root / "dynamics-report.json", report)
    return report


def record(maximums: dict, worst: dict, name: str, value: float, detail: str) -> None:
    if value > maximums[name]:
        maximums[name] = value
        worst[name] = detail


def vector(row: dict[str, str], x: str, y: str) -> tuple[float, float]:
    return float(row[x]), float(row[y])


def scale(value: tuple[float, float], factor: float) -> tuple[float, float]:
    return value[0] * factor, value[1] * factor


def subtract(first: tuple[float, float], second: tuple[float, float]) -> tuple[float, float]:
    return first[0] - second[0], first[1] - second[1]


def sum_vectors(values: list[tuple[float, float]]) -> tuple[float, float]:
    return sum(value[0] for value in values), sum(value[1] for value in values)


def average(values: list[tuple[float, float]]) -> tuple[float, float]:
    return sum_vectors(values)[0] / len(values), sum_vectors(values)[1] / len(values)


def dot(first: tuple[float, float], second: tuple[float, float]) -> float:
    return first[0] * second[0] + first[1] * second[1]


def cross(first: tuple[float, float], second: tuple[float, float]) -> float:
    return first[0] * second[1] - first[1] * second[0]


def norm(value: tuple[float, float]) -> float:
    return math.hypot(*value)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    arguments = parser.parse_args()
    for case_root in case_directories(arguments.root):
        report = check_case(case_root)
        if report:
            print(
                f"PASS dynamics: {case_root.name} "
                f"(max={max(report['maximum_scaled_residual'].values()):.4g})"
            )


if __name__ == "__main__":
    main()
