#!/usr/bin/env python3
"""Minimal VCP validator stub.

Replace this with the real spec checks. Exits non-zero when no input is found.
"""

import argparse
import glob
import json
import os
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", required=True)
    args = parser.parse_args()

    pattern = os.path.join(args.input_dir, "*.json")
    files = glob.glob(pattern)
    if not files:
        print(f"No proof JSON files found in: {args.input_dir}")
        return 1

    # Lightweight parse to ensure JSON is well-formed.
    for path in files:
        with open(path, "r", encoding="utf-8") as f:
            json.load(f)
        print(f"OK: {path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
