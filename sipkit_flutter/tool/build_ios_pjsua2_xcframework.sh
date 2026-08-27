#!/usr/bin/env bash
# Build a GPL PJSUA2 XCFramework on a macOS host with Xcode.
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"
[[ "$(uname -s)" == "Darwin" ]] ||
  die "iOS XCFramework builds require macOS with Xcode."
require_command xcodebuild "Install Xcode and select it with xcode-select."
require_command xcrun "Install Xcode and select it with xcode-select."
require_command make "Install Xcode command-line tools."
require_command libtool "Install Xcode command-line tools."
require_command lipo "Install Xcode command-line tools."

SOURCE_DIR="${PJPROJECT_SOURCE_DIR:-$PACKAGE_DIR/.native/pjproject}"
OUTPUT="${OUTPUT:-$PACKAGE_DIR/ios/Frameworks/PJSIP.xcframework}"
fetch_pjproject "$SOURCE_DIR"
rm -rf "$OUTPUT"
mkdir -p "$(dirname "$OUTPUT")"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
build_slice() {
  local sdk="$1" arch="$2" name="$3"
  (
    cd "$SOURCE_DIR"
    make distclean >/dev/null 2>&1 || true
    export ARCH="$arch"
    export DEVPATH="$(xcrun --sdk "$sdk" --show-sdk-platform-path)/Developer"
    export SDKROOT="$(xcrun --sdk "$sdk" --show-sdk-path)"
    [[ -d "$DEVPATH" ]] || die "Xcode does not provide a developer path for $sdk."
    ./configure-iphone
    make dep
    make
  )
  local -a libraries=()
  local library
  while IFS= read -r library; do
    libraries+=("$library")
  done < <(find "$SOURCE_DIR" -path '*/lib/*.a' -type f | sort)
  ((${#libraries[@]})) || die "PJSIP static libraries were not produced for $name."
  mkdir -p "$work/$name/include"
  # PJSUA2 is not self-contained; merge its PJSIP archive dependencies into
  # one linkable archive for this XCFramework slice.
  libtool -static -o "$work/$name/PJSUA2.a" "${libraries[@]}"
  cp -R "$SOURCE_DIR/pjsip/include/." "$work/$name/include/"
  cp -R "$SOURCE_DIR/pjlib/include/." "$work/$name/include/"
  cp -R "$SOURCE_DIR/pjlib-util/include/." "$work/$name/include/"
  cp -R "$SOURCE_DIR/pjmedia/include/." "$work/$name/include/"
  cp -R "$SOURCE_DIR/pjnath/include/." "$work/$name/include/"
}

# configure-iphone reads ARCH and DEVPATH. XCFramework accepts one device and
# one simulator library, so create a universal simulator archive before export.
build_slice iphoneos arm64 iphoneos
build_slice iphonesimulator arm64 iphonesimulator-arm64
build_slice iphonesimulator x86_64 iphonesimulator-x86_64
lipo -create \
  "$work/iphonesimulator-arm64/PJSUA2.a" \
  "$work/iphonesimulator-x86_64/PJSUA2.a" \
  -output "$work/iphonesimulator/PJSUA2.a"
cp -R "$work/iphonesimulator-arm64/include" "$work/iphonesimulator/"
xcodebuild -create-xcframework \
  -library "$work/iphoneos/PJSUA2.a" -headers "$work/iphoneos/include" \
  -library "$work/iphonesimulator/PJSUA2.a" -headers "$work/iphonesimulator/include" \
  -output "$OUTPUT"
cp "$PACKAGE_DIR/LICENSES/PJPROJECT-GPL-NOTICE.md" "$OUTPUT/"
cp "$SOURCE_DIR/COPYING" "$OUTPUT/GPL-2.0.txt"
echo "Created $OUTPUT from verified pjproject $PJPROJECT_COMMIT"