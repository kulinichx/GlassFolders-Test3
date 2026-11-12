"""Verify the supplied Mango sample's static bridge contract, never load it.

Requires Capstone and the existing read-only inspection helpers in the sibling
audit checkout, or --inspection-tools pointing to those helpers. This is not
a runtime ABI detector and its output must not configure production hooks.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys


PACKAGE_SHA256 = "314a7d2db9f7ac53f7f33f7f16da0efa4a97bc7eed566204b3782e058645e7b1"
RENDERER_SHA256 = "3a5ede25336b05e8c6007ebb0dcc3645ed2ccfaeb3446b166cdd7effed758749"
SHADER_SHA256 = "cca64e34dceb23fd72d1c2f9c4184e23d044c63fd15a952aad0815c3c5ddcb50"
RENDERER = "Library/MobileSubstrate/DynamicLibraries/MangoOSRendering.dylib"
CALLS = {
    0x4370: "operatingSystemVersion",
    0x5D10: "device",
    0x5D2C: "width",
    0x5D38: "height",
    0x65C4: "width",
    0x65F8: "height",
    0x6674: "device",
    0x66A0: "usage",
    0x6768: "pixelFormat",
    0x67C8: "setTexture:",
    0x6808: "setLoadAction:",
    0x6848: "setStoreAction:",
    0x6864: "renderCommandEncoderWithDescriptor:",
    0x6890: "setFragmentTexture:atIndex:",
    0x68A0: "setFragmentTexture:atIndex:",
    0x68B4: "setFragmentBytes:length:atIndex:",
    0x68C8: "drawPrimitives:vertexStart:vertexCount:",
    0x68D0: "endEncoding",
    0x714C: "newLibraryWithSource:options:error:",
}
TEXTURE_FLOW = {
    0x5CE8: ("ldr", "x9, [x9, #0x2e8]"),
    0x5CF8: ("ldr", "x0, [x25, x9]"),
    0x5D0C: ("str", "x0, [sp, #0x48]"),
    0x6888: ("ldr", "x2, [sp, #0x48]"),
    0x688C: ("mov", "x3, #0"),
    0x68AC: ("mov", "w3, #0xb0"),
}
COMPOSITOR_FLOW = {
    0x445C: ("bl", "#0xaf68"),
    0x4460: ("adrp", "x8, #0x1c000"),
    0x4464: ("str", "x0, [x8, #0x300]"),
    0xAF90: ("adrp", "x0, #0x13000"),
    0xAF94: ("add", "x0, x0, #0x7f5"),
    0xAF98: ("bl", "#0xaeb0"),
    0xB110: ("ubfx", "x15, x14, #5, #0x1b"),
    0xB114: ("lsr", "x16, x14, #7"),
    0xB118: ("and", "x0, x16, #0x7ff8"),
    0xB12C: ("b.ne", "#0xb014"),
    0x6584: ("ldr", "x8, [x8, #0x2f8]"),
    0x6590: ("ldr", "x8, [x20, x8]"),
    0x65A0: ("ldr", "x9, [x9, #0x2f0]"),
    0x65A8: ("ldr", "x21, [x8, x9]"),
    0x6670: ("mov", "x0, x21"),
    0x6680: ("cmp", "x0, x25"),
    0x66B0: ("tbz", "w22, #2, #0x6628"),
    0x6744: ("mov", "x0, x20"),
    0x6748: ("blraaz", "x8"),
    0x6750: ("adrp", "x8, #0x1c000"),
    0x6754: ("ldr", "x8, [x8, #0x300]"),
    0x6758: ("ldr", "x24, [x20, x8]"),
    0x67C4: ("mov", "x2, x21"),
    0x685C: ("mov", "x0, x24"),
    0x6860: ("mov", "x2, x22"),
}
SCANNER_ANCHOR = "Command buffer allocation failed!\n"


def comparison_flags(left, right):
    mask = (1 << 64) - 1
    left &= mask
    right &= mask
    result = (left - right) & mask
    negative = bool(result & (1 << 63))
    zero = result == 0
    carry = left >= right
    overflow = bool(((left ^ right) & (left ^ result)) & (1 << 63))
    return negative, zero, carry, overflow


def condition_holds(condition, flags):
    negative, zero, carry, overflow = flags
    conditions = {
        "eq": zero, "ne": not zero,
        "lt": negative != overflow, "le": zero or negative != overflow,
        "gt": not zero and negative == overflow, "ge": negative == overflow,
        "lo": not carry, "hs": carry,
    }
    if condition not in conditions:
        raise ValueError("Unsupported condition: " + condition)
    return conditions[condition]


def evaluate_version_setup(instructions, major):
    """Interpret only a bounded register/constant setup block, not native code."""
    if not isinstance(major, int) or isinstance(major, bool) or not 1 <= major <= 100:
        raise ValueError("Invalid OS major")
    registers, stores = {}, {}
    flags = (False, False, False, False)

    def read(value):
        if value.startswith("#"):
            return int(value[1:], 0)
        key = "x" + value[1:] if re.fullmatch(r"[wx]\d+", value) else value
        if key not in registers:
            raise ValueError("Uninitialized register: " + value)
        result = registers[key]
        return result & 0xFFFFFFFF if value.startswith("w") else result

    def write(register, value):
        if not re.fullmatch(r"[wx]\d+", register):
            raise ValueError("Unsupported register: " + register)
        registers["x" + register[1:]] = value & (
            0xFFFFFFFF if register.startswith("w") else (1 << 64) - 1)

    for _, _, mnemonic, operands in instructions:
        args = operands.split(", ")
        if mnemonic == "ldr" and operands == "x8, [sp, #8]":
            write("x8", major)
        elif mnemonic in ("mov", "adrp") and len(args) == 2:
            write(args[0], read(args[1]))
        elif mnemonic == "cmp" and len(args) == 2:
            flags = comparison_flags(read(args[0]), read(args[1]))
        elif mnemonic == "ccmp" and len(args) == 4:
            if condition_holds(args[3], flags):
                flags = comparison_flags(read(args[0]), read(args[1]))
            else:
                nzcv = read(args[2])
                flags = tuple(bool(nzcv & bit) for bit in (8, 4, 2, 1))
        elif mnemonic == "cset" and len(args) == 2:
            write(args[0], int(condition_holds(args[1], flags)))
        elif mnemonic == "csel" and len(args) == 4:
            write(args[0], read(args[1] if condition_holds(args[3], flags) else args[2]))
        elif mnemonic in ("str", "strb"):
            match = re.fullmatch(r"([wx]\d+), \[(x\d+), #(0x[0-9a-f]+)\]", operands)
            if not match:
                raise ValueError("Unsupported store: " + operands)
            register, base, offset = match.groups()
            value = read(register)
            stores[read(base) + int(offset, 16)] = value & 255 if mnemonic == "strb" else value
        else:
            raise ValueError("Unsupported setup instruction: " + mnemonic + " " + operands)
    return stores


def check_call(image, address, selector):
    code = list(image.instructions(address, address + 4))
    if len(code) != 1 or code[0][2] != "bl" or not code[0][3].startswith("#0x"):
        raise ValueError(f"Missing direct call at {address:#x}")
    target = int(code[0][3][1:], 16)
    if image.stubs.get(target) != selector:
        raise ValueError(f"Unexpected selector at {address:#x}")
    return {"address": hex(address), "selector": selector}


def check_instruction_flow(image, expected_flow, label):
    result = []
    for address, expected in expected_flow.items():
        code = list(image.instructions(address, address + 4))
        if len(code) != 1 or code[0][2:] != expected:
            raise ValueError(f"Unexpected {label} flow at {address:#x}")
        result.append({"address": hex(address), "instruction": " ".join(expected)})
    return result


def check_texture_flow(image):
    return check_instruction_flow(image, TEXTURE_FLOW, "texture")


def check_compositor_flow(image):
    if image.string(0x137F5) != SCANNER_ANCHOR:
        raise ValueError("Unexpected command-buffer scanner anchor")
    return check_instruction_flow(image, COMPOSITOR_FLOW, "compositor")


def inspect(package, inspection_tools):
    sys.path.insert(0, str(inspection_tools.resolve()))
    try:
        from inspect_mango_foreground import Image
        from inspect_rendering_package import read_package
    finally:
        sys.path.pop(0)
    raw, files = read_package(package)
    if hashlib.sha256(raw).hexdigest() != PACKAGE_SHA256:
        raise ValueError("Different package: this verifier supports only the recorded Beta14-4 sample")
    blob = files.get(RENDERER)
    if blob is None or hashlib.sha256(blob).hexdigest() != RENDERER_SHA256:
        raise ValueError("Rendering module hash mismatch")
    image = Image(blob)
    address, size, offset = image.sections["__cstring"]
    shaders = [value for value in image.data[offset:offset + size].split(b"\0")
               if b"fragment " in value and b"mangoGlassFragment" in value]
    if len(shaders) != 1 or hashlib.sha256(shaders[0]).hexdigest() != SHADER_SHA256:
        raise ValueError("Embedded shader mismatch")
    calls = [check_call(image, address, selector) for address, selector in CALLS.items()]
    texture_flow = check_texture_flow(image)
    compositor_flow = check_compositor_flow(image)
    instructions = list(image.instructions(0x4388, 0x43F4))
    if len(instructions) != (0x43F4 - 0x4388) // 4:
        raise ValueError("Incomplete version setup block")
    versions = {}
    for major in range(14, 19):
        stores = evaluate_version_setup(instructions, major)
        slots = (0x1C2E0, 0x1C2E8, 0x1C2F0, 0x1C2F8)
        if not all(slot in stores for slot in slots):
            raise ValueError("Missing setup output")
        versions[str(major)] = {
            "filter_type_field": hex(stores[slots[0]]),
            "input_texture_field": hex(stores[slots[1]]),
            "auxiliary_texture_field": hex(stores[slots[2]]),
            "auxiliary_surface_field": hex(stores[slots[3]]),
        }
    if versions["16"] != {
        "filter_type_field": "0x18", "input_texture_field": "0x58",
        "auxiliary_texture_field": "0x58", "auxiliary_surface_field": "0x110",
    }:
        raise ValueError("Unexpected iOS 16 setup result")
    return {
        "package_sha256": PACKAGE_SHA256,
        "renderer_sha256": RENDERER_SHA256,
        "shader_sha256": SHADER_SHA256,
        "native_code_executed": False,
        "target_runtime_verified": False,
        "version_setup_interpreted_from": "0x4388..0x43f4 (end exclusive)",
        "sample_field_offsets_not_a_runtime_allowlist": versions,
        "verified_static_calls": calls,
        "verified_texture_flow_instructions": texture_flow,
        "verified_compositor_flow_instructions": compositor_flow,
        "command_buffer_field": {
            "sample_scanner_entry": "0xaf68",
            "sample_scanner_anchor": SCANNER_ANCHOR.rstrip("\n"),
            "scanner_result_global": "0x1c300",
            "target_field_offset": None,
            "scanner_executed": False,
            "note": "Discovered by the sample at runtime, not the version setup table",
        },
        "remaining_requirements": [
            "Exact target iOS build and QuartzCore identity",
            "Independently validated compositor registration and callback ABI",
            "Input/output texture ownership, protection and GPU synchronization",
            "Coordinate alignment during transitions and rotation",
            "Identity-pass device verification before optical displacement",
        ],
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("deb", type=Path)
    parser.add_argument("--inspection-tools", type=Path, default=(
        Path(__file__).resolve().parents[2] / "GlassFolders-Test3-audit" / "tools"))
    args = parser.parse_args()
    try:
        print(json.dumps(inspect(args.deb, args.inspection_tools), indent=2))
    except (ValueError, OSError, KeyError, ImportError) as error:
        parser.exit(1, "Inspection failed: " + str(error) + "\n")
