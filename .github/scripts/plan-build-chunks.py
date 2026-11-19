#!/usr/bin/env python3
"""Group uncached package drvs into at most MAX_CHUNKS build jobs.

Reads `heavy <drv>` lines (scripts/heavy-drvs.sh) on stdin and prints a JSON
array of space-separated drv lists for a GitHub matrix. Drvs that share an
uncached dependency land in one chunk, so no two jobs build the same thing.
Every drv stays a target: a cached intermediate can hide a requisite, so
building only the roots may skip it.
"""

import json
import os
import subprocess
import sys

MAX_CHUNKS = int(os.environ.get("MAX_CHUNKS", "8"))

heavy = sorted({line.split()[1] for line in sys.stdin if line.startswith("heavy ")})
if not heavy:
    print("[]")
    sys.exit(0)

heavy_set = set(heavy)
deps = {}
for drv in heavy:
    out = subprocess.run(
        ["nix-store", "--query", "--requisites", drv],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.split()
    deps[drv] = {d for d in out if d in heavy_set and d != drv}

parent = {d: d for d in heavy}


def find(d):
    while parent[d] != d:
        parent[d] = parent[parent[d]]
        d = parent[d]
    return d


for drv, ds in deps.items():
    for d in ds:
        parent[find(d)] = find(drv)

groups = {}
for drv in heavy:
    g = groups.setdefault(find(drv), {"drvs": [], "size": 0})
    g["size"] += 1
    g["drvs"].append(drv)

# Largest groups first, each into the currently smallest chunk.
chunks = [{"drvs": [], "size": 0} for _ in range(min(MAX_CHUNKS, len(groups)))]
for g in sorted(groups.values(), key=lambda g: -g["size"]):
    c = min(chunks, key=lambda c: c["size"])
    c["drvs"] += g["drvs"]
    c["size"] += g["size"]

for c in chunks:
    print(f"chunk ({c['size']} drvs): {' '.join(c['drvs'])}", file=sys.stderr)
print(json.dumps([" ".join(c["drvs"]) for c in chunks]))
