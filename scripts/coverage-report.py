#!/usr/bin/env python3
"""Print per-file line coverage from an lcov file, and optionally gate on it."""
import argparse
import collections
import sys


def parse(path):
    files = collections.OrderedDict()
    current = None
    with open(path) as fh:
        for line in fh:
            if line.startswith("SF:"):
                current = line[3:].strip()
                files.setdefault(current, [0, 0])
            elif line.startswith("DA:") and current:
                _, hits = line[3:].strip().split(",")
                files[current][1] += 1
                if int(hits) > 0:
                    files[current][0] += 1
    return files


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("lcov")
    ap.add_argument("--gate", type=float, default=None,
                    help="fail if total coverage is below this percentage")
    ap.add_argument("--only", default=None,
                    help="restrict to files whose path contains this substring")
    args = ap.parse_args()

    try:
        files = parse(args.lcov)
    except FileNotFoundError:
        print(f"no coverage data at {args.lcov} — run the tests first", file=sys.stderr)
        return 1

    hit = total = 0
    rows = []
    for path, (h, t) in sorted(files.items()):
        if args.only and args.only not in path:
            continue
        if t == 0:
            continue
        hit += h
        total += t
        rows.append((100 * h / t, h, t, path.split("lib/")[-1]))

    if not rows:
        print("no matching files in the coverage data", file=sys.stderr)
        return 1

    for pct, h, t, name in rows:
        print(f"{pct:6.1f}%  {h:4d}/{t:<4d}  {name}")

    overall = 100 * hit / total
    print("-" * 62)
    label = f"TOTAL{f' ({args.only})' if args.only else ''}"
    print(f"{overall:6.1f}%  {hit:4d}/{total:<4d}  {label}")

    if args.gate is not None and overall < args.gate:
        print(f"\n\033[0;31m✗\033[0m coverage {overall:.1f}% is below the "
              f"{args.gate:.0f}% gate", file=sys.stderr)
        return 1
    if args.gate is not None:
        print(f"\033[0;32m✓\033[0m coverage gate passed ({overall:.1f}% ≥ {args.gate:.0f}%)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
