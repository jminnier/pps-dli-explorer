"""Parse the PSU Population Research Center (PRC) enrollment forecast reports for PPS into one CSV.

Source PDFs (data-raw/pps_reports/PSU_PRC_Forecast_<first>_to_<last>.pdf) come from
https://www.pps.net/departments/dataaccountability/data-and-accountability/data-strategy-and-insights/data-and-reporting
Each is a 40-page report (narrative, then appendix tables on PDF pages 33-40). The vintage is the
first forecast year ("2025-26" = report with actuals through fall 2024, forecasts from 2025-26;
"2026-27" = actuals through fall 2025). Only the appendix tables are parsed:

- Tables 5.2 / 5.3 / 5.4 (PDF pages 34-36): district-wide enrollment by grade K-12, plus grade groups
  K-2, 3-5, 6-8, 9-12 and TOTAL, for the medium / low / high scenarios, ~20 years each. Written as
  table = "district_by_grade", school = "District", scenario = middle / low / high.
- Table 5.5 (PDF pages 37-40): by school and program, by grade GROUP only (the school's span, e.g.
  K-5 or 6-8; no single-grade detail), medium scenario only, 13 years (3 historic + 10 forecast).
  Written as table = "school_program", school = the printed name without the type, school_type =
  ES / MS / HS / K8 / K12 / G28, program = Neighborhood / Spanish / Mandarin / ... / Total (the
  school total, printed for every school), grade = the printed span. Immersion IS forecast
  separately from neighborhood in this table. The group subtotal rows at the end (Elementary /
  Middle / High Schools, Other, TOTAL) are written as table = "school_group_subtotal".
- Skipped: Table 4.2 (district by grade, medium; duplicates 5.2) and all narrative/demographic
  tables (population, births, housing, historic enrollment by cluster of residence).

Layout quirks handled here:
- The text layer is clean: one table row per line, thousands commas, and the last N tokens are the
  N year columns (header gives the years). The label is "<Name> <Type> <Program> <Grades>"; the type
  token is one of ES MS HS K8 K12 G28, or "-" for the long-closed Bridger rows (Bridger - Neighborhood -).
- Program rows are not always in a fixed order: the Total row can sit before or between program rows
  (Rose City Park, Roseway Heights, McDaniel in the 2026-27 report); rows are keyed by program.
- Group subtotal labels run into the first number in the 2026-27 report ("Subtotal15,202",
  "Other (K-8, 2-8, and K-12)8,271").
- Hosford MS (2025-26 report) has Neighborhood/Mandarin rows of 0 from 2028-29 on while its Total
  row continues (program split dropped); the Total is trusted and the zeros are kept as printed.
- Zero rows are printed for new, pending or closed programs (note D) and kept as printed.
- A year column is "actual" when it is before the vintage year, otherwise "forecast".
- da Vinci MS is printed with grades "K-12" in the 2026-27 report (typo, kept as printed).

Validation (exits on failure): district grades sum to TOTAL and to the grade groups, groups sum to
TOTAL; a school's program rows sum to its Total row; school Totals sum to the group subtotals and
the subtotals to TOTAL (the closed Bridger rows, type "-", are in TOTAL but in no subtotal); TOTAL equals the medium-scenario district total of Table 5.2.
Then base-year actuals are cross-checked against data/enrollment_by_program_grade.csv (October 1
counts, by grade); mismatches are printed, not fatal.

Usage: python3 data-raw/parse_psu_forecast.py  ->  data/psu_forecast.csv
"""
import csv
import glob
import os
import re
import sys
from collections import defaultdict

from pypdf import PdfReader

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'pps_reports')
OUT = os.path.join(HERE, '..', 'data', 'psu_forecast.csv')
PROGRAM_GRADE = os.path.join(HERE, '..', 'data', 'enrollment_by_program_grade.csv')

FIELDS = ['forecast_vintage', 'table', 'school', 'school_type', 'program', 'grade', 'year',
          'enrollment', 'type', 'scenario']
SCENARIOS = {'5.2': 'middle', '5.3': 'low', '5.4': 'high'}
DISTRICT_ROWS = [str(g) for g in range(1, 13)] + ['K']
DISTRICT_GROUPS = {'K-2': ['K', '1', '2'], '3-5': ['3', '4', '5'], '6-8': ['6', '7', '8'],
                   '9-12': ['9', '10', '11', '12']}
GROUP_ROWS = {'Elementary Schools Subtotal': 'ES', 'Middle Schools Subtotal': 'MS',
              'High Schools Subtotal': 'HS', 'Other (K-8, 2-8, and K-12)': None, 'TOTAL': 'ALL'}
GROUP_ALIASES = {'Elementary and K-8 Subtotal': 'Elementary Schools Subtotal',
                'Other (K-12 and 1-8)': 'Other (K-8, 2-8, and K-12)'}  # 2024-25 edition
ROUND_TOL = 3  # rounding slack for sums of rounded forecast cells
NUM = r'\d[\d,]*'
# The 2024-25 edition prints ACCESS with no type token ("ACCESS 2-8 Total 2-8"); it is read as G28.
SCHOOL_RE = re.compile(r'^(?P<name>.+?)(?: (?P<stype>ES|MS|HS|K8|K12|G28|-))? (?P<prog>[A-Za-z]+) (?P<span>\S+)$')
# Schools whose program rows are printed as 0 (not split) in later years while the Total row continues:
# Hosford 2025-26 report, 2028-29 onward (Neighborhood/Mandarin rows are 0 but Total is 404, 352, ...).
UNSPLIT = {'Hosford'}
LANGUAGES = ['Spanish', 'Mandarin', 'Japanese', 'Russian', 'Vietnamese']
# Names in this report that differ from enrollment_by_program_grade.csv (cross-check only).
ALIASES = {'Benson Polytechnic': 'Benson', 'Ida B Wells-Barnett': 'Ida B. Wells-Barnett', 'MLC': 'Metro. Learning Center',
           'Bridger Creative Science': 'Bridger Creative Science'}
SPAN_GRADES = {'K-5': ['K', '1', '2', '3', '4', '5'], '6-8': ['6', '7', '8'],
               '9-12': ['9', '10', '11', '12'], 'K-8': ['K'] + [str(g) for g in range(1, 9)]}


def fail(msg):
    sys.exit(f'parse_psu_forecast: {msg}')


def to_int(s):
    return int(s.replace(',', ''))


def find_tables(reader, path):
    """{table id: [page text lines]} for tables 5.2-5.5 (5.5 spans several pages)."""
    tables = defaultdict(list)
    for page in reader.pages[32:]:
        lines = (page.extract_text() or '').split('\n')
        for l in lines[:4]:
            m = re.match(r'Table (5\.[2-5])[: ]', l)
            if m:
                tables[m.group(1)].append(lines)
                break
    for t in ['5.2', '5.3', '5.4', '5.5']:
        if not tables[t]:
            fail(f'{path}: Table {t} not found')
    return tables


def year_header(lines, first_col):
    """Year columns from the line starting with `first_col` (e.g. 'Grade' or 'Name Type ...')."""
    for l in lines:
        if l.startswith(first_col):
            years = re.findall(r'\d{4}-\d{2}', l)
            if years:
                return years
    fail(f'no year header starting with {first_col!r}')


def split_numbers(line, n):
    """(label, n ints) from a row whose last n tokens are numbers; None if not such a row."""
    line = re.sub(r'(Subtotal|K-12\))(?=\d)', r'\1 ', line.strip())  # "Subtotal15,202" in 2026-27
    toks = line.split()
    if len(toks) <= n or not all(re.fullmatch(r'\d[\d,]*', t) for t in toks[-n:]):
        return None
    return ' '.join(toks[:-n]), [to_int(t) for t in toks[-n:]]


def parse_district(lines, vintage, scenario, table_id):
    years = year_header(lines, 'Grade')
    rows, seen_total = {}, 0
    for l in lines:
        r = split_numbers(l, len(years))
        if not r:
            continue
        label, nums = r
        if label == 'TOTAL':
            label = 'Total' if seen_total == 0 else 'Total (groups)'
            seen_total += 1
        if label in rows:
            fail(f'{vintage} Table {table_id}: duplicate row {label}')
        rows[label] = nums
    need = set(DISTRICT_ROWS) | set(DISTRICT_GROUPS) | {'Total', 'Total (groups)'}
    if set(rows) != need:
        fail(f'{vintage} Table {table_id}: rows {sorted(set(rows) ^ need)} missing/unexpected')
    for i, y in enumerate(years):
        col = {k: v[i] for k, v in rows.items()}
        # forecasts are rounded cell by cell, so sums may be off by a few; actuals must be exact
        tol = 0 if int(y[:4]) < int(vintage[:4]) else ROUND_TOL
        checks = [(f'grades vs Total', sum(col[g] for g in DISTRICT_ROWS), col['Total']),
                  ('groups vs Total', sum(col[g] for g in DISTRICT_GROUPS), col['Total'])]
        checks += [(grp, sum(col[m] for m in members), col[grp]) for grp, members in DISTRICT_GROUPS.items()]
        for what, got, want in checks:
            if abs(got - want) > tol:
                fail(f'{vintage} {scenario} {y}: {what}: sum {got}, printed {want}')
        if col['Total (groups)'] != col['Total']:
            fail(f'{vintage} {scenario} {y}: the two TOTAL rows disagree')
    del rows['Total (groups)']
    return years, rows


def parse_schools(page_lines, vintage):
    """(years, school rows, group rows) from the pages of Table 5.5."""
    years = year_header(page_lines[0], 'Name Type')
    n = len(years)
    schools, groups = [], {}
    for lines in page_lines:
        if year_header(lines, 'Name Type') != years:
            fail(f'{vintage}: Table 5.5 year header changes between pages')
        for l in lines:
            if l.startswith(('Sources:', 'Notes', 'Note')):
                break
            r = split_numbers(l, n)
            if not r:
                continue
            label, nums = r
            label = re.sub(r'\s+', ' ', label)
            label = GROUP_ALIASES.get(label, label)
            if label in GROUP_ROWS or label.endswith('Subtotal'):
                if label not in GROUP_ROWS:
                    fail(f'{vintage}: unknown group row {label!r}')
                groups[label] = nums
                continue
            m = SCHOOL_RE.match(label)
            if not m:
                fail(f'{vintage}: cannot parse school row {l!r}')
            schools.append((m.group('name'), m.group('stype') or 'G28', m.group('prog'), m.group('span'), nums))
    if set(groups) != set(GROUP_ROWS):
        fail(f'{vintage}: group rows found {sorted(groups)}')
    return years, schools, groups


def validate_schools(vintage, years, schools, groups, medium_total):
    by_school = defaultdict(dict)
    for name, stype, prog, span, nums in schools:
        key = (name, stype)
        if prog in by_school[key]:
            fail(f'{vintage}: duplicate row {name} {stype} {prog}')
        by_school[key][prog] = (span, nums)
    sums = defaultdict(lambda: [0] * len(years))
    for (name, stype), progs in by_school.items():
        if 'Total' not in progs:
            fail(f'{vintage}: {name} has no Total row')
        spans = {s for s, _ in progs.values()}
        if len(spans) != 1:
            fail(f'{vintage}: {name} has several grade spans {spans}')
        parts = [v for p, (s, v) in progs.items() if p != 'Total']
        if parts:
            got = [sum(c) for c in zip(*parts)]
            if name in UNSPLIT:  # program rows print 0 once the program split is dropped
                got = [g if g else t for g, t in zip(got, progs['Total'][1])]
            if got != progs['Total'][1]:
                fail(f'{vintage}: {name} programs sum to {got}, Total row {progs["Total"][1]}')
        grp = stype if stype in ('ES', 'MS', 'HS', '-') else None  # '-' = closed Bridger, in no subtotal
        if vintage == '2024-25' and stype == 'K8':
            grp = 'ES'  # the 2024-25 edition's 'Elementary and K-8 Subtotal' includes the K-8 schools
        if vintage == '2024-25' and stype == 'G28':
            grp = '-'  # ACCESS (2-8) is in TOTAL but in no printed subtotal in the 2024-25 edition
        sums[grp] = [a + b for a, b in zip(sums[grp], progs['Total'][1])]
    for label, grp in GROUP_ROWS.items():
        if grp == 'ALL':
            continue
        if sums[grp] != groups[label]:
            fail(f'{vintage}: school Totals for {label} sum to {sums[grp]}, printed {groups[label]}')
    all_sum = [sum(x) for x in zip(*sums.values())]
    if all_sum != groups['TOTAL']:
        fail(f'{vintage}: schools sum to {all_sum}, TOTAL {groups["TOTAL"]}')
    for y, t in zip(years, groups['TOTAL']):
        if y in medium_total and medium_total[y] != t:
            fail(f'{vintage} {y}: Table 5.5 TOTAL {t} != Table 5.2 total {medium_total[y]}')


# Whole-school immersion schools that Table 5.5 prints with a Total row only (2025-26 note B:
# Richmond). Every Richmond student is in Japanese immersion (dli_track_profiles.csv), so a
# Japanese row equal to the Total is added, matching Lent and Rigler, which print both rows.
WHOLE_SCHOOL = {'Richmond': 'Japanese'}


def parse_file(path):
    vintage = re.search(r'Forecast_(\d{4}-\d{2})_(?:to|edition)', os.path.basename(path)).group(1)
    v0 = int(vintage[:4])
    reader = PdfReader(path)
    if len(reader.pages) != 40:
        fail(f'{path}: expected 40 pages, got {len(reader.pages)}')
    tables = find_tables(reader, path)
    out = []

    def add(table, school, stype, prog, grade, year, val, scen):
        out.append({'forecast_vintage': vintage, 'table': table, 'school': school, 'school_type': stype,
                    'program': prog, 'grade': grade, 'year': year, 'enrollment': val,
                    'type': 'actual' if int(year[:4]) < v0 else 'forecast', 'scenario': scen})

    medium_total = {}
    for tid, scen in SCENARIOS.items():
        if len(tables[tid]) != 1:
            fail(f'{vintage}: Table {tid} on {len(tables[tid])} pages')
        years, rows = parse_district(tables[tid][0], vintage, scen, tid)
        if tid == '5.2':
            medium_total = dict(zip(years, rows['Total']))
        for grade, vals in rows.items():
            for y, v in zip(years, vals):
                add('district_by_grade', 'District', '', '', grade, y, v, scen)
        # historic years must be identical across scenarios (checked below via medium_total)
        for y, v in zip(years, rows['Total']):
            if int(y[:4]) < v0 and medium_total.get(y) != v:
                fail(f'{vintage}: {scen} historic total {y} differs from medium')
    years, schools, groups = parse_schools(tables['5.5'], vintage)
    validate_schools(vintage, years, schools, groups, medium_total)
    for name, stype, prog, span, nums in schools:
        for y, v in zip(years, nums):
            add('school_program', name, stype, prog, span, y, v, 'middle')
        lang = WHOLE_SCHOOL.get(name)
        if prog == 'Total' and lang and not any(n == name and p == lang for n, _, p, _, _ in schools):
            for y, v in zip(years, nums):
                add('school_program', name, stype, lang, span, y, v, 'middle')
    for label, nums in groups.items():
        for y, v in zip(years, nums):
            add('school_group_subtotal', label, '', '', '', y, v, 'middle')
    return out


def load_actuals():
    """{(year, school, program, grade): enrollment} from enrollment_by_program_grade.csv."""
    rows = []
    with open(PROGRAM_GRADE, newline='') as f:
        for r in csv.DictReader(f):
            rows.append(r)
    return rows


def cross_check(all_rows):
    """Compare PSU actual school/program counts with the October 1 counts by program and grade."""
    pps = load_actuals()
    idx = defaultdict(int)
    schools_pps = set()
    for r in pps:
        s = r['school']
        schools_pps.add(s)
        idx[(r['year'], s, r['language'] or ('NB' if r['program'] in ('Neighborhood Program', 'Whole School') else 'OTHER'), r['grade'])] += int(r['enrollment'])
        idx[(r['year'], s, 'ALL', r['grade'])] += int(r['enrollment'])
    n_ok = n_bad = n_skip = 0
    bad, missing = [], set()
    for r in all_rows:
        if r['table'] != 'school_program' or r['type'] != 'actual' or r['year'] not in ('2024-25', '2025-26'):
            continue
        span = SPAN_GRADES.get(r['grade'])
        if not span:
            n_skip += 1
            continue
        school = ALIASES.get(r['school'], r['school'])
        if school not in schools_pps:
            if r['enrollment']:
                missing.add(r['school'])
            continue
        prog = r['program']
        key = 'ALL' if prog == 'Total' else prog if prog in LANGUAGES else 'NB' if prog == 'Neighborhood' else None
        if key is None:
            n_skip += 1
            continue
        got = sum(idx.get((r['year'], school, key, g), 0) for g in span)
        if got == r['enrollment']:
            n_ok += 1
        else:
            n_bad += 1
            bad.append((r['forecast_vintage'], r['year'], r['school'], prog, r['enrollment'], got))
    return n_ok, n_bad, n_skip, sorted(set(bad)), sorted(missing)


def main():
    # *_edition.pdf files (2022-23 to 2024-25 editions) are handled by extract_psu_premove.py
    paths = sorted(glob.glob(os.path.join(SRC, 'PSU_PRC_Forecast_*_to_*.pdf')))
    if not paths:
        fail(f'no PSU_PRC_Forecast_*_to_*.pdf in {SRC}')
    all_rows = []
    for p in paths:
        all_rows.extend(parse_file(p))
    with open(OUT, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(all_rows)
    print(f'wrote {len(all_rows)} rows to {os.path.normpath(OUT)}')
    for v in sorted({r['forecast_vintage'] for r in all_rows}):
        rows = [r for r in all_rows if r['forecast_vintage'] == v]
        sp = [r for r in rows if r['table'] == 'school_program']
        d = [r for r in rows if r['table'] == 'district_by_grade']
        print(f'{v}: {len(rows)} rows; district_by_grade {len(d)} rows, years '
              f'{min(r["year"] for r in d)}..{max(r["year"] for r in d)}; school_program {len(sp)} rows, '
              f'{len({(r["school"], r["school_type"]) for r in sp})} schools, years '
              f'{min(r["year"] for r in sp)}..{max(r["year"] for r in sp)}')
    n_ok, n_bad, n_skip, bad, missing = cross_check(all_rows)
    print(f'cross-check vs enrollment_by_program_grade.csv: {n_ok} match, {n_bad} mismatch, {n_skip} not comparable')
    for b in bad:
        print('  MISMATCH vintage %s %s %s / %s: PSU %s vs PPS %s' % b)
    if missing:
        print('  schools with enrollment not found in program-grade file:', ', '.join(missing))


if __name__ == '__main__':
    main()
