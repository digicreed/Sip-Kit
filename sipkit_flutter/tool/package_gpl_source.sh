#!/usr/bin/env bash
# Produce corresponding source for a GPL-native artifact without vendoring it.
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"
require_command git "Install Git, then retry."
require_command tar "Install GNU tar (required for reproducible archive metadata)."
tar --version 2>/dev/null | head -1 | grep -q 'GNU tar' ||
  die "GNU tar is required for reproducible archive metadata (macOS: brew install gnu-tar)."

SOURCE_DIR="${PJPROJECT_SOURCE_DIR:-$PACKAGE_DIR/.native/pjproject}"
OUTPUT="${OUTPUT:-$PACKAGE_DIR/dist/sipkit-pjsip-gpl-source.tar.gz}"
fetch_pjproject "$SOURCE_DIR"
verify_pjproject "$SOURCE_DIR"

git -C "$PACKAGE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
  die "source packaging must run from a Git checkout."
git -C "$PACKAGE_DIR" diff --quiet && git -C "$PACKAGE_DIR" diff --cached --quiet ||
  die "commit or discard changes before packaging so the source archive is reproducible."
epoch="$(git -C "$PACKAGE_DIR" show -s --format=%ct HEAD)"
root="sipkit-pjsip-gpl-source"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/$root"

# git archive avoids timestamps, owner IDs, and ignored build outputs. PJSIP is
# fetched separately at the exact revision rather than committed to this repo.
git -C "$PACKAGE_DIR" archive --format=tar HEAD:sipkit_flutter |
  tar -xf - -C "$stage/$root"
mkdir -p "$stage/$root/third_party/pjproject"
git -C "$SOURCE_DIR" archive --format=tar "$PJPROJECT_COMMIT" |
  tar -xf - -C "$stage/$root/third_party/pjproject"

mkdir -p "$(dirname "$OUTPUT")"
tar --sort=name --mtime="@$epoch" --owner=0 --group=0 --numeric-owner \
  -C "$stage" -czf "$OUTPUT" "$root"
echo "Created reproducible corresponding-source archive: $OUTPUT"