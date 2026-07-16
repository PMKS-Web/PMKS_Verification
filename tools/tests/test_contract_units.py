from __future__ import annotations

import csv
import math
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))

from compare_baseline import compare_json  # noqa: E402
from compare_motiongen import derivative_phase_offset, tangential_component  # noqa: E402
from reference_data import (  # noqa: E402
    ContractError,
    Sample,
    circular_difference,
    reject_legacy,
    signed_area,
    validate_float_token,
    validate_sweep_order,
)


class ContractUnitTests(unittest.TestCase):
    def test_json_baseline_uses_same_source_numeric_tier(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            first = root / "first.json"
            second = root / "second.json"
            first.write_text('{"metric":1.0,"label":"stable"}\n', encoding="utf-8")
            second.write_text('{"metric":1.0000000000005,"label":"stable"}\n', encoding="utf-8")
            compare_json(first, second)

    def test_json_baseline_rejects_material_numeric_change(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            first = root / "first.json"
            second = root / "second.json"
            first.write_text('{"metric":1.0}\n', encoding="utf-8")
            second.write_text('{"metric":1.000000001}\n', encoding="utf-8")
            with self.assertRaises(ContractError):
                compare_json(first, second)

    def test_csv_precision_rejects_coarsely_rounded_value(self) -> None:
        with self.assertRaises(ContractError):
            validate_float_token("3.14159", Path("value.csv"), 2, "x")

    def test_duplicate_or_restarted_sweep_is_rejected(self) -> None:
        samples = [
            Sample("a", "s0", 0, 0, 1, 0, 1, "eligible"),
            Sample("b", "s1", 0, 1, 1, 1, 1, "eligible"),
            Sample("c", "s0", 1, 2, 1, 2, 1, "eligible"),
        ]
        with self.assertRaises(ContractError):
            validate_sweep_order(samples, Path("samples.csv"))

    def test_wrong_assembly_branch_changes_signed_area(self) -> None:
        expected = signed_area([(0, 0), (1, 0), (1, 1), (0, 1)])
        wrong = signed_area([(0, 0), (0, 1), (1, 1), (1, 0)])
        self.assertGreater(expected, 0)
        self.assertLess(wrong, 0)

    def test_cycle_endpoint_angle_is_compared_modulo_two_pi(self) -> None:
        self.assertLess(circular_difference(0, 2 * math.pi), 1e-14)

    def test_legacy_path_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            reject_legacy(Path("/tmp/legacy/reference-output"))

    def test_motiongen_scalar_acceleration_is_tangential_not_vector_magnitude(self) -> None:
        self.assertEqual(tangential_component(0, 2, -3, 0), 0)
        self.assertIsNone(tangential_component(0, 0, 4, 0))

    def test_motiongen_forward_difference_phase_offsets(self) -> None:
        speed = 1.2
        self.assertAlmostEqual(derivative_phase_offset("x", speed, 60), 0)
        self.assertAlmostEqual(derivative_phase_offset("speed", speed, 60), 0.01)
        self.assertAlmostEqual(derivative_phase_offset("acceleration", speed, 60), 0.02)
        self.assertAlmostEqual(derivative_phase_offset("omega_rad_s", speed, 60), 0.01)
        self.assertAlmostEqual(derivative_phase_offset("alpha_rad_s2", speed, 60), 0.02)


if __name__ == "__main__":
    unittest.main()
