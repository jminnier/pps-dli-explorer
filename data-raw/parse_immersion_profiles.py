"""Parse PPS "Enrollment Details for Language Immersion Schools" PDFs into one CSV.

Source PDFs (data-raw/pps_reports/*_Language_Immersion_Track_Profiles.pdf) come from
https://www.pps.net/departments/dataaccountability/data-and-accountability/data-strategy-and-insights/data-and-reporting
and its historical archive (https://www.pps.net/fs/pages/46482).

Each school is two lines: counts, then percentages of total enrollment. In the 2021-22 and
2022-23 files the text layer runs adjacent numbers together ("0000"), so counts are recovered
by splitting digit runs so that every count matches its printed percentage and the row sums
(immersion languages = total immersion, ML languages = ML total) hold.

The last column is headed "Percent of ML in Immersion (Both ML and Imm / ML)", but the printed
values are both / total immersion (Ainsworth 2025: 38 / 287 = 13%, while 38 / 59 = 64%), so it is
stored as pct_immersion_ml: the share of immersion students who are multilingual learners.

Usage: python3 data-raw/parse_immersion_profiles.py  ->  data/dli_track_profiles.csv
"""
import csv
import glob
import itertools
import os
import re
import sys

from pypdf import PdfReader

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'data', 'dli_track_profiles.csv')

# Count columns in PDF order. "ml" = multilingual learners (older files say LEP/ELL).
COLS = ['enrollment', 'ml_or_immersion', 'neither', 'immersion_total',
        'imm_spanish', 'imm_mandarin', 'imm_japanese', 'imm_russian', 'imm_vietnamese',
        'ml_total', 'ml_spanish', 'ml_chinese', 'ml_japanese', 'ml_russian', 'ml_vietnamese',
        'ml_somali', 'ml_other', 'ml_and_immersion']
TOL = 0.51  # percentages are printed rounded to whole numbers


def splits(tokens, n):
    """All ways to cut the digit tokens into n non-negative integers (no leading zeros)."""
    if not tokens:
        if n == 0:
            yield []
        return
    first, rest = tokens[0], tokens[1:]
    for k in range(1, min(len(first), n) + 1):
        for parts in _cut(first, k):
            for tail in splits(rest, n - k):
                yield parts + tail


def _cut(s, k):
    if k == 1:
        if s == '0' or not s.startswith('0'):
            yield [int(s)]
        return
    for i in range(1, len(s) - k + 2):
        head = s[:i]
        if head != '0' and head.startswith('0'):
            continue
        for tail in _cut(s[i:], k - 1):
            yield [int(head)] + tail


ML_LANGS = slice(10, 17)  # ml_spanish .. ml_other


def readings(v, pcts, pct_imm_ml, check_ml_langs=True):
    """Column assignments of one split that fit the percentages and row sums.

    The ML-language columns are matched by percentage rather than position: in the 2021-22 file
    the text layer sometimes lists them out of order (Beach: counts read Somali 11, Other 1, but
    the percentage row has Somali 0%, Other 3%)."""
    enroll = v[0]
    if enroll == 0 or v[3] != sum(v[4:9]):
        return []
    if v[1] != v[3] + v[9] - v[17] or v[2] != enroll - v[1]:
        return []
    if v[3] and abs(100 * v[17] / v[3] - pct_imm_ml) > TOL:
        return []
    fits = lambda x, p: abs(100 * x / enroll - p) <= TOL
    fixed = [i for i in range(1, len(COLS)) if not ML_LANGS.start <= i < ML_LANGS.stop]
    if not all(fits(v[i], pcts[i - 1]) for i in fixed):
        return []
    if not check_ml_langs:
        return [tuple(v[:ML_LANGS.start]) + ('',) * (ML_LANGS.stop - ML_LANGS.start) + tuple(v[ML_LANGS.stop:])]
    if v[9] != sum(v[ML_LANGS]):
        return []
    out = set()
    for perm in set(itertools.permutations(v[ML_LANGS])):
        if all(fits(x, pcts[i - 1]) for i, x in zip(range(ML_LANGS.start, ML_LANGS.stop), perm)):
            out.add(tuple(v[:ML_LANGS.start]) + perm + tuple(v[ML_LANGS.stop:]))
    return list(out)


def parse_file(path):
    year = re.match(r'(\d{4}-\d{2})', os.path.basename(path)).group(1)
    lines = [l.strip() for p in PdfReader(path).pages for l in (p.extract_text() or '').split('\n')]
    rows = []
    is_pct = lambda l: re.match(r'^[\d%\s]+$', l) and '%' in l
    for i, line in enumerate(lines):
        m = re.match(r'^(\D+?)\s+(\d[\d\s]*?)\s+(\d+)%$', line)
        # the percentage line can land on the next page, after its title and column headers
        pct_line = next((l for l in lines[i + 1:i + 60] if is_pct(l)), None) if m else None
        if not pct_line:
            continue
        name, digits, pct_imm_ml = m.group(1).strip(), m.group(2).split(), int(m.group(3))
        pcts = [int(x) for x in re.findall(r'(\d+)%', pct_line)]
        if len(pcts) != len(COLS) - 1:
            sys.exit(f'{year} {name}: expected {len(COLS) - 1} percentages, got {len(pcts)}')
        found = {r for v in splits(digits, len(COLS)) for r in readings(v, pcts, pct_imm_ml)}
        if not found:
            # The text layer's ML-language counts don't add up (César Chávez 2021-22: 162 vs an ML
            # total of 189); keep the checked core columns and leave the language split blank.
            found = {r for v in splits(digits, len(COLS)) for r in readings(v, pcts, pct_imm_ml, False)}
            print(f'{year} {name}: ML language counts inconsistent in source; left blank', file=sys.stderr)
        if not found:
            sys.exit(f'{year} {name}: no consistent reading of {digits}')
        # Columns on which the readings disagree are left blank rather than guessed.
        values = [vals.pop() if len(vals := {r[i] for r in found}) == 1 else '' for i in range(len(COLS))]
        if any(values[i] == '' for i in range(len(COLS)) if not ML_LANGS.start <= i < ML_LANGS.stop):
            sys.exit(f'{year} {name}: ambiguous core columns {values}')
        rows.append({'year': year, 'school': name, **dict(zip(COLS, values)), 'pct_immersion_ml': pct_imm_ml})
    return rows


def main():
    files = sorted(glob.glob(os.path.join(HERE, 'pps_reports', '*_Language_Immersion_Track_Profiles.pdf')))
    rows = [r for f in files for r in parse_file(f)]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w', newline='', encoding='utf-8') as fh:
        w = csv.DictWriter(fh, fieldnames=['year', 'school', *COLS, 'pct_immersion_ml'])
        w.writeheader()
        w.writerows(rows)
    for f in files:
        y = re.match(r'(\d{4}-\d{2})', os.path.basename(f)).group(1)
        print(y, sum(r['year'] == y for r in rows), 'schools')
    print('wrote', os.path.relpath(OUT))


if __name__ == '__main__':
    main()
