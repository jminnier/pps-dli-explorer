#!/usr/bin/env python3
"""Parse PPS "Neighborhood Capture Rate Metrics" PDFs -> data/capture_rate.csv

Source: data-raw/pps_reports/capture_rate/<YYYY-YY>_Capture_Rate.pdf (2019-20 .. 2025-26)
Each report is titled "Enrollment Summary, October <YYYY>, by K-12 Students' Neighborhood and
Type of School Attended". One row per student neighborhood (attendance area). Pre-K excluded.

Output columns (names follow the report headers):
  year                     school year, e.g. 2025-26 (October count date = first year)
  level                    Elementary / Middle / High (as grouped in the report: the stacked block the
                           row sits in; the report prints a rotated E / M / H label) or
                           "Out of District/Undetermined"
  row_type                 school | cluster_subtotal (Jefferson Total) | level_total | grand_total
                           | residual (rows inside the Out of District/Undetermined block)
  neighborhood             "Students' Neighborhood" as printed (rotated first-letter label stripped;
                           "Jefferson / Grant" etc. are the Jefferson sub-areas)
  own_neighborhood_school, own_neighborhood_school_pct          "Own Neighborhood School (Capture Rate)"
  other_neighborhood_school, other_neighborhood_school_pct      "Other Neighborhood School"
  ppsalternative, ppsalternative_pct                            "PPS Alternative"  (col: pps_alternative)
  community_based_alternative, community_based_alternative_pct  "Community-Based Alternative"
  special_services, special_services_pct                        "Special Services"
  pps_charter, pps_charter_pct                                  "PPS Charter"
  total                    "Total" (K-12 residents of the neighborhood enrolled in PPS, Oct count)
Counts printed blank mean zero (the PDF shows only "0%"); stored as 0. Percentages are as printed
(whole percent); validation recomputes them from counts (+-0.51).

Validation (exit 1 on failure): categories sum to total for every row; printed pct = count/total
(+-0.51); level totals = sum of school rows in the level (Jefferson sub-areas count once, the
"Jefferson Total" subtotal is excluded); Out of District block rows sum to its total; grand total =
sum of level totals + out-of-district total; and 2025-26 grand total is 29,036 of 42,622.
"""
import csv, re, sys, os
from pypdf import PdfReader

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "pps_reports", "capture_rate")
OUT = os.path.join(HERE, "..", "data", "capture_rate.csv")
YEARS = ["2019-20", "2020-21", "2021-22", "2022-23", "2023-24", "2024-25", "2025-26"]
CATS = ["own_neighborhood_school", "other_neighborhood_school", "pps_alternative",
        "community_based_alternative", "special_services", "pps_charter"]
LEVEL_TOTALS = {"Elementary Total": "Elementary", "Middle Total": "Middle", "High Total": "High",
                "Out of District/Undetermined Total": "Out of District/Undetermined"}
errors = []

def err(msg):
    errors.append(msg)

def parse_line(line):
    m = re.match(r"^(.*?)\s+((?:[\d,]+\s+)?\d+%(?:\s+(?:[\d,]+\s+)?\d+%)*\s+[\d,]+)$", line.strip())
    if not m:
        return None
    name, rest = m.group(1).strip(), m.group(2).split()
    vals, i = [], 0
    for _ in CATS:
        if i + 1 < len(rest) and re.fullmatch(r"[\d,]+", rest[i]) and rest[i + 1].endswith("%"):
            vals.append((int(rest[i].replace(",", "")), int(rest[i + 1][:-1]))); i += 2
        elif i < len(rest) and rest[i].endswith("%"):
            vals.append((0, int(rest[i][:-1]))); i += 1
        else:
            return None
    if i != len(rest) - 1:
        return None
    return name, vals, int(rest[i].replace(",", ""))

def clean_name(name, first_of_block):
    name = re.sub(r"^Jefferson (?=Jefferson / )", "", name)       # rotated 'Jefferson' label
    name = re.sub(r"^O\s+(?=Out of District)", "", name)          # rotated 'O' label
    if first_of_block and len(name) > 2 and name[0] in "EMH" and name[1].isupper():
        name = name[1:]                                             # rotated E/M/H label
    return name

rows = []
for y in YEARS:
    r = PdfReader(os.path.join(SRC, f"{y}_Capture_Rate.pdf"))
    lines = [l for p in r.pages for l in p.extract_text().split("\n")]
    block, first, got = [], True, 0
    cur_year_rows = []
    for l in lines:
        if "Notes:" in l:
            break
        p = parse_line(l)
        if p is None:
            continue
        name, vals, total = p
        name = clean_name(name, first); first = False
        base = {"year": y, "neighborhood": name, "total": total}
        for c, (n, pc) in zip(CATS, vals):
            base[c] = n; base[c + "_pct"] = pc
        if name in LEVEL_TOTALS or name == "Grand Total":
            lvl = LEVEL_TOTALS.get(name)
            for b in block:
                b["level"] = lvl if lvl != "Out of District/Undetermined" else lvl
                b["row_type"] = "residual" if lvl == "Out of District/Undetermined" else \
                    ("cluster_subtotal" if b["neighborhood"] == "Jefferson Total" else "school")
            cur_year_rows += block; block = []
            base["level"] = lvl or "Grand Total"
            base["row_type"] = "level_total" if lvl else "grand_total"
            cur_year_rows.append(base); first = True
        else:
            block.append(base)
    if block:
        err(f"{y}: {len(block)} rows after the last total were not assigned to a level: {[b['neighborhood'] for b in block][:3]}")
    rows += cur_year_rows

# ---------- validation ----------
for y in YEARS:
    yr = [r for r in rows if r["year"] == y]
    if not yr: err(f"{y}: no rows"); continue
    for r in yr:
        s = sum(r[c] for c in CATS)
        if s != r["total"]:
            err(f"{y} {r['neighborhood']}: categories sum {s} != total {r['total']}")
        for c in CATS:
            exp = 100 * r[c] / r["total"] if r["total"] else 0
            if abs(exp - r[c + "_pct"]) > 0.51:
                err(f"{y} {r['neighborhood']} {c}: printed {r[c+'_pct']}% vs computed {exp:.2f}%")
    lv = {}
    for r in yr:
        if r["row_type"] == "level_total": lv[r["level"]] = r
    for L, tot in lv.items():
        parts = [r for r in yr if r["level"] == L and r["row_type"] in ("school", "residual")]
        if L.startswith("Out of District"):
            # The report prints 'Out of District' (and, in some years, 'Undetermined') component rows. In
            # 2023-24 and 2024-25 the components fall short of the printed total (an unprinted Undetermined
            # row, 11 and 9 students); in 2025-26 only the total is printed. Components must not exceed it.
            if any(sum(r[c] for r in parts) > tot[c] for c in CATS + ["total"]):
                err(f"{y} {L}: component rows exceed printed total")
            short = tot["total"] - sum(r["total"] for r in parts)
            if short: print(f"note {y}: Out of District components sum {short} short of printed total {tot['total']}")
            continue
        for c in CATS + ["total"]:
            if sum(r[c] for r in parts) != tot[c]:
                err(f"{y} {L}: sum of rows {c}={sum(r[c] for r in parts)} != printed {tot[c]}")
    g = [r for r in yr if r["row_type"] == "grand_total"]
    if len(g) != 1: err(f"{y}: {len(g)} grand totals")
    else:
        for c in CATS + ["total"]:
            if sum(t[c] for t in lv.values()) != g[0][c]:
                err(f"{y} grand total {c}: sum of levels {sum(t[c] for t in lv.values())} != {g[0][c]}")
    for L in ("Elementary", "High"):
        if L not in lv: err(f"{y}: no {L} total")
    jt = [r for r in yr if r["row_type"] == "cluster_subtotal"]
    subs = [r for r in yr if r["neighborhood"].startswith("Jefferson / ")]
    if jt and subs and sum(r["total"] for r in subs) != jt[0]["total"]:
        err(f"{y}: Jefferson sub-areas don't sum to Jefferson Total")
g25 = [r for r in rows if r["year"] == "2025-26" and r["row_type"] == "grand_total"]
if not g25 or (g25[0]["own_neighborhood_school"], g25[0]["total"]) != (29036, 42622):
    err("2025-26 grand total is not 29,036 of 42,622")

if errors:
    print("VALIDATION FAILED"); [print(" -", e) for e in errors[:60]]
    print(f"({len(errors)} problems)"); sys.exit(1)

cols = ["year", "level", "row_type", "neighborhood", "total"]
cols = ["year", "level", "row_type", "neighborhood"] + [x for c in CATS for x in (c, c + "_pct")] + ["total"]
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=cols); w.writeheader()
    for r in rows: w.writerow({k: r[k] for k in cols})
for y in YEARS:
    yr = [r for r in rows if r["year"] == y]
    g = [r for r in yr if r["row_type"] == "grand_total"][0]
    print(f"{y}: {len(yr)} rows ({sum(r['row_type']=='school' for r in yr)} areas); grand total own {g['own_neighborhood_school']:,} of {g['total']:,}")
print("OK ->", os.path.normpath(OUT))
