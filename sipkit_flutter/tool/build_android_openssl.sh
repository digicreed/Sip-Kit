#!/usr/bin/env bash
# Build pinned static OpenSSL libraries for every Android ABI packaged by SipKit.
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

OPENSSL_REPOSITORY="https://github.com/openssl/openssl.git"
OPENSSL_COMMIT="54f5fca0d0b15f912e7355a378976cbff12d58fc"
OPENSSL_VERSION="3.0.4"
ANDROID_API="${ANDROID_API:-24}"
ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
OUTPUT_ROOT="${OPENSSL_ANDROID_ROOT:-$PACKAGE_DIR/.native/android-openssl}"
SOURCE_DIR="${OPENSSL_SOURCE_DIR:-$PACKAGE_DIR/.native/openssl-$OPENSSL_VERSION}"
JOBS="${JOBS:-}"

[[ -n "$ANDROID_NDK_HOME" && -d "$ANDROID_NDK_HOME" ]] ||
  die "ANDROID_NDK_HOME (or ANDROID_NDK_ROOT) must name an installed Android NDK."
[[ -d "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt" ]] ||
  die "Android NDK LLVM toolchain not found under $ANDROID_NDK_HOME."
[[ "$ANDROID_API" =~ ^[0-9]+$ ]] ||
  die "ANDROID_API must be an integer."
require_command git "Install Git, then retry."
require_command make "Install GNU make, then retry."
require_command perl "Install Perl; OpenSSL Configure requires it."

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) host_tag="linux-x86_64" ;;
  Darwin-x86_64) host_tag="darwin-x86_64" ;;
  Darwin-arm64) host_tag="darwin-arm64" ;;
  *) die "Unsupported OpenSSL build host: $(uname -s)-$(uname -m)" ;;
esac

toolchain_bin="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$host_tag/bin"
[[ -d "$toolchain_bin" ]] ||
  die "Android NDK has no toolchain for host $host_tag: $toolchain_bin"

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
  mkdir -p "$(dirname "$SOURCE_DIR")"
  git clone --no-checkout "$OPENSSL_REPOSITORY" "$SOURCE_DIR"
fi
git -C "$SOURCE_DIR" fetch --depth=1 origin "$OPENSSL_COMMIT"
git -C "$SOURCE_DIR" checkout --detach --force "$OPENSSL_COMMIT"
actual="$(git -C "$SOURCE_DIR" rev-parse HEAD)"
[[ "$actual" == "$OPENSSL_COMMIT" ]] ||
  die "OpenSSL is $actual, expected pinned commit $OPENSSL_COMMIT"

if [[ -z "$JOBS" ]]; then
  if command -v nproc >/dev/null 2>&1; then
    JOBS="$(nproc)"
  else
    JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
  fi
fi

mkdir -p "$OUTPUT_ROOT"
cp "$SOURCE_DIR/LICENSE.txt" "$OUTPUT_ROOT/LICENSE.txt"
printf 'OpenSSL %s\ncommit %s\n' "$OPENSSL_VERSION" "$OPENSSL_COMMIT" \
  > "$OUTPUT_ROOT/BUILD-INFO.txt"

abis=(arm64-v8a armeabi-v7a x86_64)
targets=(android-arm64 android-arm android-x86_64)

for index in "${!abis[@]}"; do
  abi="${abis[$index]}"
  target="${targets[$index]}"
  prefix="$OUTPUT_ROOT/$abi"
  build_dir="$(mktemp -d)"
  echo "Building OpenSSL $OPENSSL_VERSION for $abi (API $ANDROID_API)"
  git clone --quiet --shared --no-checkout "$SOURCE_DIR" "$build_dir"
  git -C "$build_dir" checkout --quiet --detach "$OPENSSL_COMMIT"
  (
    cd "$build_dir"
    export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
    export PATH="$toolchain_bin:$PATH"
    ./Configure "$target" \
      "-D__ANDROID_API__=$ANDROID_API" \
      no-shared \
      no-tests \
      --prefix="$prefix" \
      --openssldir="$prefix/ssl" \
      --libdir=lib
    make -j"$JOBS"
    make install_sw
  )
  rm -rf "$build_dir"
  [[ -f "$prefix/include/openssl/ssl.h" ]] ||
    die "OpenSSL headers were not installed for $abi."
  [[ -f "$prefix/lib/libssl.a" && -f "$prefix/lib/libcrypto.a" ]] ||
    die "Static OpenSSL libraries were not installed for $abi."
done

echo "Created Android OpenSSL build root: $OUTPUT_ROOT"