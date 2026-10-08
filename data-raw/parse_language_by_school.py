"""Parse PPS "Enrollment by Language and School" PDFs into one long CSV.

Source PDFs (data-raw/pps_reports/*_Enrollment_by_Language_and_School_Map.pdf) come from
https://www.pps.net/departments/dataaccountability/data-and-accountability/data-strategy-and-insights/data-and-reporting

Layout: 6 landscape pages (792 x 612). Pages 1-5 hold the table (one row per school, or per
program plus a "<School> Total" row for multi-program schools); page 6 holds only footnotes
(October 1st SIS basis; the Chinese column includes Cantonese/Mandarin/Other). There is no
district total row and no map in the text layer.

Cells with no students are omitted, and numbers are right-aligned, so columns are assigned by
x position (from the text-fragment matrix, which is clean: no letter-spacing as in layout mode)
using boundaries midway between each language's "%" header and the next language's "#" header.
Rows are grouped by y. Pages 3-5 also carry roll-up rows (Elementary Schools Total, Middle School
Total, High School Total, Alt. Programs Total, CBOs, Special Services, Charter Schools, District Total) that
are used only for validation: all school rows must sum to the District Total. The name column (x ~ 20) is blank for 2nd+ programs of a school, and the
program column (x ~ 156) is blank for single-program schools (stored as "All").

Every row is validated: language counts sum to Enrollment, each count matches its printed %
(whole-number rounding), and program rows sum to the "<School> Total" row. Total rows are
used only for validation. program_language is set for immersion programs.

Usage: python3 data-raw/parse_language_by_school.py  ->  data/enrollment_by_language.csv
Also cross-checks immersion enrollment against data/dli_track_profiles.csv.
"""
import csv
import glob
import os
import re
import sys
from collections import defaultdict

from pypdf import PdfReader

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'data', 'enrollment_by_language.csv')
PROFILES = os.path.join(HERE, '..', 'data', 'dli_track_profiles.csv')

LANGS = ['English', 'Spanish', 'Vietnamese', 'Chinese', 'Russian', 'Somali/Maay-Maay', 'Japanese', 'Other']
TOL = 0.51
NAME_X, PROGRAM_X, ENROLL_X = 20, 156, 290
IMMERSION = {'Spanish': 'Spanish', 'Mandarin': 'Mandarin', 'Chinese': 'Mandarin',
             'Japanese': 'Japanese', 'Russian': 'Russian', 'Vietnamese': 'Vietnamese'}
# Names differ between the two reports in places; map to the track-profiles spelling.
ALIASES = {}
# Whole-school immersion schools are listed as a single row with a blank program, so the
# immersion language comes from the track-profiles file (all enrollment is immersion there).
WHOLE_SCHOOL = {'Lent': 'Spanish', 'Rigler': 'Spanish', 'Richmond': 'Japanese'}
ROLLUPS = ['Elementary Schools Total', 'Middle School Total', 'High School Total',
           'Alt. Programs Total', 'CBOs Total', 'Special Services Total',
           'Public Charter Schools Total', 'District Total']


def fragments(page):
    out = []
    page.extract_text(visitor_text=lambda t, cm, tm, fd, fs: out.append((round(tm[5]), tm[4], t.strip()))
                      if t.strip() else None)
    return out


def column_bounds(frags, year):
    """Boundaries between the 8 language columns, from the '#' / '%' header row."""
    hdr = [f for f in frags if f[2] in ('#', '%') and f[1] > 330]
    ys = {y for y, _, _ in hdr}
    if len(ys) != 1:
        sys.exit(f'{year}: could not find language header row ({ys})')
    xs = sorted(x for _, x, _ in hdr)
    if len(xs) != 16:
        sys.exit(f'{year}: expected 16 header cells, got {len(xs)}')
    # xs alternate #, %, #, %...; boundary between column k and k+1 = midpoint(% of k, # of k+1)
    return ys.pop(), [(xs[2 * k + 1] + xs[2 * k + 2]) / 2 for k in range(7)]


def parse_page(frags, year):
    hy, bounds = column_bounds(frags, year)
    rows = defaultdict(list)
    for y, x, t in frags:
        if y < hy:
            rows[y].append((x, t))
    out = []
    for y in sorted(rows, reverse=True):
        cells = sorted(rows[y])
        name = ' '.join(t for x, t in cells if x < PROGRAM_X - 5)
        program = ' '.join(t for x, t in cells if PROGRAM_X - 5 <= x < ENROLL_X)
        nums = [(x, t) for x, t in cells if x >= ENROLL_X]
        if not nums:
            # A long program name wraps onto the next line (Rosemary Anderson H.S. - New / Columbia).
            if not out or name or not program:
                sys.exit(f'{year}: row without numbers: {cells}')
            out[-1]['program'] += ' ' + program
            continue
        enroll = int(nums[0][1].replace(',', ''))
        counts, pcts = [0] * 8, [None] * 8
        for x, t in nums[1:]:
            col = sum(x > b for b in bounds)
            if t.endswith('%'):
                pcts[col] = int(t[:-1])
            else:
                if counts[col]:
                    sys.exit(f'{year} {name}: duplicate count in {LANGS[col]}')
                counts[col] = int(t.replace(',', ''))
        out.append({'name': name, 'program': program, 'enroll': enroll, 'counts': counts, 'pcts': pcts})
    return out


def validate(year, rows):
    """Fill in blank name cells, check each row, and check program rows against Totals."""
    rollups = {r['name']: r for r in rows if r['name'] in ROLLUPS}
    rows = [r for r in rows if r['name'] not in ROLLUPS]
    if set(rollups) != set(ROLLUPS):
        sys.exit(f'{year}: roll-up rows found: {sorted(rollups)}')
    # (The Alt. Programs / CBOs / Special Services roll-ups overlap, so only the district is checked.)
    school = None
    for r in rows:
        if r['name']:
            school = re.sub(r' Total$', '', r['name']) if r['name'].endswith(' Total') else r['name']
        r['school'] = school
        r['is_total'] = r['name'].endswith(' Total')
        where = f"{year} {school} / {r['program'] or 'All'}"
        if sum(r['counts']) != r['enroll']:
            sys.exit(f"{where}: language counts {r['counts']} sum to {sum(r['counts'])}, enrollment {r['enroll']}")
        for lang, c, p in zip(LANGS, r['counts'], r['pcts']):
            if c and p is None or not c and p not in (None, 0):
                sys.exit(f'{where}: {lang} count {c} vs pct {p}')
            if c and abs(100 * c / r['enroll'] - p) > TOL:
                sys.exit(f"{where}: {lang} {c}/{r['enroll']} != {p}%")
    by_school = defaultdict(list)
    for r in rows:
        by_school[r['school']].append(r)
    for s, rs in by_school.items():
        progs = [r for r in rs if not r['is_total']]
        totals = [r for r in rs if r['is_total']]
        if len(progs) > 1 and len(totals) != 1 or len(totals) > 1:
            sys.exit(f'{year} {s}: {len(progs)} program rows but {len(totals)} total rows')
        if totals:
            t = totals[0]
            if sum(p['enroll'] for p in progs) != t['enroll'] or \
                    [sum(p['counts'][i] for p in progs) for i in range(8)] != t['counts']:
                sys.exit(f'{year} {s}: program rows do not sum to the Total row')
    schools = [r for r in rows if not r['is_total']]
    for i, label in enumerate(['enroll'] + LANGS):
        get = (lambda r: r['enroll']) if i == 0 else (lambda r, j=i - 1: r['counts'][j])
        dist = get(rollups['District Total'])
        if sum(get(r) for r in schools) != dist:
            sys.exit(f'{year}: {label} does not sum to District Total ({sum(get(r) for r in schools)} vs {dist})')
    return schools


def program_language(school, program):
    if not program:
        return WHOLE_SCHOOL.get(school, '')
    m = re.match(r'(\w+) Immersion', program)
    return IMMERSION.get(m.group(1), '') if m else ''


def parse_file(path):
    year = re.match(r'(\d{4}-\d{2})', os.path.basename(path)).group(1)
    rows = []
    for page in PdfReader(path).pages:
        frags = fragments(page)
        if any(t == 'School Program' for _, _, t in frags):
            rows += parse_page(frags, year)
    return year, validate(year, rows)


def cross_check(rows):
    if not os.path.exists(PROFILES):
        return
    prof = {(r['year'], r['school']): r for r in csv.DictReader(open(PROFILES, encoding='utf-8'))}
    cols = {'Spanish': 'imm_spanish', 'Mandarin': 'imm_mandarin', 'Japanese': 'imm_japanese',
            'Russian': 'imm_russian', 'Vietnamese': 'imm_vietnamese'}
    seen, bad = set(), 0
    mine = defaultdict(int)
    for r in rows:
        if r['program_language']:
            mine[(r['year'], ALIASES.get(r['school'], r['school']), r['program_language'])] += r['enroll']
    for (y, s, lang), n in sorted(mine.items()):
        if y not in ('2024-25', '2025-26'):
            continue
        p = prof.get((y, s))
        if not p:
            print(f'cross-check: {y} {s} {lang} ({n}) not in track profiles'); bad += 1; continue
        seen.add((y, s))
        if int(p[cols[lang]] or 0) != n:
            print(f'cross-check MISMATCH {y} {s} {lang}: report {n} vs profiles {p[cols[lang]]}'); bad += 1
    for (y, s), p in prof.items():
        if y in ('2024-25', '2025-26') and (y, s) not in seen:
            print(f'cross-check: {y} {s} in track profiles (immersion {p["immersion_total"]}) but no immersion row here'); bad += 1
    print(f'cross-check: {len(seen)} school-years compared, {bad} problems')


def main():
    files = sorted(glob.glob(os.path.join(HERE, 'pps_reports', '*_Enrollment_by_Language_and_School_Map.pdf')))
    out = []
    for f in files:
        year, rows = parse_file(f)
        for r in rows:
            for lang, c in zip(LANGS, r['counts']):
                out.append({'year': year, 'school': r['school'], 'program': r['program'] or 'All',
                            'language': lang, 'students': c,
                            'program_language': program_language(r['school'], r['program']), 'enroll': r['enroll']})
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    fields = ['year', 'school', 'program', 'language', 'students', 'program_language']
    with open(OUT, 'w', newline='', encoding='utf-8') as fh:
        w = csv.DictWriter(fh, fieldnames=fields, extrasaction='ignore')
        w.writeheader()
        w.writerows(out)
    for f in files:
        y = re.match(r'(\d{4}-\d{2})', os.path.basename(f)).group(1)
        ys = [r for r in out if r['year'] == y]
        sp = {(r['school'], r['program']) for r in ys}
        print(y, len(ys), 'rows,', len({r['school'] for r in ys}), 'schools,', len(sp), 'school-programs')
    print('wrote', os.path.relpath(OUT))
    imm = {(r['year'], r['school'], r['program']): r for r in out if r['program_language']}
    cross_check([dict(school=s, year=y, program_language=r['program_language'], enroll=r['enroll'])
                 for (y, s, _), r in imm.items()])
    print('\nshare of immersion students whose home language matches the program language')
    want = {'Mandarin': 'Chinese'}
    for (y, s, p), r in sorted(imm.items(), key=lambda kv: (kv[1]['school'], kv[0][0])):
        lang = want.get(r['program_language'], r['program_language'])
        n = next(o['students'] for o in out if (o['year'], o['school'], o['program'], o['language']) == (y, s, p, lang))
        print(f"{y} {s:28s} {p:22s} {n:4d}/{r['enroll']:4d} = {100 * n / r['enroll']:.0f}%")


if __name__ == '__main__':
    main()
