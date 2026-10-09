#!/usr/bin/env python3
"""Functional capacity by school from PPS's Long-Range Facility Plan 2021, Volume 1.

The plan's "Enrollment & Utilization" tables (elementary, K-8, middle, high) list each site with its
permanent classrooms, modular classrooms, functional capacity and forecast utilization for 2021-22 to
2025-26. Functional capacity = classrooms x PPS station size, minus rooms set aside for other uses.

Source: data-raw/pps_reports/facility/LRFP_Vol1_2021.pdf (also checked into meub/pps-data, MIT license)
Output: data/facility_capacity_2021.csv (site, level, classrooms, modular_classrooms, functional_capacity,
        util_2021_22 .. util_2025_26 as fractions, page)
Checks: every row has three integers and five percentages; known values (Atkinson 567, Creston 558,
        Lent 707, Rigler 589, Richmond 723) match; no duplicate sites within a level.
"""
import csv, re, sys
from pathlib import Path
from pypdf import PdfReader

ROOT = Path(__file__).resolve().parent.parent
PDF = ROOT / "data-raw/pps_reports/facility/LRFP_Vol1_2021.pdf"
OUT = ROOT / "data/facility_capacity_2021.csv"
ROW = re.compile(r"^([A-Z][A-Z .'\-/]+?) (\d+) (\d+) (\d+) (\d+)% (\d+)% (\d+)% (\d+)% (\d+)%$")

reader = PdfReader(PDF)
rows, level = [], None
for i, page in enumerate(reader.pages):
    text = page.extract_text() or ""
    found = [ln for ln in (l.strip() for l in text.splitlines()) if ROW.match(ln)]
    if not found:
        continue
    # level from the page's own headings ("PROJECTED UTILIZATION MIDDLE SCHOOL PROGRAMS", "K-8 PROGRAMS", ...)
    up = text.upper()
    level = "middle" if "MIDDLE SCHOOL" in up else "high" if "HIGH SCHOOL" in up else "k8" if "K-8" in up else "elementary"
    for ln in found:
        m = ROW.match(ln)
        rows.append(dict(site=m[1].strip(), level=level, classrooms=int(m[2]), modular_classrooms=int(m[3]),
                         functional_capacity=int(m[4]), **{f"util_{y}": int(m[5 + k]) / 100 for k, y in
                         enumerate(["2021_22", "2022_23", "2023_24", "2024_25", "2025_26"])}, page=i + 1))

if not rows:
    sys.exit("no capacity rows found")
seen = set()
for r in rows:
    k = (r["level"], r["site"])
    if k in seen:
        sys.exit(f"duplicate site {k}")
    seen.add(k)
known = {"ATKINSON": 567, "CRESTON": 558, "LENT": 707, "RIGLER": 589, "RICHMOND": 723}
got = {r["site"]: r["functional_capacity"] for r in rows}
bad = {k: (v, got.get(k)) for k, v in known.items() if got.get(k) != v}
if bad:
    sys.exit(f"known capacities don't match: {bad}")
with open(OUT, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0]))
    w.writeheader(); w.writerows(rows)
by_level = {}
for r in rows:
    by_level[r["level"]] = by_level.get(r["level"], 0) + 1
print(f"OK: {len(rows)} sites {by_level} -> {OUT}")
