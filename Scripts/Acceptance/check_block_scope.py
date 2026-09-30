#!/usr/bin/env python3
import argparse
import fnmatch
import subprocess

ALLOWED = {
    "A": [
        "Sources/App/AppRootView.swift",
        "Sources/Design/IOSNextMotionSystem.swift",
        "Sources/Features/AdminAreaView.swift",
        "Tests/*Motion*",
        "UITests/*Motion*",
        "MotionSpecs/**",
        "Scripts/run_motion_frame_acceptance.sh",
        "Scripts/validate_motion_artifacts.py",
        "Scripts/Acceptance/**",
        "codemagic.yaml",
    ],
    "B": [
        "Sources/**FireTV*", "Sources/**/Media*", "Tests/**FireTV*", "UITests/**FireTV*",
        "Scripts/Acceptance/**", "codemagic.yaml"
    ],
    "C": [
        "Sources/**HomeAssistant*", "Sources/**/Room*", "Sources/**/Area*", "Sources/**/Device*",
        "Tests/**Registry*", "Tests/**Resource*", "UITests/**Room*",
        "Scripts/Acceptance/**", "codemagic.yaml"
    ],
    "D": [
        "Sources/Design/**", "Sources/Features/**", "Tests/**UI*", "Tests/**Format*", "UITests/**",
        "Scripts/Acceptance/**", "codemagic.yaml"
    ],
    "E": [
        "Sources/**Runner*", "Sources/**Commander*", "Sources/**MCP*", "Sources/Features/Owner/**",
        "Tests/**Runner*", "Tests/**Commander*", "Tests/**MCP*", "UITests/**ControlCenter*",
        "Scripts/Acceptance/**", "codemagic.yaml"
    ],
}


def matches(path: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatch(path, p) for p in patterns)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("block", choices=sorted(ALLOWED))
    parser.add_argument("--base", required=True)
    parser.add_argument("--head", default="HEAD")
    args = parser.parse_args()

    output = subprocess.check_output(
        ["git", "diff", "--name-only", f"{args.base}...{args.head}"], text=True
    )
    changed = [line.strip() for line in output.splitlines() if line.strip()]
    disallowed = [path for path in changed if not matches(path, ALLOWED[args.block])]

    print(f"BLOCK_SCOPE block={args.block} changed={len(changed)} disallowed={len(disallowed)}")
    for path in changed:
        print(f"  {'OK' if path not in disallowed else 'OUT'} {path}")
    if disallowed:
        raise SystemExit("BLOCK_SCOPE_MISMATCH: changes exceed selected block; use a broader gate or split the PR")


if __name__ == "__main__":
    main()
