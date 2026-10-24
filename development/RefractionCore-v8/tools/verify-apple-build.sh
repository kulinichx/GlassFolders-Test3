#!/usr/bin/env bash
# Compile Apple Metal IR + Objective-C++ objects + standalone iOS dylib.
# This is a build gate only, not an iPad runtime or compositor test.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v xcrun >/dev/null 2>&1 || {
  echo 'ERROR: xcrun missing. Run this job on macOS with full Xcode.' >&2; exit 2;
}
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
[[ -d "$SDK" ]] || { echo "ERROR: iPhoneOS SDK missing: $SDK" >&2; exit 2; }
OUT="$(mktemp -d "${TMPDIR:-/tmp}/gf-v8-apple-build.XXXXXXXX")"
trap 'rm -rf "$OUT"' EXIT
xcrun --sdk iphoneos metal -c "$HERE/src/GFRefraction.metal" -o "$OUT/GFRefraction.air" || {
  echo 'ERROR: Apple Metal shader compile failed. On Xcode 26+, if toolchain is missing:' >&2
  echo '       xcodebuild -downloadComponent metalToolchain' >&2
  exit 3
}
xcrun --sdk iphoneos metal -o "$OUT/GFRefraction.metallib" "$OUT/GFRefraction.air"
[[ -s "$OUT/GFRefraction.metallib" ]] || { echo 'ERROR: empty Metal library' >&2; exit 3; }
echo 'PASS: Apple iPhoneOS Metal IR + metallib compiled.'

compile_ios() {
  local arch="$1" obj
  for obj in GFRefractionRenderer GFBackboardLiveFrameBridge; do
    xcrun --sdk iphoneos clang++ \
      -arch "$arch" -isysroot "$SDK" -miphoneos-version-min=16.0 \
      -x objective-c++ -std=c++17 -fobjc-arc -fmodules -Wall -Wextra \
      -c "$HERE/src/$obj.mm" -o "$OUT/${obj}-${arch}.o"
  done
  xcrun --sdk iphoneos clang++ -dynamiclib -arch "$arch" \
    -isysroot "$SDK" -miphoneos-version-min=16.0 \
    "$OUT/GFRefractionRenderer-${arch}.o" \
    "$OUT/GFBackboardLiveFrameBridge-${arch}.o" \
    -framework Foundation -framework Metal -framework CoreGraphics \
    -install_name '@rpath/libGFRefractionCore.dylib' \
    -o "$OUT/libGFRefractionCore-${arch}.dylib"
  [[ -s "$OUT/libGFRefractionCore-${arch}.dylib" ]]
  echo "PASS: iPhoneOS $arch C++17/ObjC++ standalone dylib linked."
}
compile_ios arm64
if [[ "${GF_VERIFY_ARM64E:-0}" == 1 ]]; then
  # Apple arm64e linking may require the platform/toolchain chosen by the
  # actual RootHide target. Never claim this tests RootHide packaging.
  compile_ios arm64e
fi
echo 'COMPILE GATE PASSED; iPad GPU/runtime/compositor still untested.'
