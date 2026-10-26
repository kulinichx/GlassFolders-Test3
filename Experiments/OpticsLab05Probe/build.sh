#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
: "${THEOS:?Set THEOS to RootHide Theos installation root}"
mkdir -p Resources .build
SDK=iphoneos
if ! xcrun -sdk "$SDK" --find metal >/dev/null 2>&1; then
  echo 'Metal compiler not installed: install Xcode Metal Toolchain first.' >&2
  exit 1
fi
xcrun -sdk "$SDK" metal -std=metal3.0 -mios-version-min=16.0 -c ../GFRefraction.metal -o .build/GFRefraction.air
xcrun -sdk "$SDK" metal -std=metal3.0 -mios-version-min=16.0 -c GFProbeShaders.metal -o .build/GFProbeShaders.air
xcrun -sdk "$SDK" metallib .build/GFRefraction.air .build/GFProbeShaders.air -o Resources/GFOpticsLab05.metallib
make THEOS="$THEOS" THEOS_PACKAGE_SCHEME=roothide package FINALPACKAGE=1 ARCHS=arm64e
