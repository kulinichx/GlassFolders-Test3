"""Tests of the static verifier; no third-party package or device is required."""

import importlib.util
from pathlib import Path
import unittest

PATH = Path(__file__).resolve().parents[1] / "tools" / "inspect_mango_bridge.py"
SPEC = importlib.util.spec_from_file_location("mango_bridge_inspector", PATH)
BRIDGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BRIDGE)


def instruction(mnemonic, operands):
    return (0, 4, mnemonic, operands)


class VersionSetupTests(unittest.TestCase):
    def test_signed_comparison_and_conditions(self):
        for left in range(14, 19):
            for right in (15, 16, 17):
                flags = BRIDGE.comparison_flags(left, right)
                for condition, expected in (
                    ("eq", left == right), ("ne", left != right),
                    ("lt", left < right), ("le", left <= right),
                    ("gt", left > right), ("ge", left >= right),
                ):
                    self.assertEqual(BRIDGE.condition_holds(condition, flags), expected)

    def test_ccmp_preserves_arm_flags_semantics(self):
        code = [
            instruction("ldr", "x8, [sp, #8]"),
            instruction("cmp", "x8, #0x11"),
            instruction("ccmp", "x8, #0xf, #4, le"),
            instruction("mov", "x9, #0xf8"),
            instruction("mov", "x10, #0x108"),
            instruction("csel", "x9, x10, x9, eq"),
            instruction("adrp", "x10, #0x1c000"),
            instruction("str", "x9, [x10, #0x2f8]"),
        ]
        for major, expected in ((14, 0xF8), (15, 0x108), (16, 0xF8),
                                (17, 0xF8), (18, 0x108)):
            self.assertEqual(BRIDGE.evaluate_version_setup(code, major)[0x1C2F8], expected)

    def test_writes_to_w_register_zero_extend(self):
        code = [instruction("mov", "w8, #0x100000001"),
                instruction("adrp", "x10, #0x1c000"),
                instruction("str", "x8, [x10, #0x2e0]")]
        self.assertEqual(BRIDGE.evaluate_version_setup(code, 16)[0x1C2E0], 1)

    def test_rejects_native_calls_and_unknown_memory_loads(self):
        for code in ([instruction("bl", "#0x1234")],
                     [instruction("ldr", "x0, [x25, x9]")],
                     [instruction("mov", "x8, x9")]):
            with self.assertRaises(ValueError):
                BRIDGE.evaluate_version_setup(code, 16)

    def test_rejects_invalid_os_input(self):
        for major in (None, True, -1, 0, 101, "16"):
            with self.assertRaises(ValueError):
                BRIDGE.evaluate_version_setup([], major)

    def test_signed_overflow_flags(self):
        minimum = -(1 << 63)
        maximum = (1 << 63) - 1
        self.assertTrue(BRIDGE.condition_holds("lt", BRIDGE.comparison_flags(minimum, 1)))
        self.assertTrue(BRIDGE.condition_holds("gt", BRIDGE.comparison_flags(maximum, -1)))

    def test_rejects_changed_selector_or_texture_flow(self):
        class Image:
            stubs = {0x200: "expected:"}

            def instructions(self, start, end):
                return [(start, 4, "bl", "#0x200")]

        image = Image()
        self.assertEqual(BRIDGE.check_call(image, 0x100, "expected:")["address"], "0x100")
        with self.assertRaises(ValueError):
            BRIDGE.check_call(image, 0x100, "different:")
        with self.assertRaises(ValueError):
            BRIDGE.check_texture_flow(image)


class CompositorFlowTests(unittest.TestCase):
    class Image:
        anchor = BRIDGE.SCANNER_ANCHOR

        def __init__(self):
            self.code = dict(BRIDGE.COMPOSITOR_FLOW)

        def string(self, address):
            if address != 0x137F5:
                raise ValueError("Unexpected string address")
            return self.anchor

        def instructions(self, start, end):
            if start not in self.code:
                return []
            mnemonic, operands = self.code[start]
            return [(start, 4, mnemonic, operands)]

    def test_accepts_recorded_static_flow(self):
        result = BRIDGE.check_compositor_flow(self.Image())
        self.assertEqual(len(result), len(BRIDGE.COMPOSITOR_FLOW))
        self.assertIn({"address": "0x6758", "instruction": "ldr x24, [x20, x8]"}, result)

    def test_rejects_changed_or_missing_instruction(self):
        for address in BRIDGE.COMPOSITOR_FLOW:
            for replacement in (None, ("nop", "")):
                with self.subTest(address=hex(address), replacement=replacement):
                    image = self.Image()
                    if replacement is None:
                        del image.code[address]
                    else:
                        image.code[address] = replacement
                    with self.assertRaisesRegex(ValueError, "compositor flow"):
                        BRIDGE.check_compositor_flow(image)

    def test_rejects_changed_scanner_anchor(self):
        image = self.Image()
        image.anchor = "Different runtime anchor"
        with self.assertRaisesRegex(ValueError, "scanner anchor"):
            BRIDGE.check_compositor_flow(image)


if __name__ == "__main__":
    unittest.main()
