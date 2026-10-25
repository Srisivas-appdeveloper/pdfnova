#!/usr/bin/env bash
# Run a flutter command on a local-disk mirror of this project.
#
# Why: on exFAT/FAT drives (e.g. a PortableSSD) macOS writes AppleDouble
# "._*" files next to everything it touches. Gradle and the Flutter tool
# then fail to parse or delete them mid-build ("Unable to delete directory",
# "parseDebugLocalResources", native_assets deletion crashes).
#
# This mirrors the project to an APFS directory WITHOUT ._* files, runs the
# command there, and copies APK/AAB/IPA outputs back into ./build-local/.
# Your sources are never modified; the mirror is a disposable copy.
#
# Usage:
#   tool/local_build.sh test
#   tool/local_build.sh build apk --debug --target-platform android-arm64
#   tool/local_build.sh analyze
# Env:
#   PDFNOVA_LOCAL  mirror directory (default: ~/.cache/pdfnova-build)
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
DST="${PDFNOVA_LOCAL:-$HOME/.cache/pdfnova-build}"
mkdir -p "$DST"

rsync -a --delete \
  --exclude '._*' --exclude '.DS_Store' \
  --exclude 'build/' --exclude 'build-local/' --exclude '.dart_tool/' \
  --exclude '.git/' --exclude 'ios/Pods/' --exclude 'android/.gradle/' \
  "$SRC/" "$DST/"

cd "$DST"
flutter pub get >/dev/null
flutter "$@"

# Bring build artefacts back next to the sources.
if [ -d build/app/outputs ] || [ -d build/ios ]; then
  mkdir -p "$SRC/build-local"
  find build -type f \( -name '*.apk' -o -name '*.aab' -o -name '*.ipa' \) \
    -newer pubspec.yaml -exec cp {} "$SRC/build-local/" \; 2>/dev/null || true
fi
