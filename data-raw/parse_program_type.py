"""Parse PPS "Enrollment by Grade and Program Type" PDFs into one long CSV.

Source PDFs (data-raw/pps_reports/*_Enrollment_by_Grade_and_Program_Type.pdf) come from
https://www.pps.net/departments/dataaccountability/data-and-accountability/data-strategy-and-insights/data-and-reporting
and its historical archive (https://www.pps.net/fs/pages/46482). They are the October 1st
enrollment counts, one row per school (or per school program) by grade PK, KG, 01..12 and Total.

Layout quirks handled here:
- In the text layer every row is its label line(s) followed by exactly 15 cell lines (14 grades +
  Total). Grades a row does not serve are a blank line (" "), so cells are read by position.
  Counts of 1,000 or more carry thousands commas.
- A school with several programs prints its name on the first row only, then the program name
  (e.g. "Spanish Immersion"), then continuation rows with just a program name
  ("Neighborhood Program"), then "<School> Total". A school with one program prints only its name
  and has no school total; those rows are labelled "Whole School" because the report does not say
  what they are. Do not read them as neighborhood: Lent, Richmond and Rigler print one row, yet
  data/dli_track_profiles.csv shows every one of their students in immersion (whole-school
  immersion), so their language comes from WHOLE_SCHOOL (as in parse_language_by_school.py).
- Group rows ("Elementary Schools Total", "Middle School Total", "High School Total",
  "Alt. Programs Total", "CBOs Total", "Special Services Total", "Public Charter Schools Total",
  "District Total") close a section; they are used for validation only and not written.
- Each page repeats a title/header block ("Name / School Program / PK / KG / 01 ...") at the top and
  a footnote block at the end; both are cut before the rows are read. A long name can wrap onto two
  lines ("Rosemary Anderson H.S. - New " / "Columbia"); the first line ends in a space.
- Names differ across years for the same community org (e.g. "Rosemary Anderson H.S. - Lents" in
  2024-25 vs "RA Prep Lents" in 2025-26); they are kept as printed.

Validation (exits on failure): each row's grades sum to its Total; each school's program rows sum to
its printed school total per grade; each section's schools sum to the section total; sections sum to
the District Total. Then immersion totals are cross-checked against data/dli_track_profiles.csv and
any mismatch is printed (not fatal, since that file is a separate PPS report).

Usage: python3 data-raw/parse_program_type.py  ->  data/enrollment_by_program_grade.csv
"""
import csv
import glob
import os
import re
import sys
import unicodedata
from collections import defaultdict

from pypdf import PdfReader

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'data', 'enrollment_by_program_grade.csv')
DLI = os.path.join(HERE, '..', 'data', 'dli_track_profiles.csv')

GRADES = ['PK', 'K', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12']
LANGUAGES = ['Spanish', 'Mandarin', 'Japanese', 'Russian', 'Vietnamese']
# Group total row -> section name for the rows it closes.
SECTIONS = {
    'Elementary Schools Total': 'Elementary', 'Middle School Total': 'Middle',
    'High School Total': 'High', 'Alt. Programs Total': 'Alternative', 'CBOs Total': 'CBO',
    'Special Services Total': 'Special Services', 'Public Charter Schools Total': 'Charter',
}
# Names in the DLI profiles file that differ from this report after accent/case folding.
ALIASES = {}


def clean_lines(page):
    """Rows' text lines for one page, without the header block and the footnote/title block."""
    raw = (page.extract_text() or '').split('\n')
    if raw[:2] != ['Name', 'School Program']:
        sys.exit(f'unexpected page header: {raw[:3]}')
    raw = raw[raw.index('Total') + 1:]
    for i, l in enumerate(raw):
        if l.strip() in ('October', 'Portland Public Schools'):
            raw = raw[:i]
            break
    while raw and raw[-1].strip() == '':
        raw.pop()
    return raw


def read_rows(path):
    """(labels, 15 cell values) for every row in the file; blank cells are None."""
    rows, labels, cells = [], [], []
    for page in PdfReader(path).pages:
        for l in clean_lines(page):
            s = l.strip()
            if re.fullmatch(r'[\d,]+', s) or (s == '' and labels):
                cells.append(int(s.replace(',', '')) if s else None)
                if len(cells) == 15:
                    rows.append((labels, cells))
                    labels, cells = [], []
            elif s == '':
                continue
            else:
                if cells:
                    sys.exit(f'{path}: row {labels} has only {len(cells)} cells before next label {s!r}')
                if labels and prev_raw.endswith(' ') and not prev_raw.endswith('Total '):
                    labels[-1] = labels[-1] + ' ' + s  # wrapped name
                else:
                    labels.append(re.sub(r'\s+', ' ', s))
            prev_raw = l
        if labels or cells:
            sys.exit(f'{path}: row {labels} continues past a page break ({len(cells)} cells)')
    return rows


# Whole-school immersion schools print one unlabelled row; language from dli_track_profiles.csv.
WHOLE_SCHOOL = {'Lent': 'Spanish', 'Rigler': 'Spanish', 'Richmond': 'Japanese'}


def language_of(program):
    m = re.match(r'(\w+) Immersion$', program)
    if m and m.group(1) in LANGUAGES:
        return m.group(1)
    if m:
        sys.exit(f'unknown immersion language in program {program!r}')
    return ''


def check_sum(label, parts, total):
    """Grade-by-grade sum of `parts` (lists of 15 cells) must equal `total`."""
    got = [sum(p[i] or 0 for p in parts) for i in range(15)]
    want = [c or 0 for c in total]
    if got != want:
        bad = [(g, a, b) for g, a, b in zip(GRADES + ['Total'], got, want) if a != b]
        sys.exit(f'{label}: components do not sum to printed total (grade, sum, printed): {bad}')


def parse_file(path):
    year = re.match(r'(\d{4}-\d{2})', os.path.basename(path)).group(1)
    out, pending, sec_cells = [], [], []  # pending: (school, program, cells) of the section being read
    school, open_school, school_rows = None, False, []
    section_schools, section_totals, district = [], [], None
    for labels, cells in read_rows(path):
        name = ' '.join(labels)
        if len(labels) > 2:
            sys.exit(f'{year}: unexpected label lines {labels}')
        # every row: grades sum to its Total
        if sum(c or 0 for c in cells[:14]) != (cells[14] or 0):
            sys.exit(f'{year} {name}: grades sum to {sum(c or 0 for c in cells[:14])}, printed total {cells[14]}')
        if len(labels) == 1 and labels[0] == 'District Total':
            if open_school or pending:
                sys.exit(f'{year}: unclosed rows before District Total')
            check_sum(f'{year} District Total', section_totals, cells)
            district = cells
            continue
        if len(labels) == 1 and labels[0] in SECTIONS:
            if open_school:
                sys.exit(f'{year}: school {school} not closed before {labels[0]}')
            check_sum(f'{year} {labels[0]}', sec_cells, cells)
            for s, p, c in pending:
                out.append({'year': year, 'school': s, 'program': p, 'section': SECTIONS[labels[0]], 'cells': c})
            section_totals.append(cells)
            pending, sec_cells = [], []
            continue
        if len(labels) == 2:
            if open_school:
                sys.exit(f'{year}: school {school} not closed before {labels[0]}')
            school, open_school, school_rows = labels[0], True, []
            program = labels[1]
        elif open_school and labels[0] == school + ' Total':
            check_sum(f'{year} {school}', school_rows, cells)
            pending.extend((school, p, c) for p, c in zip(progs, school_rows))
            sec_cells.append(cells)
            open_school = False
            continue
        elif open_school:
            program = labels[0]
        else:
            school, program = labels[0], None   # single-program school; label set by section below
            if school.endswith(' Total'):
                sys.exit(f'{year}: stray total row {school!r}')
            pending.append((school, None, cells))
            sec_cells.append(cells)
            continue
        if len(school_rows) == 0:
            progs = []
        progs.append(program)
        school_rows.append(cells)
    if open_school or pending or district is None:
        sys.exit(f'{year}: file ended with unclosed rows or no District Total')
    # fill default program for single-program schools now that sections are known
    rows = []
    for r in out:
        program = r['program'] or 'Whole School'
        for g, c in zip(GRADES, r['cells'][:14]):
            if c is not None:
                rows.append({'year': year, 'school': r['school'], 'section': r['section'], 'program': program,
                             'language': language_of(program) or (WHOLE_SCHOOL.get(r['school'], '') if program == 'Whole School' else ''),
                             'grade': g, 'enrollment': c})
    return rows


def fold(s):
    s = unicodedata.normalize('NFKD', s).encode('ascii', 'ignore').decode().lower()
    s = ALIASES.get(s, s)
    return re.sub(r'[^a-z0-9]+', ' ', s).strip()


def cross_check(rows):
    imm, total = defaultdict(int), defaultdict(int)
    for r in rows:
        total[(r['year'], fold(r['school']))] += r['enrollment']
        if r['language']:
            imm[(r['year'], fold(r['school']))] += r['enrollment']
    with open(DLI, encoding='utf-8') as fh:
        dli = {(d['year'], fold(d['school'])): d for d in csv.DictReader(fh)}
    years = sorted({r['year'] for r in rows})
    for y in years:
        ok, bad, whole = 0, [], []
        keys = {k for k in imm if k[0] == y} | {k for k in dli if k[0] == y}
        for k in sorted(keys):
            a, b = imm.get(k, 0), int(dli[k]['immersion_total']) if k in dli else None
            if b is None:
                bad.append(f'{k[1]}: in program-type report ({a}) but not in dli_track_profiles')
            elif a == 0 and b == total[k]:
                whole.append(f'{k[1]} ({b})')
            elif a != b:
                bad.append(f'{k[1]}: program-type report {a} vs dli_track_profiles {b}')
            else:
                ok += 1
        print(f'{y} immersion cross-check: {ok} schools match, {len(bad)} mismatches')
        if whole:
            print('    whole-school immersion (one unsplit row in this report; dli_track_profiles immersion_total '
                  'equals school enrollment):', ', '.join(whole))
        for b in bad:
            print('   ', b)


def main():
    files = sorted(glob.glob(os.path.join(HERE, 'pps_reports', '*_Enrollment_by_Grade_and_Program_Type.pdf')))
    rows = [r for f in files for r in parse_file(f)]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    cols = ['year', 'school', 'program', 'language', 'grade', 'enrollment', 'section']
    with open(OUT, 'w', newline='', encoding='utf-8') as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)
    for y in sorted({r['year'] for r in rows}):
        yr = [r for r in rows if r['year'] == y]
        print(y, len(yr), 'rows,', len({r['school'] for r in yr}), 'schools,',
              sum(r['enrollment'] for r in yr), 'students')
    print('programs:', sorted({r['program'] for r in rows}))
    print('validation passed: grade sums, school totals, section totals, District Total')
    cross_check(rows)
    print('wrote', os.path.relpath(OUT))


if __name__ == '__main__':
    main()
