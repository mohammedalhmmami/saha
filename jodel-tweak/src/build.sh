#!/bin/bash
# build.sh — compile JodelTweak.dylib for arm64 iOS.
# Run on a Mac with Xcode installed, OR via the GitHub Actions workflow
# (.github/workflows/build-tweak.yml) which runs this script on macos-15-intel.
# Usage: ./build.sh            (writes JodelTweak.dylib next to this script)
#        ./build.sh /path/out  (writes JodelTweak.dylib to /path/out)
set -euo pipefail
cd "$(dirname "$0")"
OUT_DIR="${1:-.}"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
echo "iOS SDK: $SDK"
xcrun clang \
  -arch arm64 \
  -isysroot "$SDK" \
  -miphoneos-version-min=16.4 \
  -fobjc-arc \
  -O2 \
  -dynamiclib \
  -install_name "@rpath/JodelTweak.dylib" \
  -framework Foundation \
  -framework UIKit \
  -framework Security \
  -o "$OUT_DIR/JodelTweak.dylib" \
  JodelTweak.m JodelTweakProtection.m
echo "Built: $OUT_DIR/JodelTweak.dylib"
file "$OUT_DIR/JodelTweak.dylib"
ls -lh "$OUT_DIR/JodelTweak.dylib"
