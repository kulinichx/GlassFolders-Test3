#!/usr/bin/env bash
# Optional host-only compile of the Metal GPU smoke tool on macOS.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v xcrun >/dev/null || { echo 'SKIP: macOS Xcode not present'; exit 2; }
SDK="$(xcrun --sdk macosx --show-sdk-path)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/gf-v8-smoke.XXXXXXXX")"
trap 'rm -rf "$OUT"' EXIT
xcrun --sdk macosx clang++ -std=c++17 -fobjc-arc -fmodules -Wall -Wextra \
   -isysroot "$SDK" -x objective-c++ \
   "$ROOT/src/GFRefractionRenderer.mm" "$ROOT/tools/gpu-smoke.mm" \
   -framework Foundation -framework Metal -framework CoreGraphics \
   -o "$OUT/gf-gpu-smoke"
echo 'PASS: macOS Metal smoke program compiled.'
if [[ "${GF_RUN_GPU_SMOKE:-0}" == 1 ]]; then
   "$OUT/gf-gpu-smoke"
else
   echo 'SKIP: GPU runtime not executed (set GF_RUN_GPU_SMOKE=1 on a Mac with Metal GPU).'
fi
