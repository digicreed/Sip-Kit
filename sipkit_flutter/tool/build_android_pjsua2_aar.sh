#!/usr/bin/env bash
# Build a GPL PJSUA2 Android AAR, including upstream SWIG Java bindings.
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
[[ -n "$ANDROID_NDK_HOME" && -d "$ANDROID_NDK_HOME" ]] ||
  die "ANDROID_NDK_HOME (or ANDROID_NDK_ROOT) must name an installed Android NDK."
[[ -x "$ANDROID_NDK_HOME/ndk-build" ]] ||
  die "ANDROID_NDK_HOME does not contain ndk-build: $ANDROID_NDK_HOME"
require_command make "Install make (for example, Xcode command-line tools or build-essential)."
require_command zip "Install zip to assemble the AAR."
require_command jar "Install a JDK; jar is required to create classes.jar."
require_command javac "Install a JDK; javac is required by the upstream SWIG Java build."
require_command swig "Install SWIG; it generates the upstream PJSUA2 Java bindings."

SOURCE_DIR="${PJPROJECT_SOURCE_DIR:-$PACKAGE_DIR/.native/pjproject}"
ABIS=(arm64-v8a armeabi-v7a x86_64)
fetch_pjproject "$SOURCE_DIR"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
OUTPUT="${OUTPUT:-$PACKAGE_DIR/android/libs/pjsua2-2.14.aar}"
mkdir -p "$(dirname "$OUTPUT")" "$work/jni" "$work/classes" "$work/META-INF"
printf '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.pjsip.pjsua2"/>\n' > "$work/AndroidManifest.xml"
cp "$PACKAGE_DIR/LICENSES/PJPROJECT-GPL-NOTICE.md" "$work/META-INF/"
cp "$SOURCE_DIR/COPYING" "$work/META-INF/GPL-2.0.txt"

for abi in "${ABIS[@]}"; do
  echo "Building pjproject $PJPROJECT_COMMIT for Android $abi"
  (
    cd "$SOURCE_DIR"
    make distclean >/dev/null 2>&1 || true
    export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME" TARGET_ABI="$abi"
    # Keep the normal static PJSIP dependency build. The SWIG target links
    # those archives into libpjsua2.so, avoiding a variable set of PJSIP .so
    # files in the AAR.
    ./configure-android --use-ndk-cflags
    make dep
    make
    make -C pjsip-apps/src/swig java
  )
  mkdir -p "$work/jni/$abi"
  native_dir="$SOURCE_DIR/pjsip-apps/src/swig/java/android/pjsua2/src/main/jniLibs/$abi"
  pjsua2_so="$native_dir/libpjsua2.so"
  [[ -f "$pjsua2_so" ]] ||
    die "upstream SWIG build produced no libpjsua2.so for $abi."
  cp "$pjsua2_so" "$work/jni/$abi/"

  cxx_runtime="$native_dir/libc++_shared.so"
  [[ -f "$cxx_runtime" ]] ||
    die "upstream SWIG build produced no libc++_shared.so for $abi."
  cp "$cxx_runtime" "$work/jni/$abi/"

  # Java bytecode is ABI-independent, but build it with each SWIG invocation
  # so the generated JNI library and bindings are always from the same source.
  if [[ "$abi" == "${ABIS[0]}" ]]; then
    generated_classes="$SOURCE_DIR/pjsip-apps/src/swig/java/output/org"
    [[ -d "$generated_classes/pjsip/pjsua2" ]] ||
      die "upstream SWIG Java target produced no compiled bindings for $abi."
    cp -R "$generated_classes" "$work/classes/"
    [[ -d "$work/classes/org/pjsip/pjsua2" ]] ||
      die "compiled output does not contain org/pjsip/pjsua2 bindings."
  fi
done

generated_class="$(find "$work/classes/org/pjsip/pjsua2" -type f -name '*.class' -print -quit)"
[[ -n "$generated_class" ]] ||
  die "generated PJSUA2 Java bindings contain no class files."
(cd "$work/classes" && jar cf "$work/classes.jar" org)
(cd "$work" && zip -X -q -r "$OUTPUT" AndroidManifest.xml classes.jar jni META-INF)
echo "Created $OUTPUT from verified pjproject $PJPROJECT_COMMIT"