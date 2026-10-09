"""Parse PPS School Profiles (Power BI, 2025-26) snapshots into data/school_profiles_2025.csv.

Input: data-raw/pps_reports/school_profiles/*.txt, written by scrape_school_profiles.mjs (the visible
text of the dashboard with one school selected).

Checks (exit non-zero on failure):
  - every snapshot has the core fields and a unique address (so no snapshot repeats the previous school)
  - utilization = enrollment / functional capacity, within 0.6 percentage points of the printed rate
  - capture rate = students in neighborhood school / PPS students living in zone, within 0.1 point
Values the dashboard abbreviates (e.g. "2K") are left blank.

Usage: python3 data-raw/parse_school_profiles.py
"""
import csv, glob, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "pps_reports", "school_profiles")
OUT = os.path.join(HERE, "..", "data", "school_profiles_2025.csv")

LABELS = {  # field -> label line that precedes the value
    "enrollment_2025": "2025 - 2026 Enrollment",
    "projected_2026": "2026 - 2027 Projected",
    "direct_cert": "2025 - 2026 Direct Cert.",
    "students_in_neighborhood_school": "Students in Neighborhood School",
    "pps_students_live_in_zone": "PPS Students Live in Zone",
    "capture_rate": "In District Capture Rate",
    "utilization": "2025-2026 Utilization Rate",
    "program_type": "Program Type",
    "title1": "Title 1",
    "immersion_language": "Immersion Language",
    "immersion_language_2": "Immersion Language 2",
}
INLINE = {"address": "Address", "originally_built_for": "Originally Built For", "hs_cluster": "HS Cluster",
          "primary_use": "Primary Use", "grades": "Grades", "year_built": "Year Built", "square_feet": "Square Footage"}

def num(v, pct=False):
    if v is None or v in ("--", "") or re.search(r"[KM]$", v):
        return None
    v = v.replace(",", "").rstrip("%")
    x = float(v)
    return x / 100 if pct else x

def after(lines, label):
    for i, l in enumerate(lines):
        if l.strip() == label:
            for v in lines[i + 1:i + 4]:
                if v.strip():
                    return v.strip()
    return None

rows, errors = [], []
for f in sorted(glob.glob(os.path.join(SRC, "*.txt"))):
    raw = open(f, encoding="utf-8").read()
    selected = re.search(r"^SELECTED: (.*)$", raw, re.M).group(1)
    retrieved = re.search(r"^RETRIEVED: (.*)$", raw, re.M).group(1)
    body = raw[raw.find("\nAddress:"):]
    lines = body.split("\n")
    r = {"school": selected, "retrieved": retrieved[:10]}
    m = re.search(r"^Address: (.*)$", body, re.M)
    r["address"] = m.group(1).strip() if m else None
    for k, lab in INLINE.items():
        m = re.search(rf"^{re.escape(lab)}: (.*)$", body, re.M)
        r[k] = m.group(1).strip() if m else None
    # functional capacity: the second (unrounded) tile, labelled "Functional\nCapacity"
    m = re.search(r"\nFunctional\nCapacity\n\n([\d,.]+)", body)
    r["functional_capacity"] = num(m.group(1)) if m else num(after(lines, "Functional Capacity"))
    tile = num(after(lines, "Functional Capacity"))  # the rounded tile
    no_site = (r.get("address") or "").startswith("No Address")
    for k, lab in LABELS.items():
        r[k] = after(lines, lab)
    r["immersion_language"] = re.search(r"\nImmersion Language\n\n(.*)\n", body).group(1).strip() if "\nImmersion Language\n" in body else None
    for k in ("enrollment_2025", "projected_2026", "students_in_neighborhood_school", "pps_students_live_in_zone"):
        r[k] = num(r[k])
    for k in ("direct_cert", "capture_rate", "utilization"):
        r[k] = num(r[k], pct=True)
    r["year_built"] = num(r["year_built"])
    r["square_feet"] = num(r["square_feet"])
    for k in ("immersion_language", "immersion_language_2"):
        if r[k] in ("--", ""):
            r[k] = None
    if no_site:  # programs without a building of their own (e.g. Alliance): keep the row, blank the building fields
        r["address"] = None
        for k in ("functional_capacity", "utilization"):
            r[k] = None
    elif not r["address"] or r["functional_capacity"] is None or r["enrollment_2025"] is None:
        errors.append(f"{selected}: missing core fields")
    elif tile is not None and abs(tile - r["functional_capacity"]) > 1:
        errors.append(f"{selected}: capacity tiles disagree ({tile} vs {r['functional_capacity']})")
    if r["functional_capacity"] and r["enrollment_2025"] is not None and r["utilization"] is not None:
        if abs(r["enrollment_2025"] / r["functional_capacity"] - r["utilization"]) > 0.006:
            errors.append(f"{selected}: utilization {r['utilization']:.3f} != {r['enrollment_2025']}/{r['functional_capacity']}")
    if r["students_in_neighborhood_school"] and r["pps_students_live_in_zone"] and r["capture_rate"] is not None:
        if abs(r["students_in_neighborhood_school"] / r["pps_students_live_in_zone"] - r["capture_rate"]) > 0.001:
            errors.append(f"{selected}: capture {r['capture_rate']} != {r['students_in_neighborhood_school']}/{r['pps_students_live_in_zone']}")
    rows.append(r)

addr = {}
for r in rows:
    if r["address"] is None:
        continue
    addr.setdefault(r["address"], []).append(r["school"])
dups = {a: s for a, s in addr.items() if len(s) > 1}
if dups:
    errors.append(f"addresses repeated (a snapshot may show the wrong school): {dups}")
if len(rows) < 50:
    errors.append(f"only {len(rows)} snapshots")
if errors:
    print("FAILED:\n  " + "\n  ".join(errors))
    sys.exit(1)

cols = ["school", "address", "grades", "primary_use", "originally_built_for", "hs_cluster", "year_built", "square_feet",
        "functional_capacity", "enrollment_2025", "utilization", "projected_2026", "direct_cert",
        "students_in_neighborhood_school", "pps_students_live_in_zone", "capture_rate",
        "program_type", "title1", "immersion_language", "immersion_language_2", "retrieved"]
with open(OUT, "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore")
    w.writeheader()
    w.writerows(rows)
print(f"{len(rows)} schools -> {os.path.relpath(OUT)}; all utilization and capture checks pass")
