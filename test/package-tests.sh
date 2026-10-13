#!/usr/bin/env bash
# Runs `swift test` in every local Swift package under Packages/.
#
# usage: test/package-tests.sh --linux | --macos
#
# --linux tests every package except those holding a `.apple-only` marker file
# (packages that need Apple frameworks such as Security or SwiftUI); --macos
# tests every package on the Mac host, so each package declares a .macOS
# platform next to .iOS(.v18). With no packages yet, this passes.
set -euo pipefail

cd "$(dirname "$0")/.."

case "${1:-}" in
  --linux) host=linux ;;
  --macos) host=macos ;;
  *)
    sed -n '4p' "$0" | sed 's/^# //' >&2
    exit 64
    ;;
esac

found=0
failed=()
for manifest in Packages/*/Package.swift; do
  [ -f "$manifest" ] || continue
  package="$(dirname "$manifest")"
  if [ "$host" = linux ] && [ -e "$package/.apple-only" ]; then
    echo "skip: $package is Apple-only; xcode.yml tests it on macOS"
    continue
  fi
  found=$((found + 1))
  echo "::group::swift test in $package"
  if swift test --package-path "$package"; then
    echo "::endgroup::"
    echo "ok: $package"
  else
    echo "::endgroup::"
    echo "FAIL: $package" >&2
    failed+=("$package")
  fi
done

if [ "$found" -eq 0 ]; then
  echo "No packages to test on $host."
fi
if [ ${#failed[@]} -gt 0 ]; then
  echo "swift test failed in: ${failed[*]}" >&2
  exit 1
fi
