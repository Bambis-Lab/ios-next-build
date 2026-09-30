#!/usr/bin/env python3
from pathlib import Path
import argparse
import filecmp
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Backend" / "admin_service"
TARGET = ROOT / "HAAddons" / "iosnext-owner-admin" / "admin_service"


def python_files(root: Path) -> dict[str, Path]:
    return {
        str(path.relative_to(root)): path
        for path in root.rglob("*.py")
        if "__pycache__" not in path.parts
    }


def check() -> bool:
    source = python_files(SOURCE)
    target = python_files(TARGET) if TARGET.exists() else {}
    if set(source) != set(target):
        return False
    return all(filecmp.cmp(source[name], target[name], shallow=False) for name in source)


def sync() -> None:
    if TARGET.exists():
        shutil.rmtree(TARGET)
    shutil.copytree(SOURCE, TARGET, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        if not check():
            print("Owner add-on backend is out of sync", file=sys.stderr)
            return 1
        print("Owner add-on backend sync check passed.")
        return 0
    sync()
    print(f"Synced {SOURCE.relative_to(ROOT)} -> {TARGET.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
