#!/usr/bin/env bash
# iOS ARM64 standalone command-line GPU smoke executable.
# Uses synthetic backdrop only. Does NOT install, hook, inject, or acquire live compositor textures.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${GF_SMOKE_OUTPUT_DIR:?Set GF_SMOKE_OUTPUT_DIR to a writable CI artifact directory}"
command -v xcrun >/dev/null || { echo 'ERROR: Xcode xcrun missing' >&2; exit 2; }
command -v ldid >/dev/null || { echo 'ERROR: ldid missing; install signing tool first' >&2; exit 2; }
command -v zip >/dev/null || { echo 'ERROR: zip missing' >&2; exit 2; }
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gf-v8-device-smoke.XXXXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$GF_SMOKE_OUTPUT_DIR"
EXEC="$TMP/GFMetalSmoke"
# This compiles the SAME renderer and host-side test used by macOS compile smoke.
xcrun --sdk iphoneos clang++ -std=c++17 -fobjc-arc -fmodules -Wall -Wextra \
  -arch arm64 -isysroot "$SDK" -miphoneos-version-min=16.0 \
  "$ROOT/src/GFRefractionRenderer.mm" "$ROOT/tools/gpu-smoke.mm" \
  -framework Foundation -framework Metal -framework CoreGraphics \
  -o "$EXEC"
[[ -s "$EXEC" ]] || { echo 'ERROR: iOS GPU executable not produced' >&2; exit 3; }
ARCHS="$(xcrun lipo -archs "$EXEC")"
[[ "$ARCHS" == 'arm64' ]] || { echo "ERROR: unexpected executable arch(s): $ARCHS" >&2; exit 3; }
ldid -S "$EXEC"
ARCHIVE="$GF_SMOKE_OUTPUT_DIR/GFMetalSmoke-ios-arm64.zip"
# ZIP contains only a signed CLI binary; no tweak, package, or payload injection.
rm -f -- "$ARCHIVE"
(cd "$TMP" && zip -q "$ARCHIVE" GFMetalSmoke)
unzip -tq "$ARCHIVE"
echo "PASS: signed iOS ARM64 standalone GPU test prepared: $ARCHIVE"
shasum -a 256 "$ARCHIVE"
echo 'BUILD ONLY: a physical iPad GPU has NOT run this test.'
