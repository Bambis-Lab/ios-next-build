#!/usr/bin/env python3
import argparse
import hashlib
import json
import time
from pathlib import Path

from PIL import Image, ImageChops

EXPECTED = {"startup": 87, "control-center-unlock": 109, "control-center-lock": 27}


def open_rgba(path: Path):
    image = Image.open(path)
    image.load()
    if image.mode != "RGBA":
        image = image.convert("RGBA")
    return image


def compare_pixels(current: Path, golden: Path):
    with open_rgba(current) as current_image, open_rgba(golden) as golden_image:
        if current_image.size != golden_image.size:
            return {
                "ok": False,
                "reason": "dimension_mismatch",
                "current": list(current_image.size),
                "golden": list(golden_image.size),
            }
        diff = ImageChops.difference(current_image, golden_image)
        histogram = diff.histogram()
        total = sum(histogram)
        abs_sum = sum((index % 256) * count for index, count in enumerate(histogram))
        high = sum(count for index, count in enumerate(histogram) if (index % 256) > 12)
        max_delta = max((index % 256 for index, count in enumerate(histogram) if count), default=0)
        mean = abs_sum / max(total, 1)
        high_ratio = high / max(total, 1)
        ok = mean <= 1.5 and high_ratio <= 0.005
        return {
            "ok": ok,
            "mean_abs_delta": round(mean, 6),
            "ratio_delta_gt_12": round(high_ratio, 8),
            "max_delta": max_delta,
            "size": list(current_image.size),
        }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--frames", required=True)
    parser.add_argument("--goldens")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    started = time.monotonic()
    root = Path(args.frames)
    golden_root = Path(args.goldens) if args.goldens else None
    enforced = bool(golden_root and (golden_root / ".enforced").exists())
    result = {
        "schema_version": 2,
        "golden_mode": "enforced" if enforced else "candidate",
        "sequences": {},
    }
    overall_ok = True
    processed = 0
    expected_total = sum(EXPECTED.values())

    print(
        f"Motion artifact validation started: frames={expected_total}; "
        f"golden_mode={result['golden_mode']}; engine=Pillow",
        flush=True,
    )

    for sequence, count in EXPECTED.items():
        directory = root / sequence
        files = [directory / f"frame-{index:03d}.png" for index in range(count)]
        missing = [str(path) for path in files if not path.is_file()]
        if missing:
            raise SystemExit(f"missing motion frames for {sequence}: {missing[:5]}")
        extra = sorted(directory.glob("frame-*.png"))
        if len(extra) != count:
            raise SystemExit(f"unexpected frame count for {sequence}: {len(extra)} != {count}")

        print(f"Validating sequence {sequence}: {count} frames", flush=True)
        dimensions = set()
        entries = []
        for index, path in enumerate(files):
            with open_rgba(path) as image:
                width, height = image.size
            dimensions.add((width, height))
            entry = {
                "frame": index,
                "time_ms": round(index * 1000 / 120, 3),
                "file": path.name,
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "pixels": [width, height],
            }
            if golden_root:
                golden = golden_root / sequence / path.name
                if golden.exists():
                    comparison = compare_pixels(path, golden)
                    entry["golden_compare"] = comparison
                    overall_ok = overall_ok and comparison["ok"]
                elif enforced:
                    entry["golden_compare"] = {"ok": False, "reason": "missing_golden"}
                    overall_ok = False
            entries.append(entry)
            processed += 1
            if processed % 10 == 0 or processed == expected_total:
                elapsed = time.monotonic() - started
                print(
                    f"Motion validation progress: {processed}/{expected_total} frames "
                    f"({elapsed:.1f}s elapsed)",
                    flush=True,
                )

        if len(dimensions) != 1:
            raise SystemExit(f"frame dimensions changed within {sequence}: {sorted(dimensions)}")
        result["sequences"][sequence] = {
            "frame_count": count,
            "dimensions": list(next(iter(dimensions))),
            "frames": entries,
        }

    result["ok"] = overall_ok
    result["validation_seconds"] = round(time.monotonic() - started, 3)
    Path(args.output).write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(
        f"Motion V2 artifacts valid: {expected_total} frames; "
        f"golden_mode={result['golden_mode']}; ok={overall_ok}; "
        f"elapsed={result['validation_seconds']}s",
        flush=True,
    )
    if enforced and not overall_ok:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
