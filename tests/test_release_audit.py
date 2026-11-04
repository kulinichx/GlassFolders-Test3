"""Portable release guards. UIKit behavior still requires a device test."""

import argparse
import base64
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import struct
import subprocess
import tarfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
BASE = None


def source(name):
    return (BASE or ROOT).joinpath(name).read_text(encoding="utf-8")


def implementation(name, text=None):
    text = text or source("Tweak.xm")
    start = text.index("@implementation " + name + "\n")
    return text[start:text.index("@end", start)]


def method(text, signature):
    start = text.index(signature)
    opening = text.index("{", start)
    depth = 1
    for index in range(opening + 1, len(text)):
        depth += (text[index] == "{") - (text[index] == "}")
        if not depth:
            return text[opening + 1:index]
    raise ValueError("Unclosed body: " + signature)


def read_deb(path):
    raw = path.read_bytes()
    if raw[:8] != b"!<arch>\n":
        raise ValueError("Not a Debian ar archive")
    offset, members = 8, {}
    while offset < len(raw):
        header = raw[offset:offset + 60]
        if len(header) != 60 or header[58:] != b"`\n":
            raise ValueError("Invalid ar header")
        name = header[:16].decode("ascii").strip().rstrip("/")
        size = int(header[48:58])
        start = offset + 60
        data = raw[start:start + size]
        if len(data) != size or name in members:
            raise ValueError("Truncated or duplicate ar member")
        members[name] = data
        offset = start + size + (size % 2)
    if members.get("debian-binary") != b"2.0\n":
        raise ValueError("Unsupported Debian package format")
    result = {}
    for prefix in ("control.tar", "data.tar"):
        archives = [value for name, value in members.items() if name.startswith(prefix)]
        if len(archives) != 1:
            raise ValueError("Missing or ambiguous " + prefix)
        files = {}
        # tarfile handles gzip, xz and the legacy LZMA stream used by RootHide.
        with tarfile.open(fileobj=io.BytesIO(archives[0]), mode="r:*") as archive:
            for item in archive:
                name = item.name.removeprefix("./")
                if PurePosixPath(name).is_absolute() or ".." in PurePosixPath(name).parts:
                    raise ValueError("Unsafe tar path: " + name)
                if item.isfile():
                    if name in files:
                        raise ValueError("Duplicate package path: " + name)
                    files[name] = archive.extractfile(item).read()
        result[prefix] = files
    return raw, result


def audit_deb(path):
    raw, files = read_deb(path)
    control = files["control.tar"]["control"].decode("utf-8")
    fields = dict(line.split(": ", 1) for line in control.splitlines() if ": " in line)
    if fields["Package"] != "com.kulinich.glassfolders":
        raise ValueError("Wrong package identifier")
    data = files["data.tar"]
    binaries = {}
    for suffix in ("/GlassFolders.dylib", "/GlassFoldersPrefs.bundle/GlassFoldersPrefs"):
        matches = [name for name in data if name.endswith(suffix)]
        if len(matches) != 1:
            raise ValueError("Missing/duplicate binary: " + suffix)
        binary = data[matches[0]]
        if binary[:4] != b"\xcf\xfa\xed\xfe":
            raise ValueError("Expected thin 64-bit Mach-O")
        cpu, subtype = struct.unpack_from("<II", binary, 4)
        if cpu != 0x100000C or subtype & 0xFFFFFF != 2:
            raise ValueError("Expected arm64e binary")
        binaries[matches[0]] = {"bytes": len(binary), "sha256": hashlib.sha256(binary).hexdigest()}
    entries = [name for name in data if "PreferenceLoader/Preferences/" in name and name.endswith(".plist")]
    filters = [plistlib.loads(value) for name, value in data.items()
               if name.endswith("/DynamicLibraries/GlassFolders.plist")]
    if len(entries) != 1 or len(filters) != 1 or filters[0].get("Filter", {}).get("Bundles") != ["com.apple.springboard"]:
        raise ValueError("Injection filter or preference entry mismatch")
    for name, value in data.items():
        if name.endswith(".plist"):
            plistlib.loads(value)
    public_key = re.search(r'GF_LICENSE_PUBLIC_KEY @"([^"]+)"', source("GFLicensePublicKey.h")).group(1)
    if not any(public_key.encode("ascii") in value for name, value in data.items() if name.endswith(".dylib")):
        raise ValueError("License public key does not match source")
    forbidden = (".pem", ".pfx", ".dpapi", "issuer-key", "records.json")
    if any(any(token in name.lower() for token in forbidden) for name in data):
        raise ValueError("Issuer private material included")
    info = next(plistlib.loads(value) for name, value in data.items() if name.endswith("/GlassFoldersPrefs.bundle/Info.plist"))
    return {"file": path.name, "sha256": hashlib.sha256(raw).hexdigest(),
            "package": fields["Package"], "version": fields["Version"],
            "architecture": fields["Architecture"], "files": len(data),
            "bundle_version": info["CFBundleVersion"], "binaries": binaries}


class ReleaseAuditTests(unittest.TestCase):
    def test_real_scheduler_blocks_with_virtual_dispatch(self):
        # Extract the production C block bodies and execute those statements
        # with deterministic dispatch stubs, rather than reimplementing them.
        text = source("GFLivePreferencesPrelude.h")
        arm = method(text, "static void GFLiveArmRefreshTimer(int64_t delay)")
        schedule = method(text, "static void GFLiveSchedulePreferenceReload(void)")
        replacements = {
            "dispatch_get_main_queue()": "null",
            "BOOL ": "let ",
            "^{": "() => {",
        }
        for before, after in replacements.items():
            arm, schedule = arm.replace(before, after), schedule.replace(before, after)
        for before, after in (("YES", "true"), ("NO", "false")):
            arm = re.sub(r"\b" + before + r"\b", after, arm)
            schedule = re.sub(r"\b" + before + r"\b", after, schedule)
        program = """
const assert = require('node:assert/strict');
const DISPATCH_TIME_NOW=0, DISPATCH_TIME_FOREVER=Infinity;
const NSEC_PER_MSEC=1, DISPATCH_SOURCE_TYPE_TIMER=0;
let now=0, GFLiveRefreshTimer=null, GFLiveRefreshDeadline=0;
let GFLivePreferenceReloadPending=false, creates=0, applies=0, settles=0;
const dispatch_time=(base, delay) => now+delay;
const dispatch_async=(queue, block) => block();
const dispatch_source_create=() => {creates++; return {deadline:Infinity};};
const dispatch_source_set_event_handler=(timer, fn) => timer.fn=fn;
const dispatch_source_set_timer=(timer, deadline, repeat, leeway) => {
  assert.equal(repeat, Infinity); timer.deadline=deadline;
};
const dispatch_resume=() => {};
const GFLiveApplyPreferencesNow=() => applies++;
const GFLiveRefreshAllSurfaces=() => settles++;
""" + "function GFLiveArmRefreshTimer(delay) {" + arm + "}\n" + \
            "function schedule() {" + schedule + "}\n" + """
for (let i=0;i<1000;i++) {now=i; schedule();}
assert.equal(creates, 1);
assert.equal(GFLiveRefreshTimer.deadline, 1099);
// Simulate a stale expiration already queued before the last rearm.
GFLiveRefreshTimer.fn();
assert.equal(applies, 0);
now=1099; GFLiveRefreshTimer.fn();
assert.equal(applies, 1);
assert.equal(GFLiveRefreshTimer.deadline, 1279);
// A write during settling replaces it with a fresh debounce deadline.
now=1100; schedule();
assert.equal(GFLiveRefreshTimer.deadline, 1200);
now=1200; GFLiveRefreshTimer.fn();
assert.equal(applies, 2);
assert.equal(settles, 0);
now=1380; GFLiveRefreshTimer.fn();
assert.equal(settles, 1);
assert.equal(GFLiveRefreshTimer.deadline, Infinity);
assert.equal(creates, 1);
"""
        result = subprocess.run(["node", "-e", program], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_all_declared_resources_exist(self):
        for line in source("prefs/Makefile").splitlines():
            if line.startswith("GlassFoldersPrefs_RESOURCE_FILES ="):
                for name in line.split("=", 1)[1].split():
                    self.assertTrue((BASE or ROOT).joinpath("prefs", name).is_file(), name)

    def test_live_constructor_is_process_guarded(self):
        body = method(source("GFLivePreferencesPrelude.h"), "static void GFLivePreferencesInstall(void)")
        self.assertLess(body.index('isEqualToString:@"com.apple.springboard"'), body.index("CFNotificationCenterAddObserver"))

    def test_slider_uses_one_rearmed_source_not_callback_per_write(self):
        text = source("GFLivePreferencesPrelude.h")
        body = method(text, "static void GFLiveSchedulePreferenceReload(void)")
        self.assertNotIn("dispatch_after", body)
        self.assertEqual(body.count("dispatch_source_create("), 1)
        self.assertIn("DISPATCH_TIME_FOREVER", body)
        self.assertIn("GFLiveArmRefreshTimer(100 * NSEC_PER_MSEC)", body)
        self.assertIn("GFLiveArmRefreshTimer(180 * NSEC_PER_MSEC)", body)
        self.assertIn("< GFLiveRefreshDeadline", body)

    def test_closed_icons_rebuild_whole_material_only_on_change(self):
        body = method(implementation("GFBackdropGlassView"), "- (void)gfRefreshMaterial")
        for token in ("_gfMaterialDark == darkAppearance", "_gfMaterialStyle == _gfStyle",
                      "_gfMaterialStrength == _gfStrength", 'GFCreateCAFilter(@"gaussianBlur")',
                      "GFCreateNativeAppLibraryPodVisual", "removeFromSuperview", "removeFromSuperlayer"):
            self.assertIn(token, body)

    def test_closed_icons_keep_native_background_and_refresh_on_toggle(self):
        text = source("Tweak.xm")
        body = method(text, "static void GFRefreshClosedFolderIcon(UIView *icon)")
        self.assertIn("kGFIconNativeBackgroundKey", body)
        self.assertIn("useGlass == (glass != nil)", body)
        self.assertIn("@selector(setBackgroundView:)", body)
        self.assertIn("GFRefreshClosedFolderIcon(view);", source("GFLivePreferencesPrelude.h"))

    def test_panel_restores_latest_native_color_including_nil(self):
        text = source("Tweak.xm")
        body = method(text, "static void GFUpdateOpenedFolderBackground(\n")
        self.assertIn("originalColor == NSNull.null ? nil : originalColor", body)
        self.assertIn("backgroundView.backgroundColor ?: NSNull.null", body)
        setter = method(text, "- (void)setBackgroundColor:(UIColor *)color")
        self.assertIn("kGFPanelSettingTransparentColorKey", setter)
        self.assertIn("color ?: NSNull.null", setter)

    def test_zero_strength_removes_stale_open_panel_recipe(self):
        body = method(implementation("GFPanelGlassView"), "- (void)gfRefreshMaterial")
        zero = body[body.index("// Liquid Glass at 0%") :]
        for token in ('setValue:@[] forKey:@"filters"', "gfBackdropSampleView.hidden = YES",
                      "[self.gfFallbackBlurView removeFromSuperview]"):
            self.assertIn(token, zero)

    def test_quick_action_geometry_has_one_owner(self):
        base = method(implementation("GFPanelGlassView"), "- (void)layoutSubviews")
        self.assertIn("if (circular) overscan = 12.0", base)
        self.assertIn("if (circular) radius = maxRadius", base)
        self.assertNotIn("layoutSubviews", implementation("GFQuickActionGlassView", source("GFLockScreenGlass.h")))

    def test_lock_screen_layout_updates_rim_only_on_geometry_change(self):
        body = method(implementation("GFLockScreenGlassView", source("GFLockScreenGlass.h")),
                      "- (void)layoutSubviews")
        self.assertIn("if (rimGeometryChanged)", body)
        self.assertEqual(body.count("[self.gfLockRim setNeedsLayout]"), 1)
        self.assertIn("[CATransaction setDisableActions:YES]", body)

    def test_search_reorders_only_when_necessary(self):
        body = method(source("Tweak.xm"), "static void GFUpdateAppLibrarySearchView(\n")
        self.assertIn("candidate.subviews.firstObject != overlay", body)
        self.assertIn("!CGRectEqualToRect(overlay.frame, candidate.bounds)", body)

    def test_invalid_style_value_cannot_receive_integer_selector(self):
        body = implementation("GFRootListController", source("prefs/GFRootListController.m"))
        self.assertIn("[style isKindOfClass:NSNumber.class]", body)

    def test_version_metadata_agrees(self):
        text = source("control")
        version = re.search(r"^Version: (.+)$", text, re.MULTILINE).group(1)
        info = plistlib.loads((BASE or ROOT).joinpath("prefs/Resources/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleShortVersionString"], version.split("~")[0].split("+")[0])
        self.assertIn("^Version: " + version + "$", source(".github/workflows/build.yml"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--deb", type=Path)
    parser.add_argument("--source", type=Path)
    args, remaining = parser.parse_known_args()
    BASE = args.source
    if args.deb:
        print(json.dumps(audit_deb(args.deb), indent=2))
    else:
        unittest.main(argv=[__file__] + remaining)
