#!/usr/bin/env python3
"""Summarize raw rdmsr_bench CSV; all units are invariant-TSC ticks."""
import csv
import statistics
import sys


def main(path):
    with open(path, encoding="utf-8") as source:
        rows = list(csv.DictReader(line for line in source if not line.startswith("#")))
    if not rows:
        raise SystemExit("No samples in input")
    columns = {key: sorted(int(row[key]) for row in rows)
               for key in ("empty_ticks", "rdmsr_ticks")}
    print(f"{len(rows)} samples; units: TSC ticks (not necessarily core cycles)")
    for key, values in columns.items():
        print(f"{key:12s}: min={values[0]} median={statistics.median(values):g} "
              f"p95={values[(len(values) - 1) * 95 // 100]} max={values[-1]}")
    estimate = (statistics.median(columns["rdmsr_ticks"])
                - statistics.median(columns["empty_ticks"]))
    print(f"Median RDMSR minus median empty: {estimate:g} TSC ticks")
    print("Baseline subtraction is an estimate, not an exact instruction latency.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: {sys.argv[0]} results.csv")
    main(sys.argv[1])
