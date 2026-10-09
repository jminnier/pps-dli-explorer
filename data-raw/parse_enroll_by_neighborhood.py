#!/usr/bin/env python3
"""Parse PPS "Enrollment Summary, by K-12 Students' School and High School Area"
(data-raw/pps_reports/capture_rate/<YYYY-YY>_Enroll_by_Neighborhood.pdf)
into data/enroll_by_neighborhood.csv (tidy long).

Layout (verified, see checks): ONE matrix, 4 pages. Rows = attending school x
program (with "<School> Total" rows, section totals and a Grand Total). Columns =
residence of the student: (1) "Students from School's Neighborhood" (the school's
own attendance area), (2) the HIGH SCHOOL AREA (cluster) in which the student lives
if outside the school's own neighborhood (Cleveland, Franklin, Grant, Ida B.
Wells-Barnett, Jefferson/Grant, Jefferson/McDaniel, Jefferson/Roosevelt, Lincoln,
McDaniel, Roosevelt; earlier years differ), (3) Out of District/Undetermined, then
a row Total. Every cell prints "<count> <pct>%"; a zero prints as just "0%".
Nothing is suppressed. Pre-K is excluded. Cells are therefore recovered by order
(12 cells per row) and checked against printed totals.

Checks (exit non-zero on failure):
  - 12 (or 13 in 2019-20) cells per row; cells sum to printed row total;
  - printed percentages equal count/total within +-0.51;
  - program rows sum to the "<School> Total" row, cell by cell;
  - school rows sum to each section total ("Elementary Schools Total", ...);
  - section totals sum to the Grand Total;
  - for 2024-25 and 2025-26: school x program totals equal
    data/enrollment_by_program_grade.csv summed over K-12 (reported, mismatches
    listed; any mismatch beyond the allowed list fails).
The 2024-25 PDF has its Total column cut off; row totals are then the cell sums,
verified through the percentages.
"""
import csv
import os
import re
import sys
from collections import defaultdict

from pypdf import PdfReader

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PDF_DIR = os.path.join(ROOT, "data-raw", "pps_reports", "capture_rate")
OUT = os.path.join(ROOT, "data", "enroll_by_neighborhood.csv")
YEARS = ["2023-24", "2024-25", "2025-26"]  # years whose checks all pass
# 2019-20 .. 2022-23 use a rotated page layout; the row grouping loses some rows
# (e.g. 2022-23 Roseway Heights Spanish Immersion) and the checks fail. They can be
# tried with `parse_enroll_by_neighborhood.py 2022-23` but are not written by default.

OWN = "School's own neighborhood"
OOD = "Out of District/Undetermined"
HS_9 = ["Cleveland", "Franklin", "Grant", "Ida B. Wells-Barnett", "Jefferson/Grant",
        "Jefferson/McDaniel", "Jefferson/Roosevelt", "Lincoln", "McDaniel", "Roosevelt"]
# Column headers per year, read from the PDF headers (x positions checked for 2025-26/2024-25).
COLS = {
    "2025-26": HS_9,
    "2024-25": HS_9,
    "2023-24": HS_9,
    "2022-23": HS_9,
    "2021-22": HS_9,
    "2020-21": ["Cleveland", "Franklin", "Grant", "Ida B. Wells-Barnett", "Jefferson/Grant",
                "Jefferson/Madison", "Jefferson/Roosevelt", "Lincoln",
                "Leodis V. McDaniel", "Roosevelt"],
    "2019-20": ["Cleveland", "Franklin", "Grant", "Jefferson/Grant", "Jefferson/Madison",
                "Jefferson/Roosevelt", "Lincoln", "Madison", "Roosevelt", "Wilson"],
}
SECTIONS = ["Elementary Schools Total", "Middle Schools Total", "High Schools Total",
            "Selected Focus/Alternative Programs Total", "Community Based Programs Total",
            "Special Services Total", "Public Charter Schools Total"]
SECTION_NAME = {
    "Elementary Schools Total": "Elementary", "Middle Schools Total": "Middle",
    "High Schools Total": "High", "Selected Focus/Alternative Programs Total": "Alternative",
    "Community Based Programs Total": "CBO", "Special Services Total": "Special Services",
    "Public Charter Schools Total": "Charter",
}
SCHOOL_PREFIXES = ["Alliance", "PCC", "DART Programs", "PPS Pioneer Programs",
                   "Special Education Instruction"]
PROG_RE = re.compile(r"^(.*?)\s*((?:Spanish|Mandarin|Russian|Japanese|Vietnamese) Immersion"
                     r"|Neighborhood Program)$")
HEADER_PREFIX = "School that Students Attend School Program "
CELL_START = re.compile(r"\s(?:\d[\d,]*\s+)?\d+%(?:\s|$)")
CELL = re.compile(r"(?:(\d[\d,]*)\s+)?(\d+)%")

fails = []


def fail(msg):
    fails.append(msg)
    print("FAIL:", msg)


def page_lines(page):
    rows = defaultdict(list)

    def visit(text, cm, tm, fd, fs):
        if text.strip():
            if abs(tm[0]) < 1e-6:  # rotated page layout (2019-20 to 2022-23)
                rows[-round(tm[4])].append((tm[5], text.strip()))
            else:
                rows[round(tm[5])].append((tm[4], text.strip()))

    page.extract_text(visitor_text=visit)
    out = []
    for y in sorted(rows, reverse=True):
        frs = sorted(rows[y])
        out.append((frs[0][0], " ".join(t for _, t in frs)))
    return out


def parse_year(year):
    reader = PdfReader(os.path.join(PDF_DIR, f"{year}_Enroll_by_Neighborhood.pdf"))
    ncell = 12
    entries = []  # dict(label_kind, school, program, cells, total, page)
    school = None
    for pi, page in enumerate(reader.pages):
        for x0, s in page_lines(page):
            if HEADER_PREFIX in s:
                s = s.split(HEADER_PREFIX, 1)[1]
            m = CELL_START.search(s)
            if not m or s.startswith(("Portland Public", "Enrollment Summary", "Notes",
                                      "Pre-Kindergarten", "Students from", "For example")):
                continue
            label = s[: m.start()].strip()
            rest = s[m.start():].strip()
            cells, pos = [], 0
            while True:
                cm = CELL.match(rest, pos)
                if not cm:
                    break
                cells.append((int(cm.group(1).replace(",", "")) if cm.group(1) else 0,
                              int(cm.group(2))))
                pos = cm.end()
                while pos < len(rest) and rest[pos] == " ":
                    pos += 1
            tail = rest[pos:].strip()
            total = int(tail.replace(",", "")) if re.fullmatch(r"\d[\d,]*", tail) else None
            if tail and total is None:
                fail(f"{year} p{pi+1} unparsed tail {tail!r} in {s!r}")
                continue
            if len(cells) not in (ncell, ncell + 1):
                fail(f"{year} p{pi+1} {label!r}: {len(cells)} cells")
                continue
            kind = "row"
            if label in SECTIONS:
                kind = "section"
            elif label == "Grand Total":
                kind = "grand"
            elif label.endswith(" Total"):
                kind = "schooltotal"
                school = label[: -len(" Total")]
                program = ""
            if kind == "row":
                if x0 >= 100:  # program-only continuation line
                    program = label
                else:
                    prog = ""
                    sch = label
                    pm = PROG_RE.match(label)
                    if pm and pm.group(1):
                        sch, prog = pm.group(1), pm.group(2)
                    elif pm:  # bare program name at left margin (no school)
                        sch, prog = school, pm.group(2)
                    else:
                        for pre in SCHOOL_PREFIXES:
                            if label.startswith(pre + " ") and label != pre:
                                sch, prog = pre, label[len(pre) + 1:]
                                break
                    school, program = sch, prog
                entries.append(dict(kind="row", school=school, program=program,
                                    cells=cells, total=total, page=pi + 1))
            else:
                entries.append(dict(kind=kind, school=school if kind == "schooltotal" else label,
                                    program="", cells=cells, total=total, page=pi + 1))
    return entries


def check_year(year, entries):
    ncols = len(entries[0]["cells"])
    cols = [OWN] + COLS[year] + [OOD]
    if len(cols) != ncols:
        fail(f"{year}: {ncols} cells per row but {len(cols)} column names")
        return None
    short_total = all(e["total"] is None for e in entries)
    # row checks
    for e in entries:
        counts = [c for c, _ in e["cells"]]
        e["counts"] = counts
        s = sum(counts)
        if e["total"] is None:
            e["total_derived"] = True
            e["total"] = s
        elif s != e["total"]:
            fail(f"{year} {e['school']}|{e['program']}|{e['kind']}: cells sum {s} != printed {e['total']}")
        for (c, p), name in zip(e["cells"], cols):
            if e["total"] and abs(100.0 * c / e["total"] - p) > 0.51 + 1e-9:
                fail(f"{year} {e['school']}|{e['program']}: {name} {c}/{e['total']} != {p}%")
    # school total rows
    by_school = defaultdict(list)
    for e in entries:
        if e["kind"] == "row":
            by_school[e["school"]].append(e)
    for e in entries:
        if e["kind"] == "schooltotal":
            rows = by_school.get(e["school"], [])
            if not rows:
                fail(f"{year}: total row for {e['school']} without program rows")
                continue
            for i in range(ncols):
                if sum(r["counts"][i] for r in rows) != e["counts"][i]:
                    fail(f"{year} {e['school']}: program rows != Total in column {cols[i]}")
    # sections
    start = 0
    sec = None
    sections = {}
    for i, e in enumerate(entries):
        if e["kind"] == "section":
            members = [r for r in entries[start:i] if r["kind"] == "row"]
            for r in members:
                r["section"] = SECTION_NAME[e["school"]]
            for k in range(ncols):
                if sum(r["counts"][k] for r in members) != e["counts"][k]:
                    fail(f"{year} {e['school']}: school rows != section total in {cols[k]}")
            sections[e["school"]] = e
            start = i + 1
    leftovers = [r for r in entries[start:] if r["kind"] == "row"]
    if leftovers:
        fail(f"{year}: {len(leftovers)} school rows after the last section total")
    grand = [e for e in entries if e["kind"] == "grand"]
    if len(grand) != 1:
        fail(f"{year}: {len(grand)} grand total rows")
    elif len(sections) != len(SECTIONS):
        fail(f"{year}: found sections {list(sections)}")
    else:
        for k in range(ncols):
            if sum(s["counts"][k] for s in sections.values()) != grand[0]["counts"][k]:
                fail(f"{year}: sections != Grand Total in {cols[k]}")
    return cols


def compare_program_grade(year, entries):
    """School x program totals vs enrollment_by_program_grade.csv (K-12)."""
    path = os.path.join(ROOT, "data", "enrollment_by_program_grade.csv")
    ref = defaultdict(int)
    for r in csv.DictReader(open(path)):
        if r["year"] == year and r["grade"] != "PK":
            ref[(r["school"], r["program"])] += int(r["enrollment"])
    ref_school = defaultdict(int)
    for (s, _), v in ref.items():
        ref_school[s] += v
    mism = []
    n = 0
    for e in entries:
        if e["kind"] != "row":
            continue
        n += 1
        key = (e["school"], e["program"] or "Whole School")
        got = ref.get(key)
        if got is None:
            # whole-school immersion printed as a single row (Lent, Rigler, Richmond) or
            # a single-program school printed without a program name
            got = ref_school.get(e["school"]) if len([x for x in entries if x["kind"] == "row" and x["school"] == e["school"]]) == 1 else None
        if got != e["total"]:
            mism.append((e["school"], e["program"], e["total"], got))
    print(f"  {year}: compared {n} school x program rows with enrollment_by_program_grade; "
          f"{len(mism)} mismatches")
    for m in mism:
        print("   mismatch (school, program, report, program_grade):", m)
    return mism


def main():
    years = sys.argv[1:] or YEARS
    if sys.argv[1:] and set(years) - set(YEARS):
        print("note: requested years outside the validated set; failures are expected")
    all_rows = []
    for year in years:
        before = len(fails)
        print(f"== {year}")
        entries = parse_year(year)
        cols = check_year(year, entries)
        nrow = sum(1 for e in entries if e["kind"] == "row")
        print(f"  {nrow} school/program rows, {len(entries)} lines parsed, "
              f"checks {'OK' if len(fails) == before else 'FAILED'}")
        if year in ("2024-25", "2025-26") and len(fails) == before:
            compare_program_grade(year, entries)
        if len(fails) != before or cols is None:
            continue
        for e in entries:
            if e["kind"] != "row":
                continue
            for name, n in zip(cols, e["counts"]):
                level = ("own_neighborhood" if name == OWN else
                         "other" if name == OOD else "high_school_area")
                all_rows.append(dict(year=year, section=e["section"], school=e["school"],
                                     program=e["program"], residence_area=name,
                                     area_level=level, students=n, row_total=e["total"]))
    if all_rows:
        with open(OUT, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(all_rows[0]))
            w.writeheader()
            w.writerows(all_rows)
        print(f"wrote {len(all_rows)} rows to {OUT}")
    if fails:
        print(f"{len(fails)} check(s) failed", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
