#!/usr/bin/env python3
"""Keep candidate package labels distinct from the rollback package."""
from pathlib import Path
import plistlib

root = Path(__file__).resolve().parents[1]
control = dict(
    line.split(": ", 1)
    for line in (root / "control").read_text(encoding="utf-8").splitlines()
    if ": " in line
)
info = plistlib.loads((root / "prefs/Resources/Info.plist").read_bytes())
workflow = (root / ".github/workflows/build.yml").read_text(encoding="utf-8")

assert control["Package"] == "com.kulinich.glassfolders"
assert control["Name"] == "GlassFolders (WhiteBG Test 1)"
assert control["Version"] == "1.3.0~lock16+whitebg1"
assert control["Architecture"] == "iphoneos-arm64e"
assert info["CFBundleIdentifier"] == "com.kulinich.glassfolders.preferences"
assert info["CFBundleVersion"] == "1.3.0.16.1"
assert info["CFBundleDisplayName"] == "GlassFolders WhiteBG Test 1"
assert workflow.count(
    f"grep -Fqx 'Version: {control['Version']}' ctrl/control"
) == 2
assert workflow.count(
    f"grep -Fqx 'Name: {control['Name']}' ctrl/control"
) == 2
for scheme, architecture in (("RootHide", "arm64e"), ("Rootless", "arm64")):
    assert f"GlassFolders-1.3.0-lock16-whitebg1-{scheme}-{architecture}" in workflow
assert workflow.count("needs: notification-contrast") == 2
assert workflow.count("runs-on: macos-15-intel") == 2
print("WhiteBG Test 1 package identity and build prerequisites: PASS")
