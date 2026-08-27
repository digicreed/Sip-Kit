#!/usr/bin/env bash
# Shared, intentionally small helpers for the native artifact scripts.
set -euo pipefail

TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "$TOOL_DIR/.." && pwd)"
source "$TOOL_DIR/pjproject.env"

die() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing prerequisite '$1'. $2"
}

verify_pjproject() {
  local source_dir="$1"
  [[ -d "$source_dir/.git" ]] || die "pjproject source is not a Git checkout: $source_dir"
  local actual
  actual="$(git -C "$source_dir" rev-parse HEAD)"
  [[ "$actual" == "$PJPROJECT_COMMIT" ]] ||
    die "pjproject is $actual, expected pinned commit $PJPROJECT_COMMIT"
}

fetch_pjproject() {
  local source_dir="$1"
  require_command git "Install Git, then retry."
  if [[ ! -d "$source_dir/.git" ]]; then
    mkdir -p "$(dirname "$source_dir")"
    git clone --no-checkout "$PJPROJECT_REPOSITORY" "$source_dir"
  fi
  git -C "$source_dir" fetch --depth=1 origin "$PJPROJECT_COMMIT"
  git -C "$source_dir" checkout --detach --force "$PJPROJECT_COMMIT"
  verify_pjproject "$source_dir"
}