"""Parse PPS "School and Neighborhood Enrollment Details by Ethnicity and Programs" PDFs.

Source PDFs (data-raw/pps_board/school_neighborhood_enroll_ethnicity_program_{A,B}.pdf; A = October
2025, B = October 2024, years read from the title line) come from
https://www.pps.net/departments/dataaccountability/data-and-accountability/data-strategy-and-insights/data-and-reporting

Layout: 4 landscape pages (A 792 x 612; B 1298 x 1003). One "<Name> School" row followed by a
"Neighborhood" row per school, then a "Grand Total" row. Column labels, in order:
School Name | School / Neighborhood | October Enrollment | Latino | African American | Asian |
Native American | Pacific Islander | White | Asian/White | Other Ancestries (the race group is headed
"Percentage of Enrollment by Race/Ethnicity", with "One Racial Group, not Latino" over the first six
and "Multi-Racial" over Asian/White and Other Ancestries) | Direct Certification | English Language
Learners | Talented and Gifted | Language Immersion | Focus Option / Alt | Historically Underserved
(headed "Percentage of Enrollment by Program"). The first race column is labelled only "Latino" in the
text layer. All values after enrollment are whole-number percentages.

Footnotes (verbatim): "Direct Certification is defined as data from Nutrition Services, provided by
the state, which has identified students as eligible for Free meals. For comparability between
schools, Portland Public Schools is no longer including data from paper applications. Historically
Underserved are Latino, African American, Native American, Pacific Islander and Multi-Racial Other
Ancestries. In the 'School / Neighborhood' column, School represents the enrollment of K-12 Students
attending the School in October. Neighborhood represents the Students who live in the School
Neighborhood Boundary in K-12. Not all PK aged students attend a PPS PK program, therefore PK not
included as otherwise neighborhood percentages may be inflated due to the location of the Headstart
and other PK programs."
So a Neighborhood row counts K-12 students living in the attendance area, whichever school they attend.

Blank cells are omitted from the text layer, so columns are assigned by x position. Each cell's right
edge is computed from the content stream (percent cells are right-aligned): in B every cell has its own
text matrix; in A a row is one TJ array whose large negative adjustments encode the gaps, so advances are
accumulated with the font's /W widths (glyph id = ASCII - 29). The 14 percentage columns are calibrated
by clustering the right edges (must give exactly 14).

A blank cell is treated as 0 (not suppressed): a percentage that rounds to zero is printed as "0%" only
for some rows, and rows with blanks still sum to ~100 (see the validation). Blanks are written as 0 and
counted in the printout.

Validation (sys.exit on failure): 14 columns; every row has enrollment; percentages within 0-100;
race/ethnicity sums 97-103 (rounding); every Neighborhood row follows its School row (option schools have a label-only Neighborhood row with no data, which is skipped); Grand Total
enrollment and percentages match the School rows (weighted); cross-checks of % Language Immersion x
enrollment against data/dli_track_profiles.csv and of enrollment against
data/enrollment_by_program_grade.csv.

Usage: python3 data-raw/parse_ethnicity_program.py  ->  data/school_demographics.csv
"""
import csv
import os
import re
import sys
import unicodedata
from collections import defaultdict

from pypdf import PdfReader
from pypdf.generic import ContentStream

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'data', 'school_demographics.csv')
PROFILES = os.path.join(HERE, '..', 'data', 'dli_track_profiles.csv')
PROGRAM_GRADE = os.path.join(HERE, '..', 'data', 'enrollment_by_program_grade.csv')
FILES = ['school_neighborhood_enroll_ethnicity_program_A.pdf', 'school_neighborhood_enroll_ethnicity_program_B.pdf']
YEARS = {'2025': '2025-26', '2024': '2024-25'}  # October year -> school year
COLS = ['pct_latino', 'pct_african_american', 'pct_asian', 'pct_native_american', 'pct_pacific_islander',
        'pct_white', 'pct_multi_asian_white', 'pct_multi_other', 'pct_direct_cert', 'pct_ell', 'pct_tag',
        'pct_immersion', 'pct_focus_alt', 'pct_hist_underserved']
RACE = COLS[:8]
TOL_RACE = 3      # race sums must be 100 +- 3
TOL_TOTAL = 1.0   # Grand Total pct vs weighted mean of School rows (points)


def mul(a, b):
    return [a[0] * b[0] + a[1] * b[2], a[0] * b[1] + a[1] * b[3], a[2] * b[0] + a[3] * b[2],
            a[2] * b[1] + a[3] * b[3], a[4] * b[0] + a[5] * b[2] + b[4], a[4] * b[1] + a[5] * b[3] + b[5]]


def cid_widths(font):
    """CID -> width (1/1000 em) from a Type0 font's /W array (only the 'c_first c_last w' form is used)."""
    if '/DescendantFonts' not in font:
        return None
    W, w, i = font['/DescendantFonts'][0].get_object()['/W'], {}, 0
    while i < len(W):
        if isinstance(W[i + 1], list):
            sys.exit('unexpected /W array form')
        for c in range(int(W[i]), int(W[i + 1]) + 1):
            w[c] = float(W[i + 2])
        i += 3
    return w


def to_unicode(font):
    """CID -> str from a Type0 font's ToUnicode CMap (bfchar / bfrange)."""
    if '/ToUnicode' not in font:
        return None
    d = font['/ToUnicode'].get_object().get_data().decode('latin1')
    m = {}
    for blk in re.findall(r'beginbfchar(.*?)endbfchar', d, re.S):
        for a, b in re.findall(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>', blk):
            m[int(a, 16)] = bytes.fromhex(b).decode('utf-16-be')
    for blk in re.findall(r'beginbfrange(.*?)endbfrange', d, re.S):
        for a, b, c in re.findall(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>', blk):
            for k in range(int(a, 16), int(b, 16) + 1):
                m[k] = chr(int(c, 16) + k - int(a, 16))
    return m


def page_cells(reader, page):
    """Return (y, x_left, x_right, text) for every text cell (glyph runs split at gaps > 6 pt)."""
    fonts = page['/Resources']['/Font']
    cm, stack, tm, font, fs, widths, uni, out = [1, 0, 0, 1, 0, 0], [], None, None, 1.0, {}, {}, []
    for o, op in ContentStream(page.get_contents(), reader).operations:
        if op == b'q':
            stack.append(cm[:])
        elif op == b'Q':
            cm = stack.pop()
        elif op == b'cm':
            cm = mul([float(v) for v in o], cm)
        elif op == b'Tf':
            font, fs = str(o[0]), float(o[1])
            if font not in widths:
                widths[font] = cid_widths(fonts[font].get_object())
                uni[font] = to_unicode(fonts[font].get_object())
        elif op == b'Tm':
            tm = [float(v) for v in o]
        elif op in (b'TJ', b'Tj'):
            arr = o[0] if op == b'TJ' else [o[0]]
            m = mul(tm, cm)
            sc, x, y, w = fs * abs(m[0]), m[4], m[5], widths[font]
            cur = None
            for it in arr:
                if isinstance(it, str):
                    for ch in it:
                        adv = (w[ord(ch)] if w else 556 if ch.isdigit() else 889 if ch == '%' else 500) / 1000 * sc
                        if cur is None:
                            cur = [x, '']
                        cur[1] += uni[font].get(ord(ch), '?') if w else ch
                        x += adv
                        cur.append(x) if len(cur) == 2 else cur.__setitem__(2, x)
                else:
                    gap = -float(it) / 1000 * sc
                    if gap > 6 and cur:
                        out.append((round(y, 1), round(cur[0], 1), round(cur[2], 1), cur[1].strip()))
                        cur = None
                    x += gap
            if cur:
                out.append((round(y, 1), round(cur[0], 1), round(cur[2], 1), cur[1].strip()))
    return [c for c in out if c[3]]


def parse_file(path):
    reader = PdfReader(path)
    cells = [(pi, *c) for pi, p in enumerate(reader.pages) for c in page_cells(reader, p)]
    title = next((c[4] for c in cells if c[4].startswith('School and Neighborhood Enrollment Details')), '')
    m = re.search(r'October (\d{4})', title)
    if not m or m.group(1) not in YEARS:
        sys.exit(f'{path}: cannot read year from title {title!r}')
    year = YEARS[m.group(1)]
    # Calibrate the 14 percentage columns from the right edges of all % cells in data rows.
    pct = sorted({c[3] for c in cells if re.fullmatch(r'\d+%', c[4])})
    clusters = []
    for e in pct:
        if clusters and e - clusters[-1][-1] < 5:
            clusters[-1].append(e)
        else:
            clusters.append([e])
    # Only percentage cells of data rows count: the 14 clusters must hold the bulk of cells.
    if len(clusters) != 14:
        sys.exit(f'{year}: expected 14 percentage columns, found {len(clusters)}: {[round(sum(c)/len(c)) for c in clusters]}')
    centers = [sum(c) / len(c) for c in clusters]
    rows = defaultdict(list)
    for pi, y, a, b, t in cells:
        # cells of one row can differ by a fraction of a point in y: snap to an existing row within 2 pt
        k = next((k for k in rows if k[0] == pi and abs(k[1] - y) < 2), (pi, y))
        rows[k].append((a, b, t))
    out, school, grand, last_kind, last_name, empty_nb = [], None, None, None, None, []
    for key in sorted(rows, key=lambda k: (k[0], -k[1])):  # top of page = largest y
        cs = sorted(rows[key])
        texts = [t for _, _, t in cs]
        if texts == ['Neighborhood']:
            empty_nb.append(school)  # option school with no attendance area: label only, no data
            continue
        if not any(re.fullmatch(r'\d+%', t) for t in texts):
            continue  # header, title and footnote lines
        if 'School' in texts or 'Neighborhood' in texts or 'Grand Total' in texts or 'School/Program' in texts:
            if 'School/Program' in texts:
                i = texts.index('School/Program')
                name, kind = ' '.join(texts[:i]), 'Program'
            elif 'School' in texts:
                i = texts.index('School')
                name, kind = ' '.join(texts[:i]), 'School'
                if name.endswith('Subtotal'):
                    kind = 'Subtotal School'
            elif 'Neighborhood' in texts:
                i = texts.index('Neighborhood')
                if i == 0:
                    name, kind = (school if school else ''), 'Neighborhood'
                    if last_kind == 'Subtotal School':
                        name, kind = last_name, 'Subtotal Neighborhood'
                elif ' '.join(texts[:i]) == 'Out of District/Undetermined':
                    name, kind = 'Out of District/Undetermined', 'Out of District'
                else:
                    sys.exit(f'{year}: unexpected Neighborhood row {texts[:4]}')
            else:
                i, name, kind = texts.index('Grand Total'), 'Grand Total', 'Grand Total'
            rest = cs[i + 1:]
            enr_cells = [c for c in rest if re.fullmatch(r'[\d,]+', c[2])]
            if len(enr_cells) != 1:
                sys.exit(f'{year} {name} {kind}: enrollment cell not found: {texts}')
            enroll = int(enr_cells[0][2].replace(',', ''))
            vals = [None] * 14
            for a, b, t in rest:
                if not t.endswith('%'):
                    continue
                col = min(range(14), key=lambda j: abs(centers[j] - b))
                if abs(centers[col] - b) > 4 or vals[col] is not None:
                    sys.exit(f'{year} {name} {kind}: bad cell {t} at right edge {b} (column {col})')
                vals[col] = int(t[:-1])
            if kind == 'School':
                school = name
            last_kind, last_name = kind, name
            if kind == 'Neighborhood' and not school:
                sys.exit(f'{year}: Neighborhood row before any School row')
            out.append({'year': year, 'row_type': kind, 'name': name, 'enrollment': enroll,
                        **dict(zip(COLS, vals))})
    grand = [r for r in out if r['row_type'] == 'Grand Total']
    if len(grand) != 1:
        sys.exit(f'{year}: {len(grand)} Grand Total rows')
    print(f'{year}: Neighborhood rows with no data (label only): {empty_nb}')
    return year, [r for r in out if r['row_type'] != 'Grand Total'], grand[0], empty_nb


def validate(year, allrows, grand, empty_nb):
    """Check all rows, then roll-ups; return only the School and Neighborhood rows."""
    rows = [r for r in allrows if r['row_type'] in ('School', 'Neighborhood')]
    sch = [r for r in rows if r['row_type'] == 'School']
    nb = [r for r in rows if r['row_type'] == 'Neighborhood']
    if len(sch) != len(nb) + len(empty_nb):
        sys.exit(f'{year}: {len(sch)} School rows, {len(nb)} Neighborhood rows + {len(empty_nb)} label-only')
    if [r['name'] for r in sch if r['name'] not in empty_nb] != [r['name'] for r in nb]:
        sys.exit(f'{year}: Neighborhood rows do not line up with School rows')
    blanks = 0
    for r in allrows + [grand]:
        where = f"{year} {r['name']} ({r['row_type']})"
        for c in COLS:
            if r[c] is None:
                blanks += 1
            elif not 0 <= r[c] <= 100:
                sys.exit(f'{where}: {c} = {r[c]} outside 0-100')
        s = sum(r[c] or 0 for c in RACE)
        if abs(s - 100) > TOL_RACE:
            sys.exit(f'{where}: race/ethnicity sums to {s}')
    # Roll-ups. School side: school rows + Charter/Special Services/CBO/PPS Alternatives "School/Program" rows
    # = the three level subtotals = Grand Total. Neighborhood side: neighborhood rows + Out of District.
    by = defaultdict(list)
    for r in allrows:
        by[r['row_type']].append(r)
    if len(by['Subtotal School']) != 3 or len(by['Subtotal Neighborhood']) != 3 or len(by['Program']) != 4 \
            or len(by['Out of District']) != 1:
        sys.exit(f'{year}: roll-up rows found: { {k: len(v) for k, v in by.items()} }')
    n = lambda rs: sum(r['enrollment'] for r in rs)
    G = grand['enrollment']
    # A School row that is missing from the text layer (Clark, both years) shows up as the gap between the
    # level subtotals and the School rows; require it to equal that school's K-12 enrollment elsewhere.
    mine = {key(r['name']) for r in sch}
    absent = {k: v for k, v in program_grade_totals(year).items() if k not in mine}
    gap = n(by['Subtotal School']) - n(sch)
    if gap != sum(v[1] for v in absent.values()):
        sys.exit(f'{year}: School rows are {gap} short of the level subtotals; schools absent from the report '
                 f'({ {v[0]: v[1] for v in absent.values()} }) do not explain it')
    if absent:
        print(f"{year}: NOT in the report's text layer although the subtotals include them: "
              f"{ {v[0]: v[1] for v in absent.values()} } (gap {gap})")
    checks = {
        'School subtotals + Program rows == Grand Total': n(by['Subtotal School']) + n(by['Program']) == G,
    }
    for k, ok in checks.items():
        if not ok:
            sys.exit(f'{year}: {k} failed')
    # Percentages: Grand Total vs enrollment-weighted mean over the School-side rows present
    side = sch + by['Program']
    for c in COLS:
        w = sum((r[c] or 0) * r['enrollment'] for r in side) / n(side)
        if abs(w - (grand[c] or 0)) > TOL_TOTAL:
            sys.exit(f"{year}: {c} weighted mean {w:.2f} vs Grand Total {grand[c]}")
    sums = [sum(r[c] or 0 for c in RACE) for r in allrows]
    print(f'{year}: Grand Total {G} = level subtotals {n(by["Subtotal School"])} + Program rows {n(by["Program"])}; '
          f'School rows {n(sch)} (+ {gap} absent); Neighborhood rows {n(nb)}, Neighborhood subtotals '
          f'{n(by["Subtotal Neighborhood"])}, Out of District {n(by["Out of District"])}')
    print(f'{year}: {blanks} blank percentage cells (treated as 0); race sums range {min(sums)}-{max(sums)}; '
          f'{sum(1 for x in sums if x != 100)} of {len(sums)} rows != 100')
    return rows


def program_grade_totals(year):
    """key -> (name, K-12 enrollment) for Elementary/Middle/High schools in enrollment_by_program_grade.csv."""
    out = {}
    if os.path.exists(PROGRAM_GRADE):
        for e in csv.DictReader(open(PROGRAM_GRADE, encoding='utf-8')):
            if e['year'] == year and e['section'] in ('Elementary', 'Middle', 'High') and e['grade'] != 'PK':
                k = key(e['school'])
                out[k] = (e['school'], out.get(k, (0, 0))[1] + int(float(e['enrollment'] or 0)))
    return out


def key(s):
    s = unicodedata.normalize('NFKD', s).encode('ascii', 'ignore').decode().lower()
    return re.sub(r'[^a-z0-9]', '', s.replace('school', ''))


def cross_check(year, rows):
    sch = {key(r['name']): r for r in rows if r['row_type'] == 'School'}
    if os.path.exists(PROFILES):
        bad = n = 0
        off = []
        for p in csv.DictReader(open(PROFILES, encoding='utf-8')):
            if p['year'] != year:
                continue
            r = sch.get(key(p['school']))
            if not r:
                print(f"cross-check {year}: profile school {p['school']} not found in report (see absent-school note above)"); bad += 1; continue
            n += 1
            est = (r['pct_immersion'] or 0) / 100 * r['enrollment']
            imm = int(p['immersion_total'] or 0)
            pts = abs(100 * imm / r['enrollment'] - (r['pct_immersion'] or 0))
            if r['enrollment'] != int(p['enrollment']):
                sys.exit(f"{year} {p['school']}: enrollment {r['enrollment']} vs profile {p['enrollment']}")
            if pts > 1:  # a whole-number % can be off by 0.5 pt, so >1 pt is a real mismatch
                sys.exit(f"cross-check {year} {p['school']}: {r['pct_immersion']}% vs {imm}/{r['enrollment']} = {100*imm/r['enrollment']:.1f}%")
            if abs(est - imm) > 2:
                off.append(f"{p['school']} {est:.0f} vs {imm}")
        print(f'cross-check {year} immersion: {n} schools compared, all within 1 pt of immersion_total/enrollment '
              f'(and enrollment equal); {len(off)} differ by >2 students only because the printed % is a whole number: {off}')
    if os.path.exists(PROGRAM_GRADE):
        tot, nopk = defaultdict(int), defaultdict(int)
        for e in csv.DictReader(open(PROGRAM_GRADE, encoding='utf-8')):
            if e['year'] == year:
                v = int(float(e['enrollment'] or 0))
                tot[key(e['school'])] += v
                if e['grade'] != 'PK':
                    nopk[key(e['school'])] += v
        d_all = d_nopk = n = missing = 0
        diffs = []
        for k, r in sch.items():
            if k not in tot:
                missing += 1; print(f"cross-check {year}: {r['name']} not in program_grade"); continue
            n += 1
            d_all += tot[k] == r['enrollment']
            d_nopk += nopk[k] == r['enrollment']
            if nopk[k] != r['enrollment']:
                diffs.append((r['name'], r['enrollment'], nopk[k], tot[k]))
        print(f'cross-check {year} enrollment: {n} schools; equal excluding PK: {d_nopk}; equal including PK: {d_all}; not found {missing}')
        for d in diffs:
            print(f'   differs (report, program_grade no-PK, with PK): {d}')


def main():
    allrows = []
    for f in FILES:
        year, rows, grand, empty_nb = parse_file(os.path.join(HERE, 'pps_board', f))
        rows = validate(year, rows, grand, empty_nb)
        cross_check(year, rows)
        for r in rows + [grand]:
            allrows.append(r)
    fields = ['year', 'row_type', 'name', 'enrollment'] + COLS
    with open(OUT, 'w', newline='', encoding='utf-8') as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        for r in allrows:
            w.writerow({k: (r[k] if k in ('year', 'row_type', 'name', 'enrollment') else
                            round((r[k] or 0) / 100, 2)) for k in fields})
    print('wrote', os.path.relpath(OUT), len(allrows), 'rows')


if __name__ == '__main__':
    main()
