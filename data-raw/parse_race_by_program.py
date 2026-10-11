"""Parse PPS "Enrollment Summary by Race and Ethnicity, October 2025" (race and ethnicity counts for each
school AND each program inside a school).

Source PDF: data-raw/pps_reports/race/EnrollmentbyRace25-26.pdf
URL: https://resources.finalsite.net/images/v1761606954/ppsnet/p020rdtb2usyi0zikguo/EnrollmentbyRace25-26.pdf
Retrieved: 2026-10-11.  Output: data/race_by_program_2025.csv

Needs PyMuPDF (import pymupdf), which is in the repo venv, not in the system python:
    .venv/bin/python3 data-raw/parse_race_by_program.py

Layout: 6 landscape pages (842.6 x 651.1 pt); pages 1-5 hold the table, page 6 holds only the footnote.
Column groups, left to right (each has a # and a % column except Total): Latino ethnicity | One racial group,
not Latino: Black, Asian, Native American, Pacific Islander, White | Multi-Racial: Asian/White, Other
Ancestries | Total. Row types:
  * single-program school: one row ("Abernethy 25 9.3 ...")   -> program "School"
  * school with programs: "<School> <Language> Immersion" row, "Neighborhood Program" row, "<School> Total"
    row. Some schools have more than one immersion row (Franklin, McDaniel, Roosevelt: the later program rows
    leave the school-name cell empty, so the school carries over from the row above).
  * whole-school immersion (Lent, Rigler, Richmond): only the immersion row, no Total row.
  * grouped programs outside the regular schools (Alliance, PCC, Rosemary Anderson, DART Programs, PPS
    Pioneer Programs, CTC, Metro. Learning Center, ...): the group name sits in the school-name cell and each
    program in the program cell, like a school with programs.
  * section total rows: Elementary Schools, Middle School, High School, Alt. Programs, CBOs, Special
    Services, Public Charter Schools, and finally District Total. The PDF has no level headings, so `level`
    is the section whose total row comes next (Alt. Programs = ACCESS, Alliance, Head Start, Metro.
    Learning Center; CBOs = Mt Scott ... Youth Progress Association; Special Services = CTC, DART, Pioneer,
    Providence, Serendipity, Special Education). Elementary includes the K-8 schools (e.g. Bridger
    Creative Science, Beverly Cleary) because the report lists them there.

Quirks handled:
  * Blank cells are omitted from the text layer, so columns are assigned by each word's RIGHT edge
    (numbers are right-aligned). Counts: x1 near 290/355/421/488/554/619/685/751 and Total near 817;
    percents: 322/388/454/521/586/652/718/784. In the plain text stream (pypdf, or pymupdf get_text()) the
    Native American count (x1 about 488) does not stay with its row, and only its % shows inline. The word
    boxes from page.get_text("words") do carry it, so every cell is recovered by x position.
  * Percentages print with a trailing dot instead of ".0" ("75." = 75.0). A blank count is 0 students and its
    % is left blank in the CSV.

Output columns: school, program, level, row_type (program | school | school_total | section_total |
district_total), latino_n, black_n, asian_n, native_american_n, pacific_islander_n, white_n, asian_white_n,
other_multi_n, total, the matching *_pct columns (as printed, blank if the cell is empty), source_page.
`school` is the base school name; section total rows use the section name and program "Total".

Footnote (page 6, verbatim): "October 2025 Enrollment Summaries are based on enrollment on 10/1/2025 as
extracted from Synergy student information system. Latino ethnicity includes students identified as
Hispanic/Latino regardless of race. Multiple Races category includes students identified as two or more
races, exclusive of Hispanic/Latino.   The Multiple Race category has been separated into two categories,
Multiple Race students identifying as Asian and White and others identifying with Multiple Races."

Validation (sys.exit(1) on failure):
  1. every row: the eight counts sum to Total;
  2. every printed % equals 100 * n / total within 0.051 (all eight groups); a % without a count, or a count
     without a %, fails;
  3. for each school/group with a Total row, the rows above it add up to that Total in every column;
  4. summing the leaf rows (programs and single schools) of each section reproduces the section total row, and
     the section totals add up to District Total, in every count column;
  5. no duplicate (school, program) pairs; the row count and the per-page, per-level counts are printed.
Also prints a cross-check against data/school_demographics.csv (2025-26 School rows; a different PPS report)
as information only.

Usage: .venv/bin/python3 data-raw/parse_race_by_program.py  ->  data/race_by_program_2025.csv
"""
import csv
import os
import re
import sys
import unicodedata
from collections import Counter, defaultdict

import pymupdf

HERE = os.path.dirname(os.path.abspath(__file__))
PDF = os.path.join(HERE, 'pps_reports', 'race', 'EnrollmentbyRace25-26.pdf')
OUT = os.path.join(HERE, '..', 'data', 'race_by_program_2025.csv')
DEMOG = os.path.join(HERE, '..', 'data', 'school_demographics.csv')

GROUPS = ['latino', 'black', 'asian', 'native_american', 'pacific_islander', 'white', 'asian_white', 'other_multi']
CNT_EDGES = [290, 355, 421, 488, 554, 619, 685, 751]   # right edges of the # columns
PCT_EDGES = [322, 388, 454, 521, 586, 652, 718, 784]   # right edges of the % columns
TOT_EDGE = 817
TOL = 3.5
SCHOOL_X_MAX = 130      # school-name cell starts at x about 21; program cell at x about 139
LABEL_X_MAX = 270       # numbers start right of this
HEADER_Y = 100          # page 1: header rows are above this y
SECTIONS = [            # (label in the PDF, level, total-row school name)
    ('Elementary Schools', 'Elementary'),
    ('Middle School', 'Middle'),
    ('High School', 'High'),
    ('Alt. Programs', 'Alternative programs'),
    ('CBOs', 'Community-based organizations'),
    ('Special Services', 'Special services'),
    ('Public Charter Schools', 'Charter'),
]
SECTION_NAMES = [s for s, _ in SECTIONS]
COLS = ([g + '_n' for g in GROUPS] + ['total'] + [g + '_pct' for g in GROUPS])


def fail(msg):
    print('FAIL: ' + msg)
    sys.exit(1)


def norm(s):
    s = unicodedata.normalize('NFKD', s).encode('ascii', 'ignore').decode().lower()
    return re.sub(r'[^a-z0-9]+', ' ', s).strip()


def nearest(x, edges):
    i = min(range(len(edges)), key=lambda k: abs(edges[k] - x))
    return i if abs(edges[i] - x) <= TOL else None


def page_rows(page):
    """Group the page's words into rows by y position (words in one row differ by < 4 pt)."""
    words = sorted(page.get_text('words'), key=lambda w: (w[1], w[0]))
    rows, cur, cy = [], [], None
    for w in words:
        if cy is None or abs(w[1] - cy) < 4:
            cur.append(w)
            cy = w[1] if cy is None else cy
        else:
            rows.append(cur)
            cur, cy = [w], w[1]
    if cur:
        rows.append(cur)
    return rows


def parse_row(ws, pno):
    """Return (school_label, program_label, cells) for one row, or None if it has no numbers."""
    ws = sorted(ws, key=lambda w: w[0])
    left = [w for w in ws if w[0] < LABEL_X_MAX]
    nums = [w for w in ws if w[0] >= LABEL_X_MAX]
    school = ' '.join(w[4] for w in left if w[0] < SCHOOL_X_MAX).strip()
    program = ' '.join(w[4] for w in left if w[0] >= SCHOOL_X_MAX).strip()
    cells = {}
    for w in nums:
        t = w[4]
        x1 = w[2]
        if '.' in t:                       # percent, e.g. "75." or "9.3"
            i = nearest(x1, PCT_EDGES)
            if i is None:
                fail(f'page {pno}: percent {t!r} at x1={x1:.0f} not on a % column ({school} {program})')
            key, val = GROUPS[i] + '_pct', float(t)
        else:                              # count (may contain a thousands comma)
            if not re.fullmatch(r'\d{1,3}(,\d{3})*|\d+', t):
                fail(f'page {pno}: unexpected token {t!r} in row {school} {program}')
            val = int(t.replace(',', ''))
            if abs(x1 - TOT_EDGE) <= TOL:
                key = 'total'
            else:
                i = nearest(x1, CNT_EDGES)
                if i is None:
                    fail(f'page {pno}: count {t!r} at x1={x1:.0f} not on a # column ({school} {program})')
                key = GROUPS[i] + '_n'
        if key in cells:
            fail(f'page {pno}: two values for {key} in row {school} {program}')
        cells[key] = val
    return school, program, cells


def main():
    doc = pymupdf.open(PDF)
    if doc.page_count != 6:
        fail(f'expected 6 pages, found {doc.page_count}')
    foot = ' '.join(doc[5].get_text().split())
    for phrase in ['Enrollment Summary by Race and Ethnicity, October 2025',
                   'Latino ethnicity includes students identified as Hispanic/Latino regardless of race',
                   'Multiple Race category has been separated into two categories']:
        if phrase not in foot:
            fail(f'page 6 footnote missing {phrase!r}')

    # ---- 1. read rows --------------------------------------------------------------------------
    rows = []                     # dicts in printed order
    cur_school = None             # school/group whose rows are open (cleared by its Total row)
    for pno in range(1, 6):
        for ws in page_rows(doc[pno - 1]):
            if pno == 1 and ws[0][1] < HEADER_Y:
                continue                              # titles and column headers
            if pno > 1 and ws[0][1] < 50:
                continue                              # running title
            school, program, cells = parse_row(ws, pno)
            if not cells:
                fail(f'page {pno}: row with no numbers: {school!r} {program!r}')
            r = {'page': pno, 'cells': cells}
            lab = school.strip()
            if lab.endswith(' Total') and not program:
                base = lab[:-len(' Total')].strip()
                if base in SECTION_NAMES:
                    r.update(school=base, program='Total', row_type='section_total')
                elif lab == 'District Total':
                    r.update(school='District', program='Total', row_type='district_total')
                elif cur_school and base == cur_school:
                    r.update(school=base, program='Total', row_type='school_total')
                    cur_school = None
                else:
                    fail(f'page {pno}: Total row {lab!r} does not close an open school ({cur_school!r})')
            elif lab:
                cur_school = lab
                r.update(school=lab, program=program or 'School', row_type='program' if program else 'school')
            else:
                if not cur_school:
                    fail(f'page {pno}: program row {program!r} with no school above it')
                r.update(school=cur_school, program=program, row_type='program')
            rows.append(r)

    # ---- levels: the section whose total row comes next ------------------------------------------
    pending = []
    sec_levels = dict(SECTIONS)
    for r in rows:
        if r['row_type'] == 'section_total':
            r['level'] = sec_levels[r['school']]
            for p in pending:
                p['level'] = r['level']
            pending = []
        elif r['row_type'] == 'district_total':
            r['level'] = 'All'
        else:
            pending.append(r)
    if pending:
        fail(f'{len(pending)} rows after the last section total have no level')
    # Section totals must appear in the printed order
    order = [r['school'] for r in rows if r['row_type'] == 'section_total']
    if order != SECTION_NAMES:
        fail(f'section totals out of order or missing: {order}')

    # ---- fill blanks, build output records ---------------------------------------------------------
    for r in rows:
        c = r['cells']
        if 'total' not in c:
            fail(f"page {r['page']}: no Total in row {r['school']} / {r['program']}")
        for g in GROUPS:
            n, p = g + '_n', g + '_pct'
            if (n in c) != (p in c):
                fail(f"page {r['page']}: {r['school']} / {r['program']}: count and % disagree on blank for {g} "
                     f"(count={c.get(n)}, pct={c.get(p)})")
            c.setdefault(n, 0)            # blank = 0 students; % stays blank
    # ---- checks --------------------------------------------------------------------------------------
    problems = []
    for r in rows:
        c, tag = r['cells'], f"p{r['page']} {r['school']} / {r['program']}"
        s = sum(c[g + '_n'] for g in GROUPS)
        if s != c['total']:
            problems.append(f"1. {tag}: counts sum to {s}, Total is {c['total']}")
        for g in GROUPS:
            if g + '_pct' in c:
                exp = 100 * c[g + '_n'] / c['total']
                if abs(c[g + '_pct'] - exp) > 0.051:
                    problems.append(f"2. {tag}: {g} printed {c[g + '_pct']} vs {exp:.2f}")
    # 3. school totals
    open_rows = []
    for r in rows:
        if r['row_type'] in ('school', 'program'):
            if r['row_type'] == 'school' or not open_rows or open_rows[-1]['school'] != r['school']:
                open_rows = []
            open_rows.append(r)
        elif r['row_type'] == 'school_total':
            grp = [x for x in open_rows if x['school'] == r['school']]
            if len(grp) < 1:
                problems.append(f"3. {r['school']}: Total row has {len(grp)} rows above it")
            for k in [g + '_n' for g in GROUPS] + ['total']:
                if sum(x['cells'][k] for x in grp) != r['cells'][k]:
                    problems.append(f"3. {r['school']}: {k} rows sum to {sum(x['cells'][k] for x in grp)}, "
                                    f"Total row {r['cells'][k]}")
            open_rows = []
    # 4. section and district totals
    ncols = [g + '_n' for g in GROUPS] + ['total']
    secsum = defaultdict(lambda: Counter())
    for r in rows:
        if r['row_type'] in ('school', 'program'):
            for k in ncols:
                secsum[r['level']][k] += r['cells'][k]
    dist = Counter()
    for r in rows:
        if r['row_type'] == 'section_total':
            for k in ncols:
                dist[k] += r['cells'][k]
                if secsum[r['level']][k] != r['cells'][k]:
                    problems.append(f"4. {r['school']} {k}: leaf rows sum to {secsum[r['level']][k]}, "
                                    f"printed {r['cells'][k]}")
    d = [r for r in rows if r['row_type'] == 'district_total']
    if len(d) != 1:
        problems.append(f'4. expected one District Total row, found {len(d)}')
    else:
        for k in ncols:
            if dist[k] != d[0]['cells'][k]:
                problems.append(f"4. District Total {k}: sections sum to {dist[k]}, printed {d[0]['cells'][k]}")
    # 5. duplicates
    keys = Counter((r['school'], r['program']) for r in rows)
    for k, v in keys.items():
        if v > 1:
            problems.append(f'5. duplicate (school, program) {k} x{v}')
    if problems:
        print('\n'.join(problems))
        fail(f'{len(problems)} validation problem(s)')

    # ---- write ---------------------------------------------------------------------------------------
    fields = (['school', 'program', 'level', 'row_type'] + [g + '_n' for g in GROUPS] + ['total'] +
              [g + '_pct' for g in GROUPS] + ['source_page'])
    with open(OUT, 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in rows:
            o = {'school': r['school'], 'program': r['program'], 'level': r['level'],
                 'row_type': r['row_type'], 'source_page': r['page']}
            for k in COLS:
                o[k] = r['cells'].get(k, '')
            w.writerow(o)

    print(f'OK: {len(rows)} rows written to {os.path.relpath(OUT)}; all checks passed')
    print('rows by page:', dict(sorted(Counter(r['page'] for r in rows).items())))
    print('rows by level:', dict(Counter(r['level'] for r in rows)))
    print('rows by page and level:', dict(sorted(Counter((r['page'], r['level']) for r in rows).items())))
    print('rows by type:', dict(Counter(r['row_type'] for r in rows)))

    # ---- information only: compare with school_demographics.csv ---------------------------------------
    if os.path.exists(DEMOG):
        dem = {}
        with open(DEMOG, encoding='utf-8') as f:
            for x in csv.DictReader(f):
                if x['year'] == '2025-26' and x['row_type'] == 'School':
                    dem[norm(x['name'])] = x
        whole = [r for r in rows if r['row_type'] == 'school_total' or
                 (r['row_type'] == 'school') or
                 (r['row_type'] == 'program' and r['program'].endswith('Immersion') and
                  not any(q['school'] == r['school'] and q['row_type'] == 'school_total' for q in rows))]
        diffs, nomatch, nmatch = [], [], 0
        for r in whole:
            if r['level'] in ('All',):
                continue
            m = dem.get(norm(r['school']))
            if not m:
                nomatch.append(r['school'])
                continue
            nmatch += 1
            c = r['cells']
            dn = int(m['enrollment'])
            dl, dw = float(m['pct_latino']), float(m['pct_white'])
            ol, ow = c['latino_n'] / c['total'], c['white_n'] / c['total']
            if dn != c['total'] or abs(dl - ol) > 0.0051 or abs(dw - ow) > 0.0051:
                diffs.append(f"  {r['school']}: total {c['total']} vs {dn}; Latino {ol:.3f} vs {dl}; White {ow:.3f} vs {dw}")
        print(f'cross-check vs school_demographics.csv: {nmatch} schools matched; {len(diffs)} differ')
        print('\n'.join(diffs))
        print('  not in school_demographics (or name differs):', ', '.join(nomatch))


if __name__ == '__main__':
    main()
