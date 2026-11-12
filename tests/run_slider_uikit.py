"""Run the production slider in a dedicated simulator; export UIKit screenshots."""

import json
import platform
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "test-artifacts/slider-uikit"
BUNDLE = "com.kulinich.glassfolders.sliderharness"


def command(*args, timeout=120):
    return subprocess.run(args, check=True, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=timeout).stdout.strip()


def main():
    info = json.loads(command("xcrun", "simctl", "list", "runtimes", "--json"))
    runtimes = [r for r in info["runtimes"] if r.get("isAvailable") and ".iOS-" in r["identifier"]]
    if not runtimes:
        raise RuntimeError("An installed iOS simulator runtime is required for actual UIKit validation")
    runtime = min(runtimes, key=lambda r: tuple(int(x) for x in r["version"].split(".")))
    print("UIKit validation runtime:", runtime["name"], flush=True)
    device = command("xcrun", "simctl", "create", "GFSliderValidation",
                     "com.apple.CoreSimulator.SimDeviceType.iPhone-14-Pro", runtime["identifier"])
    try:
        with tempfile.TemporaryDirectory(prefix="gf-slider-uikit-") as directory:
            app = Path(directory) / "SliderHarness.app"
            app.mkdir()
            plist = {"CFBundleIdentifier": BUNDLE, "CFBundleExecutable": "SliderHarness",
                     "CFBundleName": "SliderHarness", "CFBundlePackageType": "APPL",
                     "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
                     "MinimumOSVersion": "16.0", "UIDeviceFamily": [1],
                     "LSRequiresIPhoneOS": True, "UILaunchScreen": {}}
            with (app / "Info.plist").open("wb") as stream:
                plistlib.dump(plist, stream)
            sdk = command("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path")
            arch = "arm64" if platform.machine() == "arm64" else "x86_64"
            command("xcrun", "--sdk", "iphonesimulator", "clang", "-fobjc-arc",
                    "-Wall", "-Wextra", "-Wno-unused-parameter", "-isysroot", sdk,
                    "-target", f"{arch}-apple-ios16.0-simulator", "-I", str(ROOT / "tests/slider_stubs"),
                    "-framework", "UIKit", "-framework", "Foundation", "-framework", "CoreFoundation",
                    "-framework", "CoreGraphics",
                    str(ROOT / "prefs/GFPercentSliderCell.m"), str(ROOT / "tests/slider_uikit_harness.m"),
                    "-o", str(app / "SliderHarness"))
            command("codesign", "--force", "--sign", "-", str(app))
            command("xcrun", "simctl", "boot", device)
            command("xcrun", "simctl", "bootstatus", device, "-b", timeout=360)
            command("xcrun", "simctl", "install", device, str(app))
            command("xcrun", "simctl", "launch", device, BUNDLE)
            container = Path(command("xcrun", "simctl", "get_app_container", device, BUNDLE, "data"))
            result_path = container / "Documents/result.json"
            deadline = time.monotonic() + 90
            while not result_path.exists() and time.monotonic() < deadline:
                time.sleep(1)
            if not result_path.exists():
                raise RuntimeError("UIKit harness did not produce a result")
            result = json.loads(result_path.read_text())
            result["runtime"] = runtime["name"]
            OUTPUT.mkdir(parents=True, exist_ok=True)
            (OUTPUT / "result.json").write_text(json.dumps(result, indent=2))
            print(json.dumps(result, indent=2), flush=True)
            if result["status"] != "pass":
                raise AssertionError(result)
            for name in ("slider-dark.png", "slider-light.png"):
                source = container / "Documents" / name
                if source.stat().st_size < 1000:
                    raise AssertionError(f"Missing/empty UIKit capture: {name}")
                shutil.copyfile(source, OUTPUT / name)
    finally:
        # Only the dedicated simulator created above is shut down and removed.
        subprocess.run(["xcrun", "simctl", "shutdown", device], check=False)
        subprocess.run(["xcrun", "simctl", "delete", device], check=False)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        print(error.stdout or "", error.stderr or "", flush=True)
        raise
