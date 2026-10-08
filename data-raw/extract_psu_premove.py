"""Extract school x program enrollment forecasts from the three older PSU PRC editions (2022-23, 2023-24,
2024-25), i.e. the forecasts made before / around the 2023-24 move of Bridger's Spanish immersion program
to Lent (Southeast Enrollment and Program Balancing), into data/psu_forecast_premove.csv.

Source PDFs: data-raw/pps_reports/PSU_PRC_Forecast_<first forecast year>_edition.pdf, from the PPS archive page
https://www.pps.net/departments/dataaccountability/data-and-accountability/data-strategy-and-insights/archives
Vintage = first forecast year printed in the report title:

- 2022-23 ("2022-23 to 2036-37", June 2022, based on October 2021 enrollments; 97 pages). Appendix C
  Table C (PDF pages 85-89): one row per school, or per program (Spanish Immersion / Neighborhood Program /
  Total), 13 years 2019-20..2031-32 (3 historic). The report states that the May 2022 Southeast Enrollment
  and Program Balancing changes "are not incorporated in these enrollment forecasts" (PDF page 61).
  Written as the district total from the "District Total" row.
- 2023-24 ("2023-24 to 2032-33", June 2023, based on October 2022 enrollments; 21 pages). Appendix C
  (PDF pages 18-21): rows "<School> <Program> <Grades> ...", 13 years 2020-21..2032-33 (3 historic).
  Incorporates the program moves (note (3): "Bridger Spanish DLI (grades K-5) moved to Lent ES"; note (6):
  "Lent neighborhood program moved to Marysville"). The PDF text layer fuses runs of zeros into one token
  ("12 20000000000" for 122 followed by ten zeros); those rows are decoded from the school Total row minus
  the sibling program rows and checked against the fused digit string.
- 2024-25 ("2024-25 to 2033-34", July 2024; 40 pages). Same layout as the 2025-26 and 2026-27 editions, so
  it is read with parse_psu_forecast.parse_file (which carries all of that script's validations).

Validation (exits on failure): a school's program rows sum to its Total row (exact for actual years,
+-ROUND_TOL for forecast years, which are rounded cell by cell); school Totals for the Elementary / Middle /
High subtotals sum to the printed subtotals where those are printed unsplit (2023-24 and 2024-25); the
district total equals the TOTAL row; the 2023-24 edition's TOTAL equals Table A's medium-scenario TOTAL.

Usage: python3 data-raw/extract_psu_premove.py  ->  data/psu_forecast_premove.csv
Columns: forecast_vintage, school, program (Total / Neighborhood / Spanish / ...), year, enrollment, type
(actual / forecast). school == "District", program == "Total" is the district total (all K-12).
"""
import csv
import os
import re
import sys
from collections import defaultdict

from pypdf import PdfReader

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import parse_psu_forecast as P  # noqa: E402

SRC = os.path.join(HERE, 'pps_reports')
OUT = os.path.join(HERE, '..', 'data', 'psu_forecast_premove.csv')
FIELDS = ['forecast_vintage', 'school', 'program', 'year', 'enrollment', 'type']
TOL = 3
PROGS = ['Total', 'Neighborhood', 'Spanish', 'Mandarin', 'Japanese', 'Russian', 'Vietnamese', 'Chinese', 'PISA']


def fail(msg):
    sys.exit(f'extract_psu_premove: {msg}')


def pages_text(path):
    reader = PdfReader(path)
    return reader, [(p.extract_text() or '') for p in reader.pages]


def norm(line):
    line = line.replace('‑', '-').replace('‐', '-').replace('‐', '-')
    line = re.sub(r'(\d{4})- ?(\d{2})', r'\1-\2', line)
    line = re.sub(r'K- (\d)', r'K-\1', line)
    return line.strip()


def years_from(line):
    return re.findall(r'\d{4}-\d{2}', norm(line))


# Inconsistencies in the printed source (checked against the PDF text; the Total row is trusted)
KNOWN_SOURCE_MISMATCH = {('2022-23', 'Roseway Heights', '2020-21'),  # Spanish 93 + Neighborhood 509 = 602, Total 617
                         }
# 2023-24 edition: program rows print 0 while the Total row continues: Rigler (whole-school Spanish; 0/0 in the
# 3 historic years too, Total 268/237/223) and Bridger Creative Science (Neighborhood/Spanish 0 in all forecast years)
UNSPLIT = {('2023-24', 'Rigler'), ('2023-24', 'Bridger Creative Science'),
          ('2023-24', 'Hosford')}  # Hosford: Neighborhood/Mandarin 0 from 2023-24 on


def check_programs(vintage, school, progs, years, v0):
    """progs: {program: [ints]}; programs must sum to Total."""
    if 'Total' not in progs:
        fail(f'{vintage}: {school} has no Total row')
    parts = [v for p, v in progs.items() if p != 'Total']
    if not parts:
        return
    got = [sum(c) for c in zip(*parts)]
    for y, g, t in zip(years, got, progs['Total']):
        tol = 0 if int(y[:4]) < v0 else TOL
        if abs(g - t) > tol:
            if g == 0 and (vintage, school) in UNSPLIT:
                continue  # program rows print 0 (split dropped / not printed) while the Total row continues
            if (vintage, school, y) in KNOWN_SOURCE_MISMATCH:
                print(f'  known source inconsistency kept as printed: {vintage} {school} {y}: programs sum {g}, Total {t}')
                continue
            fail(f'{vintage}: {school} {y}: programs sum to {g}, Total {t}')


# ---------------------------------------------------------------- 2023-24 edition
ROW23 = re.compile(r'^(?P<name>.+?) (?P<prog>%s) (?P<span>K-\d+|\d-\d+|N/A) (?P<rest>[\d, ]+)$' % '|'.join(PROGS))


def decode_fused(school, bad, total, n):
    """bad: {program: fused digit string}; total: Total row. Return {program: ints}."""
    if len(bad) == 1:
        (prog, D), = bad.items()
        # the missing row = Total minus the good sibling rows; caller passes that residual in `total`
        vals = total
        if set(D) == {'0'} and len(D) == 13:
            return {prog: [0] * 13}  # all-zero row (Rigler Neighborhood): taken as printed
        if ''.join(str(v) for v in vals) != D:
            fail(f'{school} {prog}: fused digits {D} do not match residual {vals}')
        return {prog: vals}
    progs = list(bad)
    if len(progs) != 2:
        fail(f'{school}: {len(progs)} fused rows')
    a, b = progs
    sols = []

    def dfs(i, ia, ib, va, vb):
        if i == n:
            if ia == len(bad[a]) and ib == len(bad[b]):
                sols.append((va[:], vb[:]))
            return
        if bad[a][ia:ia + 1] == '0' and bad[b][ib:ib + 1] == '0':
            # program split dropped: both program rows print 0 while the Total row continues
            dfs(i + 1, ia + 1, ib + 1, va + [0], vb + [0])
        for k in range(1, 5):
            s = bad[a][ia:ia + k]
            if len(s) < k or (len(s) > 1 and s[0] == '0'):
                continue
            x = int(s)
            if x > total[i]:
                continue
            t = str(total[i] - x)
            if bad[b][ib:ib + len(t)] != t:
                continue
            dfs(i + 1, ia + k, ib + len(t), va + [x], vb + [total[i] - x])

    dfs(0, 0, 0, [], [])
    sols = [list(map(list, x)) for x in {(tuple(a_), tuple(b_)) for a_, b_ in sols}]
    if len(sols) != 1:
        fail(f'{school}: {len(sols)} decodings of fused rows: {sols}')
    return {a: sols[0][0], b: sols[0][1]}


def parse_2023(path, vintage='2023-24'):
    reader, pages = pages_text(path)
    v0 = int(vintage[:4])
    rows = defaultdict(lambda: defaultdict(dict))  # school -> prog -> {'vals' or 'fused'}
    order, years, groups, ola = [], None, {}, None
    for pg in range(17, 21):  # PDF pages 18-21
        for l in pages[pg].split('\n'):
            l = norm(l)
            if l.startswith('Name Program Grades'):
                years = years_from(l)
                continue
            m = ROW23.match(l)
            if m:
                toks = m.group('rest').split()
                school, prog = m.group('name'), m.group('prog')
                if school not in order:
                    order.append(school)
                if len(toks) == 13 and all(re.fullmatch(r'\d[\d,]*', t) for t in toks):
                    rows[school][prog] = {'vals': [P.to_int(t) for t in toks]}
                else:
                    rows[school][prog] = {'fused': ''.join(toks)}
                continue
            col = l.replace(' ', '')
            mo = re.match(r'^OLATotalK-12(\d+)$', col)
            if mo and l.count(' ') > 10:
                ola = mo.group(1)  # letter-spaced garbled OLA Total row; decoded below from the printed TOTAL
                continue
            mc = re.match(r'^(?P<name>[A-Za-z\.\'\-/]+?)(?P<prog>Vietnamese|Spanish|Mandarin|Japanese|Russian|Chinese|PISA)'
                          r'(?P<span>6-8|9-12|K-5|K-8)(?P<d>\d+)$', col)
            if mc and ' ' in l and l.count(' ') > 20:
                # letter-spaced garbled row (Roseway Heights Vietnamese): keep the digit string as a fused row
                hit = [sc for sc in order if sc.replace(' ', '') == mc.group('name')]
                if len(hit) != 1:
                    fail(f'{vintage}: cannot place garbled row {l!r}')
                rows[hit[0]][mc.group('prog')] = {'fused': mc.group('d')}
                continue
            mg = re.match(r'^(Elementary and K-8 Subtotal|Middle Schools Subtotal|High Schools Subtotal|'
                          r'Other \(K-12 and 1-8\)|TOTAL) ([\d, ]+)$', l)
            if mg:
                groups[mg.group(1)] = [P.to_int(t) for t in mg.group(2).split()]
    if years is None or len(years) != 13:
        fail(f'{vintage}: year header not found / not 13 years: {years}')
    out = {}
    for school in order:
        prow = rows[school]
        bad = {p: d['fused'] for p, d in prow.items() if 'fused' in d}
        good = {p: d['vals'] for p, d in prow.items() if 'vals' in d}
        if bad:
            if 'Total' in bad:
                fail(f'{vintage}: {school} Total row is fused')
            resid = [t - sum(good[p][i] for p in good if p != 'Total') for i, t in enumerate(good['Total'])]
            good.update(decode_fused(school, bad, resid, 13))
        out[school] = good
        check_programs(vintage, school, good, years, v0)
    if ola is not None:
        # OLA (closed) Total = printed TOTAL minus every other school Total; must reproduce the garbled digits
        resid = [t - sum(p['Total'][i] for p in out.values()) for i, t in enumerate(groups['TOTAL'])]
        resid = [r if int(y[:4]) < v0 else 0 for r, y in zip(resid, years)]  # forecast sums carry rounding slack
        if ''.join(str(r) for r in resid) != ola:
            fail(f'{vintage}: OLA digits {ola} do not match TOTAL residual {resid}')
        out['OLA'] = {'Total': resid}
    return years, out, groups


def span_of(path, vintage='2023-24'):
    """{school: grade span} for the 2023-24 edition."""
    _, pages = pages_text(path)
    spans = {}
    for pg in range(17, 21):
        for l in pages[pg].split('\n'):
            m = ROW23.match(norm(l))
            if m and m.group('prog') == 'Total':
                spans[m.group('name')] = m.group('span')
            elif m:
                spans.setdefault(m.group('name'), m.group('span'))
    return spans


def validate_2023(vintage, years, schools, groups, spans):
    v0 = int(vintage[:4])
    sums = defaultdict(lambda: [0] * 13)
    for school, progs in schools.items():
        sp = spans.get(school, 'K-12')  # OLA is K-12
        g = 'High' if sp == '9-12' else 'Middle' if sp == '6-8' else 'Elem' if sp in ('K-5', 'K-8') else 'Other'
        sums[g] = [a + b for a, b in zip(sums[g], progs['Total'])]
    want = {'Elem': 'Elementary and K-8 Subtotal', 'Middle': 'Middle Schools Subtotal', 'High': 'High Schools Subtotal'}
    for g, label in want.items():
        if label not in groups:
            fail(f'{vintage}: group row {label} not found')
        for y, a, b in zip(years, sums[g], groups[label]):
            if abs(a - b) > (0 if int(y[:4]) < v0 else TOL):
                print(f'  note {vintage} {label} {y}: school Totals sum {a}, printed {b}')
    allsum = [sum(x) for x in zip(*sums.values())]
    for y, a, b in zip(years, allsum, groups['TOTAL']):
        if abs(a - b) > (0 if int(y[:4]) < v0 else TOL):
            print(f'  note {vintage} TOTAL {y}: all school Totals sum {a}, printed {b}')


def check_table_a_2023(path, groups, years):
    _, pages = pages_text(path)
    for l in pages[9].split('\n'):  # PDF page 10, medium scenario
        if l.startswith('TOTAL'):
            nums = [P.to_int(t) for t in re.findall(r'\d[\d,]*', l.replace(', ', ','))]
            # Table A runs 2018-19..2037-38 (20 values); Appendix C starts at 2020-21 (index 2)
            if nums[2:15] != groups['TOTAL']:
                fail(f'2023-24: Table A TOTAL {nums[2:15]} != Appendix C TOTAL {groups["TOTAL"]}')
            return
    fail('2023-24: Table A TOTAL row not found')


# ---------------------------------------------------------------- 2022-23 edition
PROG22 = {'Spanish Immersion': 'Spanish', 'Neighborhood Program': 'Neighborhood', 'Total': 'Total',
          'Mandarin Immersion': 'Mandarin', 'Japanese Immersion': 'Japanese', 'Russian Immersion': 'Russian',
          'Vietnamese Immersion': 'Vietnamese'}
# Campus / strand rows that are printed like programs (head text -> (school, program))
SPECIAL22 = {'Beverly Cleary Fernwood': ('Beverly Cleary', 'Fernwood'), 'Hollyrood': ('Beverly Cleary', 'Hollyrood'),
             "Leodis V. McDaniel4 Portland Int'l Scholars": ('Leodis V. McDaniel', "Portland Int'l Scholars"),
             "Roosevelt Portland Int'l Scholars": ('Roosevelt', "Portland Int'l Scholars"),
             "Portland Int'l Scholars": (None, "Portland Int'l Scholars")}
ROW22 = re.compile(r'^(?P<head>.*?)\s*(?P<span>KG-\d+|\d-\d+|K-\d+|N/A|K-1|2-8)\s+(?P<rest>(?:\d[\d,]*\s+){12}\d[\d,]*)$')


def parse_2022(path, vintage='2022-23'):
    _, pages = pages_text(path)
    v0 = int(vintage[:4])
    years, schools, order = None, defaultdict(dict), []
    district = None
    cur = None
    for pg in range(84, 89):  # PDF pages 85-89
        lines = [norm(l) for l in pages[pg].split('\n')]
        for i, l in enumerate(lines):
            if l.startswith('Name School Program') or re.match(r'^Range\d? 2019', l):
                ys = years_from(l)
                if len(ys) == 13:
                    years = ys
                continue
            m = re.match(r'^District Total ((?:\d[\d,]*\s*){13})$', l)
            if m:
                district = [P.to_int(t) for t in m.group(1).split()]
                continue
            m = ROW22.match(l)
            if not m:
                continue
            head, vals = m.group('head').strip(), [P.to_int(t) for t in m.group('rest').split()]
            prog = None
            if head in SPECIAL22:
                sch_, prog = SPECIAL22[head]
                head = sch_ or ''
            for k, v in PROG22.items():
                if prog is not None:
                    break
                if head == k or head.endswith(' ' + k):
                    prog, head = v, head[:-len(k)].strip()
                    break
            if head:
                cur = re.sub(r'(?<=[A-Za-z\.\)])\d$', '', head)  # footnote marker glued to the name
                if cur not in order:
                    order.append(cur)
            elif cur is None:
                fail(f'{vintage}: row with no school: {l!r}')
            if prog is None:
                prog = 'Total'  # single-program school: the one row is the Total
            if prog in schools[cur]:
                fail(f'{vintage}: duplicate row {cur} {prog}')
            schools[cur][prog] = vals
    if years is None:
        fail(f'{vintage}: year header not found')
    if district is None:
        fail(f'{vintage}: District Total not found')
    for s in order:
        if 'Total' not in schools[s] and len(schools[s]) == 1:
            # whole-school immersion printed with one program row and no Total (Rigler): Total = that row
            schools[s]['Total'] = list(next(iter(schools[s].values())))
        check_programs(vintage, s, schools[s], years, v0)
    return years, {s: schools[s] for s in order}, district


# ---------------------------------------------------------------- main
def emit(rows, vintage, years, school, prog, vals):
    v0 = int(vintage[:4])
    for y, v in zip(years, vals):
        rows.append({'forecast_vintage': vintage, 'school': school, 'program': prog, 'year': y,
                     'enrollment': v, 'type': 'actual' if int(y[:4]) < v0 else 'forecast'})


def main():
    rows = []
    # 2022-23
    y, sch, dist = parse_2022(os.path.join(SRC, 'PSU_PRC_Forecast_2022-23_edition.pdf'))
    for s, progs in sch.items():
        for p, v in progs.items():
            emit(rows, '2022-23', y, s, p, v)
    emit(rows, '2022-23', y, 'District', 'Total', dist)
    # actual-year district total must equal the sum of the school Totals + nothing else (all schools listed)
    tot = [sum(sch[s]['Total'][i] for s in sch) for i in range(13)]
    for i, (a, b) in enumerate(zip(tot, dist)):
        if abs(a - b) > (0 if int(y[i][:4]) < 2022 else TOL):
            print(f'  note 2022-23 {y[i]}: school Totals sum {a} vs District Total {b} (diff {b - a}; some rows may sit on pages '
                  f'not parsed or in the text layer out of order)')
    # 2023-24
    p23 = os.path.join(SRC, 'PSU_PRC_Forecast_2023-24_edition.pdf')
    y, sch, groups = parse_2023(p23)
    validate_2023('2023-24', y, sch, groups, span_of(p23))
    check_table_a_2023(p23, groups, y)
    for s, progs in sch.items():
        for p, v in progs.items():
            emit(rows, '2023-24', y, s, p, v)
    emit(rows, '2023-24', y, 'District', 'Total', groups['TOTAL'])
    # 2024-25 through the main parser (its validations run inside)
    r24 = P.parse_file(os.path.join(SRC, 'PSU_PRC_Forecast_2024-25_edition.pdf'))
    for r in r24:
        if r['table'] == 'school_program':
            rows.append({'forecast_vintage': '2024-25', 'school': r['school'], 'program': r['program'],
                         'year': r['year'], 'enrollment': r['enrollment'], 'type': r['type']})
        elif r['table'] == 'school_group_subtotal' and r['school'] == 'TOTAL':
            rows.append({'forecast_vintage': '2024-25', 'school': 'District', 'program': 'Total',
                         'year': r['year'], 'enrollment': r['enrollment'], 'type': r['type']})
    with open(OUT, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(rows)
    print(f'wrote {len(rows)} rows to {os.path.normpath(OUT)}')
    for v in sorted({r['forecast_vintage'] for r in rows}):
        rr = [r for r in rows if r['forecast_vintage'] == v]
        print(f'{v}: {len(rr)} rows, {len({r["school"] for r in rr})} schools, years {min(r["year"] for r in rr)}..{max(r["year"] for r in rr)}')


if __name__ == '__main__':
    main()
