#!/usr/bin/env bash
# One-command Android TLS build: OpenSSL for all ABIs, then the PJSUA2 AAR.
set -euo pipefail

TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_DIR="$(cd "$TOOL_DIR/.." && pwd)"
export OPENSSL_ANDROID_ROOT="${OPENSSL_ANDROID_ROOT:-$PACKAGE_DIR/.native/android-openssl}"

"$TOOL_DIR/build_android_openssl.sh"
"$TOOL_DIR/build_android_pjsua2_aar.sh"
"$TOOL_DIR/verify_native_artifacts.sh" --android-only

echo "TLS-enabled Android AAR is ready at android/libs/pjsua2-2.14.aar"