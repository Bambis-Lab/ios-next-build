#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dependency_root="$project_root/.build-dependencies/wireguard-apple"
expected_commit="2fec12a6e1f6e3460b6ee483aa00ad29cddadab1"
primary_url="https://git.zx2c4.com/wireguard-apple"
fallback_url="https://github.com/WireGuard/wireguard-apple.git"

clone_from() {
  local url="$1"
  local attempts=3
  local delay=3
  local i

  rm -rf "$dependency_root"
  mkdir -p "$(dirname "$dependency_root")"

  for ((i=1; i<=attempts; i++)); do
    echo "WireGuard clone attempt $i/$attempts from $url"
    if git clone --quiet --no-checkout "$url" "$dependency_root"; then
      return 0
    fi
    rm -rf "$dependency_root"
    mkdir -p "$(dirname "$dependency_root")"
    if (( i < attempts )); then
      sleep "$delay"
      delay=$((delay * 2))
    fi
  done

  return 1
}

fetch_expected_commit() {
  local attempts=3
  local delay=3
  local i

  for ((i=1; i<=attempts; i++)); do
    echo "WireGuard fetch attempt $i/$attempts for $expected_commit"
    if git -C "$dependency_root" fetch --quiet --depth 1 origin "$expected_commit"; then
      return 0
    fi
    if (( i < attempts )); then
      sleep "$delay"
      delay=$((delay * 2))
    fi
  done

  return 1
}

if [[ ! -d "$dependency_root/.git" ]]; then
  if ! clone_from "$primary_url"; then
    echo "Primary WireGuard source unavailable; falling back to official GitHub mirror." >&2
    clone_from "$fallback_url"
  fi
fi

if ! fetch_expected_commit; then
  current_origin="$(git -C "$dependency_root" remote get-url origin || true)"
  if [[ "$current_origin" != "$fallback_url" ]]; then
    echo "Pinned commit fetch failed from primary source; retrying via official GitHub mirror." >&2
    git -C "$dependency_root" remote set-url origin "$fallback_url"
    fetch_expected_commit
  else
    exit 1
  fi
fi

git -C "$dependency_root" checkout --quiet --detach "$expected_commit"

actual_commit="$(git -C "$dependency_root" rev-parse HEAD)"
if [[ "$actual_commit" != "$expected_commit" ]]; then
  echo "Unexpected WireGuard source commit: $actual_commit" >&2
  exit 1
fi

if head -n 1 "$dependency_root/Package.swift" | grep -Eq 'swift-tools-version:5\.3'; then
  perl -pi -e 's#swift-tools-version:5\.3#swift-tools-version:5.5#' \
    "$dependency_root/Package.swift"
fi

if ! grep -Eq '^#include <sys/types\.h>$' \
  "$dependency_root/Sources/WireGuardKitC/WireGuardKitC.h"; then
  perl -0pi -e 's/#include "key\.h"/#include <sys\/types.h>\n\n#include "key.h"/' \
    "$dependency_root/Sources/WireGuardKitC/WireGuardKitC.h"
fi

status="$(git -C "$dependency_root" status --short)"
expected_status=$' M Package.swift\n M Sources/WireGuardKitC/WireGuardKitC.h'
if [[ "$status" != "$expected_status" ]] || \
   ! head -n 1 "$dependency_root/Package.swift" | grep -Eq 'swift-tools-version:5\.5'; then
  echo "WireGuard dependency differs from the two-file audited compatibility patch." >&2
  git -C "$dependency_root" status --short >&2
  exit 1
fi

echo "Prepared WireGuardKit $expected_commit with audited Xcode 27 compatibility."
