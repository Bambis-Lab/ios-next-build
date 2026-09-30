#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

if [[ -n "$(git status --porcelain=v1)" ]]; then
  echo "Refusing to package a dirty worktree." >&2
  exit 1
fi

commit="$(git rev-parse HEAD)"
short_commit="$(git rev-parse --short=12 HEAD)"
destination="${1:-$project_root/security-audit-$short_commit.tar.gz}"
case "$destination" in
  /|"$HOME"|"$project_root")
    echo "Unsafe audit bundle destination." >&2
    exit 1
    ;;
esac

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
bundle_root="$temporary_directory/IOSNext-security-audit-$short_commit"
mkdir -p "$bundle_root/source" "$bundle_root/evidence"

git archive "$commit" | tar -x -C "$bundle_root/source"
PYTHONPATH=Backend python3 -m unittest discover -s Backend/tests -v \
  >"$bundle_root/evidence/backend-tests.txt" 2>&1
bash Scripts/validate_without_macos.sh \
  >"$bundle_root/evidence/portable-validation.txt" 2>&1

{
  echo "commit=$commit"
  echo "created_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "wireguard_upstream=https://git.zx2c4.com/wireguard-apple"
  echo "wireguard_tag=1.0.16-27"
  echo "wireguard_commit=2fec12a6e1f6e3460b6ee483aa00ad29cddadab1"
} >"$bundle_root/AUDIT_MANIFEST.txt"

find "$bundle_root/source" -type f -print0 \
  | sort -z \
  | xargs -0 sha256sum \
  >"$bundle_root/evidence/source-sha256.txt"

tar -czf "$destination" -C "$temporary_directory" "$(basename "$bundle_root")"
sha256sum "$destination" >"$destination.sha256"
echo "$destination"
