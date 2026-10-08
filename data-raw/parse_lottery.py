"""Parse six years of PPS school-choice lottery result summaries into one tidy CSV.

Source PDFs (data-raw/pps_lottery/*.pdf) come from
https://www.pps.net/departments/enrollment-transfer/transfer-english/lottery/prior-transfer-data
Files: 2021-22 .. 2025-26 Elementary and Middle/High School, 2026-27 Kindergarten, 2026-27
Middle/High School, 2026-27 Focus Option and MLC Grades 1-5.

Output data/lottery_results.csv: one row per year x school x program x grade x applicant group.
`year` is the school year the lottery placed students into (the lottery is held the winter before).
`level` comes from the grade (K-5 ES, 6-8 MS, 9-12 HS), not from the file; school Total rows
without a grade take the level of their group rows. `is_total` rows are the report's own school
total rows: keep the group rows OR the total rows, never both. Columns a report does not print
are blank. Report wording differs by year and is mapped as:
  Slots (seats)                                  -> slots (2021-22, 2023-24, MS/HS 2021-23)
  Offered / Placed / Slots Filled                -> offered (2024-25 and 2025-26 say "Slots
                                                    Filled", defined as offers)
  Applicants / Applications / Total Applicants   -> applications
  Canceled / Placed to higher choice             -> cancelled
  Not Placed / Not Offered (waitlist was full)   -> not_placed
Extra descriptive columns: `program_type` (Dual Language Immersion, Focus Option, Alternative,
Focus Option / Alternative for MS/HS) and `group` (applicant-group label exactly as printed).
`residence` is NH/TR/RG (Regional) and `background` English/Heritage/Native. In 2021-24 the
printed "Native English" is stored as English and "Native <language>" as Native. Labels that are
neither (MLK's Albina, Current King, NH-TR, Neighborhood-Transfer) go to `background` as printed.

Layout quirks, per file
- 2021-22 Elementary: plain text is in order. Block header "<School> Slots Applicants Offered
  Waitlisted Canceled Not Placed", then grade lines (focus options) or group lines
  ("NH Native Spanish"). The MLK block sits under the "Russian Immersion" heading although its rows
  are Chinese; language therefore comes from SCHOOL_LANG and heading conflicts are printed.
- 2022-23 Elementary: empty cells are omitted from the text layer, so columns are recovered from
  x positions. School name only on a school's first row; MLK's name wraps onto its own line before
  "Total". The MLK total includes its grade-1 row.
- 2023-24 Elementary: complete cells (Slots Offered Waitlisted Canceled Applications). The MLK
  grade-1 row prints after the Total row and is not part of it.
- 2024-25 Elementary: one very tall sheet whose y axis points down, so reading order is increasing
  y; the school name precedes its column header; numeric grade rows start with the grade. "Slots
  Filled" is offers. No school totals are printed.
- 2025-26 Elementary: Buckman grades 1-5 are printed in a different column order than their header
  (see fix_misordered_columns). Page 1 has two side-by-side columns (Focus Option left, Alternative right,
  split at x=300). Title text and page numbers are interleaved with school names; a school's rows
  can continue on the next page without its name. No school totals are printed.
- 2026-27 Kindergarten: section headings and school names come late in the plain text; reading by
  position fixes it. Header precedes the school name; each school has a "<School> Total" row. No
  slots column. Rigler is absent.
- 2026-27 Focus Option and MLC Grades 1-5: MLC and five focus options only (no immersion); y axis
  points down (reading order = increasing y); the school Total row precedes its grade rows.
- Middle/High School 2021-22 .. 2023-24: plain text; 2021-22 school rows omit slots. 2024-25
  .. 2026-27: empty cells are omitted so columns come from right edges. 2024-25 also has a
  "Dual Language Immersion by School Locations" table (offers go out in February, none printed).

Validation (exits on failure): group rows sum to the printed school Total per column wherever a
total exists (all grades, else kindergarten rows only); printed Grand Totals equal the sum of
school totals where positions allow; every immersion school must be in SCHOOL_LANG, which is
checked against data/dli_sites.csv. The identity applications = offered + waitlisted + cancelled
(+ not_placed) is tested on every row with those columns and violations are printed (not fatal:
it is a property of the report).

Usage: python3 data-raw/parse_lottery.py  ->  data/lottery_results.csv
"""
import csv
import os
import re
import sys
from collections import Counter, defaultdict

from pypdf import PdfReader

HERE = os.path.dirname(os.path.abspath(__file__))
PDF_DIR = os.path.join(HERE, 'pps_lottery')
OUT = os.path.join(HERE, '..', 'data', 'lottery_results.csv')
PROFILES = os.path.join(HERE, '..', 'data', 'dli_track_profiles.csv')
SITES = os.path.join(HERE, '..', 'data', 'dli_sites.csv')

FIELDS = ['year', 'level', 'school', 'pps_school', 'program_type', 'program', 'language', 'grade',
          'residence', 'background', 'group', 'slots', 'applications', 'offered', 'waitlisted',
          'cancelled', 'not_placed', 'is_total', 'source_file']
COUNTS = ['slots', 'applications', 'offered', 'waitlisted', 'cancelled', 'not_placed']

# Language of each school's elementary immersion program (checked against data/dli_sites.csv).
SCHOOL_LANG = {
    'Ainsworth': 'Spanish', 'Atkinson': 'Spanish', 'Beach': 'Spanish', 'Bridger': 'Spanish',
    'César Chávez': 'Spanish', 'James John': 'Spanish', 'Lent': 'Spanish', 'Scott': 'Spanish',
    'Sitton': 'Spanish', 'Clark': 'Mandarin', 'Harrison Park': 'Mandarin', 'MLK Jr': 'Mandarin',
    'Woodstock': 'Mandarin', 'Richmond': 'Japanese', 'Kelly': 'Russian',
    'Rose City Park': 'Vietnamese'}
SECTION_LANG = {'chinese': 'Mandarin', 'japanese': 'Japanese', 'russian': 'Russian',
                'vietnamese': 'Vietnamese', 'vietmanese': 'Vietnamese', 'spanish': 'Spanish'}
PROGRAM_OF = {'Spanish': 'Spanish Immersion', 'Mandarin': 'Mandarin Immersion',
              'Japanese': 'Japanese Immersion', 'Russian': 'Russian Immersion',
              'Vietnamese': 'Vietnamese Immersion'}
DLI = 'Dual Language Immersion'
MSHS = 'Focus Option / Alternative'
DLI_LOC = 'Dual Language Immersion (by school location)'
CANON = {'cesar chavez': 'César Chávez', 'martin luther king jr': 'MLK Jr', 'mlk': 'MLK Jr',
         'leodis v. mcdaniel': 'McDaniel'}
DIGIT_W = 5.5  # width of one digit in the right-aligned MS/HS tables

ROWS = []
CHECKS = Counter()
WARNINGS = []


def fail(msg):
    sys.exit(f'parse_lottery: {msg}')


def warn(msg):
    if msg not in WARNINGS:
        WARNINGS.append(msg)


# ---------------------------------------------------------------- names, groups, rows
def profile_rows():
    with open(PROFILES, encoding='utf-8') as fh:
        return list(csv.DictReader(fh))


PROFILE_ROWS = profile_rows()
PROFILE_NAMES = {r['school'] for r in PROFILE_ROWS}


def pps_name(raw):
    """Name used in data/dli_track_profiles.csv, or '' when the school is not one of those."""
    s = re.sub(r'\s*\(continued\)', '', raw).strip()
    s = re.sub(r'^Dr\.\s+', '', s)
    s = re.sub(r'\s+(M\.S\.|H\.S\.|K-8|School)$', '', s).strip().rstrip('.')
    name = CANON.get(s.lower(), s)
    return name if name in PROFILE_NAMES else ''


def parse_group(label):
    """(residence, background) from an applicant-group label; unknown labels stay as printed."""
    label = (label or '').strip()
    if not label:
        return '', ''
    toks = [t for t in re.split(r'[\s\-]+', label) if t]
    res = {'NH': 'NH', 'TR': 'TR', 'RG': 'RG', 'REGIONAL': 'RG'}
    residence = res.get(toks[0].upper(), '') if len(toks) > 1 else ''
    rest = toks[1:] if residence else toks
    if len(rest) == 2 and rest[0].lower() == 'native':
        return residence, 'English' if rest[1].lower() == 'english' else 'Native'
    if len(rest) == 1 and rest[0].lower() in ('english', 'heritage', 'native'):
        return residence, rest[0].capitalize()
    return '', label  # Albina, Current King, NH-TR, Neighborhood-Transfer ... as printed


def norm_grade(g):
    g = str(g).strip().rstrip('*').lower()
    if g in ('k', 'kg', 'kindergarten'):
        return 'K'
    m = re.match(r'^(\d{1,2})(st|nd|rd|th)?( grade)?$', g)
    return str(int(m.group(1))) if m else ''


def level_of(grade, default=''):
    if grade == 'K':
        return 'ES'
    if grade.isdigit():
        return 'ES' if int(grade) <= 5 else 'MS' if int(grade) <= 8 else 'HS'
    return default


def add(year, source, school, ptype, program, language, grade, label='', total=False,
        default_level='', **counts):
    grade = norm_grade(grade) if grade != '' else ''
    residence, background = parse_group(label)
    row = dict.fromkeys(FIELDS, '')
    row.update(year=year, level=level_of(grade, default_level),
               school=re.sub(r'\s*\(continued\)', '', school).strip(), pps_school=pps_name(school),
               program_type=ptype, program=program, language=language, grade=grade,
               residence=residence, background=background, group=label.strip(),
               is_total='TRUE' if total else 'FALSE', source_file=source)
    for k, v in counts.items():
        if v is not None:
            row[k] = int(v)
    ROWS.append(row)
    return row


def immersion_lang(school, section_lang, year):
    """Language of an immersion school (SCHOOL_LANG), cross-checked with the section heading."""
    name = pps_name(school)
    if name not in SCHOOL_LANG:
        fail(f'{year}: immersion school {school!r} is not in SCHOOL_LANG')
    lang = SCHOOL_LANG[name]
    if section_lang and section_lang != lang:
        warn(f'{year} {school}: printed under the {section_lang} heading but its rows are {lang}')
    return lang


class Section:
    """Program type and language from section heading lines."""
    HEAD = re.compile(r'^(?:(Dual (?:Language )?Immersion)|(Focus Options?(?: Program)?)'
                      r'|((?:PPS )?Alternative(?: Program)?)'
                      r'|(Chinese|Japanese|Russian|Vietnamese|Vietmanese|Spanish)(?: Immersion)?)'
                      r'(?: \(continued\))?\s*$', re.I)

    def __init__(self):
        self.ptype = ''
        self.lang = ''

    def feed(self, text):
        m = self.HEAD.match(text.strip())
        if not m:
            return False
        if m.group(1):
            self.ptype, self.lang = DLI, ''
        elif m.group(2):
            self.ptype, self.lang = 'Focus Option', ''
        elif m.group(3):
            self.ptype, self.lang = 'Alternative', ''
        else:
            self.ptype, self.lang = DLI, SECTION_LANG[m.group(4).lower()]
        return True


def emit(year, src, school, sec, grade, label, total, default_level='', **counts):
    """Add a row for a school in the current section; immersion rows get language and program."""
    if sec.ptype == DLI:
        lang = immersion_lang(school, sec.lang, year)
        return add(year, src, school, DLI, PROGRAM_OF[lang], lang, grade, label, total,
                   default_level, **counts)
    if not school:
        fail(f'{year}: row {counts} has no school')
    return add(year, src, school, sec.ptype or 'Other', re.sub(r'\s*\(continued\)', '', school).strip(),
               '', grade, label, total, default_level, **counts)


# ---------------------------------------------------------------- reading PDFs
def fragments(path, page):
    out = []

    def visit(text, cm, tm, fd, fs):
        if text.strip():
            out.append((round(tm[5], 1), round(tm[4], 1), text.strip()))
    PdfReader(path).pages[page].extract_text(visitor_text=visit)
    return out


TITLE_WORDS = {'Elementary', 'Schools', 'School', 'Lottery', 'Results', 'Summary', 'Page', '-'}


def merge_split_words(toks):
    """Rejoin words the PDF split at a kerning gap ("B"+"uckman", "Alternat"+"ive")."""
    out = []
    for x, t in toks:
        if out and len(t) > 1 and t[0].islower() and t.isalpha() and out[-1][1][-1].isalpha() \
                and x - out[-1][0] <= 6.2 * len(out[-1][1]):
            out[-1] = (out[-1][0], out[-1][1] + t)
        else:
            out.append((x, t))
    return out


def read_lines(path, page, ascending=False, tol=1.5):
    """Visual lines [(y, [(x, text)])] in reading order, with titles, page numbers and dates removed."""
    frs = sorted(fragments(path, page), key=lambda r: (r[0] if ascending else -r[0], r[1]))
    lines = []
    for y, x, t in frs:
        if lines and abs(lines[-1][0] - y) <= tol:
            lines[-1][1].append((x, t))
        else:
            lines.append([y, [(x, t)]])
    out = []
    for y, toks in lines:
        toks = merge_split_words(sorted(toks))
        if 'Lottery Results' in ' '.join(t for _, t in toks):
            toks = [(x, t) for x, t in toks if 'Lottery Results' not in t and t not in TITLE_WORDS
                    and not re.fullmatch(r'\d{1,4}', t)]
        # print dates, and page numbers that the tall 2024-25 and 1-5 sheets put at x >= 770
        toks = [(x, t) for x, t in toks if not re.fullmatch(r'\d{1,2}/\d{1,2}/\d{4}', t)
                and not (x >= 770 and re.fullmatch(r'\d{1,2}', t))]
        if toks:
            out.append((y, toks))
    return out


def text_lines(path):
    """Plain extract_text lines, stripped, for the files whose text layer is already in order."""
    for p in PdfReader(path).pages:
        for l in (p.extract_text() or '').split('\n'):
            if l.strip():
                yield l.strip()


def ltext(toks):
    return re.sub(r'K\s*-\s*8', 'K-8', ' '.join(t for _, t in toks)).strip()


def split_row(text, n):
    """(label, numbers) when `text` ends in exactly n numbers and its label has no digits."""
    toks = text.split()
    if len(toks) < n or not all(re.fullmatch(r'\d+\*?', t) for t in toks[-n:]):
        return None
    label = ' '.join(toks[:len(toks) - n])
    if re.search(r'\d', label.replace('K-8', '')):
        return None
    return label, [int(t.rstrip('*')) for t in toks[-n:]]


# ---------------------------------------------------------------- 2021-22 elementary
def parse_2021_22_elem(path):
    year, src = '2021-22', os.path.basename(path)
    sec, school = Section(), ''
    for text in text_lines(path):
        if sec.feed(text):
            continue
        m = re.match(r'^(.+?) Slots Applicants Offered Waitlisted Canceled Not Placed$', text)
        if m:
            school = m.group(1)
            continue
        r = split_row(text, 6)
        if r and school:
            label, n = r
            grade = norm_grade(label)
            if not grade and label.endswith('Total'):
                fail(f'{src}: unexpected total row {text!r}')
            emit(year, src, school, sec, grade, '' if grade else label, False, default_level='ES',
                 slots=n[0], applications=n[1], offered=n[2], waitlisted=n[3], cancelled=n[4],
                 not_placed=n[5])


# ---------------------------------------------------------------- 2022-23 elementary
def parse_2022_23_elem(path):
    year, src = '2022-23', os.path.basename(path)
    sec, school, pending = Section(), '', ''
    for p in range(len(PdfReader(path).pages)):
        for _, toks in read_lines(path, p):
            text = ltext(toks)
            if sec.feed(text) or text.startswith('School Group Grade'):
                continue
            data = [(x, t) for x, t in toks if x >= 255 and re.fullmatch(r'\d+', t)]
            gr = [t for x, t in toks if 205 <= x < 235]
            name = ' '.join(t for x, t in toks if x < 97)
            group = ' '.join(t for x, t in toks if 97 <= x < 205)
            if not data and not gr:
                if name.split()[-1:] != ['Total'] and re.fullmatch(r'[A-Za-z. ]+', text):
                    pending = text  # e.g. MLK's wrapped name before its Total line
                continue
            total = name.split()[-1:] == ['Total']
            if total:
                school = name[:-5].strip() or pending or school
            elif name:
                school = name
            vals = dict.fromkeys(['offered', 'waitlisted', 'not_placed', 'cancelled', 'applications'], 0)
            for x, t in data:
                col = ('offered' if x < 305 else 'waitlisted' if x < 380 else 'not_placed' if x < 440
                       else 'cancelled' if x < 500 else 'applications')
                vals[col] = int(t)
            emit(year, src, school, sec, gr[0] if gr else '', group, total, default_level='ES', **vals)
            pending = ''


# ---------------------------------------------------------------- name-before-header formats
def parse_header_first(path, year, counts_after_grade, ascending=False, split_page0_at=None):
    """2023-24, 2024-25, 2025-26 elementary: <school> / header / rows '<label> <grade> n n n n'.

    counts_after_grade lists the numeric columns that follow the grade."""
    src = os.path.basename(path)
    n_num = len(counts_after_grade)
    states = {}
    for p in range(len(PdfReader(path).pages)):
        lines = read_lines(path, p, ascending)
        streams = {'main': lines}
        if split_page0_at and p == 0:
            # a header printed once across both columns ("Grade ... Cancelled Grade ... Cancelled")
            # belongs to both
            streams = {k: [(y, [(x, t) for x, t in toks
                                if (x < split_page0_at) == (k == 'L') or t.count('Grade') == 2])
                           for y, toks in lines] for k in ('L', 'R')}
        for key, slines in streams.items():
            st = states.setdefault(key, {'sec': Section(), 'school': '', 'name': ''})
            for _, toks in slines:
                text = ltext(toks)
                if not text or st['sec'].feed(text):
                    continue
                if re.match(r'^(Group )?Grade\b.*(Slots|Offered)', text):
                    st['school'] = st['name']
                    continue
                cnt = lambda nums: dict(zip(counts_after_grade, nums))
                r = split_row(text, n_num + 1)
                kg = re.match(r'^(.*?)\s*\bKG((?:\s+\d+){%d})$' % n_num, text)
                if r:
                    emit(year, src, st['school'], st['sec'], str(r[1][0]), r[0], False,
                         default_level='ES', **cnt(r[1][1:]))
                elif kg:
                    emit(year, src, st['school'], st['sec'], 'K', kg.group(1), False,
                         default_level='ES', **cnt([int(v) for v in kg.group(2).split()]))
                elif re.fullmatch(r'Total(\s+\d+){%d}' % n_num, text):
                    emit(year, src, st['school'], st['sec'], '', '', True, default_level='ES',
                         **cnt([int(v) for v in text.split()[1:]]))
                elif not re.search(r'\d', text.replace('K-8', '')):
                    st['name'] = re.sub(r'\s*\(continued\)', '', text).strip()


# ---------------------------------------------------------------- 2026-27 kindergarten and grades 1-5
def parse_2026_27_k(path):
    year, src = '2026-27', os.path.basename(path)
    sec, school = Section(), ''
    for p in range(len(PdfReader(path).pages)):
        for _, toks in read_lines(path, p):
            text = ltext(toks)
            if sec.feed(text) or re.match(r'^(Group|Grade) Offered', text):
                continue
            r = split_row(text, 4)
            if r:
                label, n = r
                cnt = dict(zip(['offered', 'waitlisted', 'cancelled', 'applications'], n))
                if label.endswith(' Total'):
                    emit(year, src, school, sec, '', '', True, default_level='ES', **cnt)
                elif label == 'Kindergarten':
                    emit(year, src, school, sec, 'K', '', False, default_level='ES', **cnt)
                else:
                    emit(year, src, school, sec, 'K', label, False, default_level='ES', **cnt)
            elif not re.search(r'\d', text.replace('K-8', '')):
                school = re.sub(r'\s*\(continued\)', '', text).strip()


def parse_2026_27_focus(path):
    year, src = '2026-27', os.path.basename(path)
    sec, school = Section(), ''
    seen = 0
    for p in range(len(PdfReader(path).pages)):
        for _, toks in read_lines(path, p, ascending=True):
            text = ltext(toks)
            if sec.feed(text) or re.match(r'^Grade Offered', text) or text == 'Key Definitions':
                continue
            g = re.match(r'^Grade (\d)((?:\s+\d+){4})$', text)
            t = split_row(text, 4)
            if g:
                n = [int(v) for v in g.group(2).split()]
                emit(year, src, school, sec, g.group(1), '', False, default_level='ES',
                     **dict(zip(['offered', 'waitlisted', 'cancelled', 'applications'], n)))
                seen += 1
            elif t and t[0].endswith(' Total'):
                emit(year, src, school, sec, '', '', True, default_level='ES',
                     **dict(zip(['offered', 'waitlisted', 'cancelled', 'applications'], t[1])))
            elif not re.search(r'\d', text):
                if not school or text.split()[0] not in ('Offers', 'Waitlisted', 'Canceled', 'becomes', 'choice.'):
                    school = text
    if not seen:
        fail(f'{src}: no grade rows found')


# ---------------------------------------------------------------- middle / high school
def mshs_row(year, src, school, ptype, grade, total, program=None, **counts):
    return add(year, src, school, ptype, program or school, '', grade, '', total, **counts)


def parse_mshs_2021_22(path):
    year, src = '2021-22', os.path.basename(path)
    section, school = '', ''
    for text in (ltext(t) for _, t in read_lines(path, 0)):  # headings are late in the plain text
        if text in ('High Schools', 'Middle Schools'):
            section = text
            continue
        nums = text.split()
        if not section or not nums or not re.fullmatch(r'\d+', nums[-1]):
            continue
        hs = section == 'High Schools'
        cols = (['slots', 'applications', 'offered', 'cancelled'] if hs else
                ['slots', 'applications', 'offered', 'waitlisted', 'cancelled', 'not_placed'])
        if all(re.fullmatch(r'\d+', t) for t in nums) and len(nums) == len(cols) + 1:
            mshs_row(year, src, school, MSHS, nums[0], False, program=f'{school} ({section[:-1]})',
                     **dict(zip(cols, map(int, nums[1:]))))
            continue
        r = split_row(text, len(cols) - 1)
        if r and r[0] == 'Total':
            continue  # district total
        if r and r[0]:
            school = r[0]
            mshs_row(year, src, school, MSHS, '', True, program=f'{school} ({section[:-1]})',
                     **dict(zip(cols[1:], r[1])))


def parse_mshs_2022_23(path):
    year, src = '2022-23', os.path.basename(path)
    school = ''
    cols = ['slots', 'applications', 'offered', 'waitlisted', 'cancelled', 'not_placed']
    for text in text_lines(path):
        r = split_row(text, 7)
        if r:
            school = r[0] or school
            mshs_row(year, src, school, MSHS, str(r[1][0]), False, **dict(zip(cols, r[1][1:])))


def parse_mshs_2023_24(path):
    year, src = '2023-24', os.path.basename(path)
    school = ''
    cols = ['slots', 'applications', 'offered', 'waitlisted', 'cancelled']
    for text in text_lines(path):
        r = split_row(text, 6)
        if r:
            school = r[0] or school
            mshs_row(year, src, school, MSHS, str(r[1][0]), False, **dict(zip(cols, r[1][1:])))
        elif not re.search(r'\d', text.replace('K-8', '')):
            school = text if text not in ('High School', 'Middle School') else school
        elif re.match(r'^[A-Za-z]', text) and 'TOTALS' not in text and 'Summary' not in text:
            pass


def profile_languages(year, pps):
    """Immersion languages a school has in that year's track-profile file."""
    langs = {'imm_spanish': 'Spanish', 'imm_mandarin': 'Mandarin', 'imm_japanese': 'Japanese',
             'imm_russian': 'Russian', 'imm_vietnamese': 'Vietnamese'}
    for r in PROFILE_ROWS:
        if r['year'] == year and r['school'] == pps:
            return [l for c, l in langs.items() if r[c] not in ('', '0')]
    return []


def column_edges(lines, off_x):
    """Right edges of the 4 value columns on a page: clusters of the data numbers' right edges."""
    res = sorted(x + DIGIT_W * len(t.rstrip('*')) for _, toks in lines for x, t in toks
                 if x > off_x and re.fullmatch(r'\d+\*?', t))
    clusters = []
    for r in res:
        if clusters and r - clusters[-1][-1] <= 20:
            clusters[-1].append(r)
        else:
            clusters.append([r])
    if len(clusters) > 4:
        fail(f'{len(clusters)} numeric columns on a page (expected at most 4): {[round(c[0]) for c in clusters]}')
    return [sum(c) / len(c) for c in clusters] if len(clusters) == 4 else None


def parse_mshs_positional(path, year):
    """2024-25 .. 2026-27 MS/HS: Offered, Waitlisted, Canceled, Applicants from right edges.

    Empty cells are omitted from the text layer, so each number is assigned to the nearest of the
    four column right edges, which are measured per page (the 2026-27 pages differ)."""
    src = os.path.basename(path)
    cols = ['offered', 'waitlisted', 'cancelled', 'applications']
    school, ptype, block, edges, off_x = '', MSHS, [], None, 0

    def put(school, grade, total, cnt):
        if ptype != DLI_LOC:
            return mshs_row(year, src, school, ptype, grade, total, **cnt)
        langs = profile_languages(year, pps_name(school))  # '' when the school has several
        return add(year, src, school, DLI, DLI_LOC, langs[0] if len(langs) == 1 else '', grade, '',
                   total, **cnt)

    for p in range(len(PdfReader(path).pages)):
        lines = read_lines(path, p)
        offs = [x for _, toks in lines for x, t in toks if t.strip() == 'Offered' and x > 150]  # the column header, not the key
        off_x = min(offs) if offs else off_x
        edges = column_edges(lines, off_x) or edges
        if edges is None:
            fail(f'{src} page {p + 1}: cannot measure the value columns')
        for _, toks in lines:
            text = ltext(toks)
            if text.startswith('Dual Language Immersion by School Locations'):
                ptype = DLI_LOC
                continue
            if re.match(r'^(Focus Options|Offers will|\*|Offered -|Canceled -|Waitlisted -|before|Key Def|'
                        r'were made|to historical|Due )', text):
                continue
            hdr = re.match(r'^(.*?)\s*(?:Grade\s+)?Offered\s+Waitlisted\s+Canceled', text)
            nums, labels = [], []
            for x, t in toks:
                core = t.rstrip('*').strip()
                if re.fullmatch(r'\d+', core) and x > off_x:
                    nums.append((x + DIGIT_W * len(core), core))
                elif re.fullmatch(r'\d+\*?', t) and x <= off_x:
                    labels.append(t)  # a grade, or the 8 of "K-8"; decided below
                elif t not in ('*', 'th', 'st', 'nd', 'rd', 'Grade', 'Offered', 'Waitlisted',
                               'Canceled', 'Waitlist', 'Cancelled', 'Applicants', 'Total Applicants',
                               'Grand Total') or t in ('Total', 'Grand Total'):
                    labels.append(t)
            grade_tok = ''
            if nums and labels and re.fullmatch(r'\d+\*?', labels[-1]):  # the grade ends the label zone
                grade_tok = labels.pop().rstrip('*')
            label = re.sub(r'\s*-\s*', '-', ' '.join(labels)).strip()  # "K - 8" -> "K-8"
            if hdr:
                school = hdr.group(1).strip() or school
                continue
            gt_fragment = not nums and re.fullmatch(r'Grand Total( \d+)+', text)
            if not nums and not gt_fragment:
                if re.fullmatch(r'(Grand )?Total|Applicants|School|School/Grade|Total Applicants', label) \
                        or label.endswith(' Total') or not label:
                    continue
                if re.search(r'Lottery Results|Summary', label):
                    continue
                school = label  # school name line
                continue
            if gt_fragment:  # printed as one text fragment: numbers are in column order
                vals = [int(v) for v in text.split()[2:]]
                if len(vals) != 4:
                    fail(f'{src}: cannot place Grand Total {text!r}')
                cnt, label, grade = dict(zip(cols, vals)), 'Grand Total', ''
            else:
                cnt, grade = {}, grade_tok
                for re_, v in nums:
                    col = min(range(4), key=lambda i: abs(edges[i] - re_))
                    if abs(edges[col] - re_) > 22:
                        fail(f'{src}: number {v} at {re_:.0f} fits no column in {text!r}')
                    if cols[col] in cnt:
                        fail(f'{src}: two numbers in column {cols[col]} in {text!r}')
                    cnt[cols[col]] = int(v)
            if label == 'Grand Total':
                s = sum(r['applications'] for r in block)
                if cnt['applications'] != s:
                    fail(f'{src}: Grand Total applications {cnt["applications"]} != sum of schools {s}')
                CHECKS['grand totals validated'] += 1
                block = []
                continue
            if label.endswith(' Total'):
                if not school:
                    fail(f'{src}: total without school: {text!r}')
                block.append(put(school, '', True, cnt))
                continue
            if label:
                school = label
            if not school or not grade:
                fail(f'{src}: row without school or grade: {text!r}')
            put(school, grade, False, cnt)


# ---------------------------------------------------------------- validation
def set_total_levels(rows):
    """Total rows have no grade; give them the level of their school's grade rows."""
    lev = {}
    for r in rows:
        if r['is_total'] == 'FALSE' and r['level']:
            lev.setdefault((r['source_file'], r['school'], r['program']), r['level'])
    for r in rows:
        if r['is_total'] == 'TRUE' and not r['level']:
            r['level'] = lev.get((r['source_file'], r['school'], r['program']), '')


def validate_totals(rows):
    """Group rows sum to the printed school total (all grades, else kindergarten rows only)."""
    by = defaultdict(list)
    for r in rows:
        by[(r['source_file'], r['school'], r['program'], r['level'] if r['is_total'] == 'FALSE' else '')]
    keyed = defaultdict(lambda: ([], []))
    for r in rows:
        keyed[(r['source_file'], r['school'], r['program'])][r['is_total'] == 'TRUE'].append(r)
    for (src, school, prog), (groups, totals) in keyed.items():
        for t in totals:
            for label, rs in (('', groups), (' (kindergarten rows only)', [g for g in groups if g['grade'] in ('K', '')])):
                bad = [c for c in COUNTS if t[c] != '' and sum(g[c] for g in rs if g[c] != '') != t[c]]
                if not bad:
                    CHECKS['school totals validated' + ('' if not label else ' on kindergarten rows only')] += 1
                    break
            else:
                detail = {c: (sum(g[c] for g in groups if g[c] != ''), t[c]) for c in bad}
                fail(f'{src} {school}: group rows vs printed total (sum, printed): {detail}')


def fix_misordered_columns(rows):
    """2025-26 Elementary prints Buckman grades 1-5 with the columns in the 2026-27 order (Offered,
    Waitlist, Cancelled, Applications) under the 2025-26 header (Slots Filled, Applications,
    Waitlist, Cancelled): e.g. grade 1 reads 9 0 6 15, i.e. 9 offered of 0 applications. Every
    such row satisfies the identity only in the 2026-27 order, so those rows are re-read that way.
    Only non-immersion rows that fail the identity as printed and pass it re-read are touched."""
    for r in rows:
        if r['program_type'] == DLI or r['is_total'] == 'TRUE' or r['grade'] in ('', 'K'):
            continue
        o, a, w, c = (r[k] for k in ('offered', 'applications', 'waitlisted', 'cancelled'))
        if o + w + c != a and o + a + w == c:
            r['applications'], r['waitlisted'], r['cancelled'] = c, a, w
            CHECKS['2025-26 rows re-read in 2026-27 column order (Buckman)'] += 1
            warn(f"{r['source_file']}: {r['school']} grade {r['grade']} columns re-read as "
                 f"offered/waitlist/cancelled/applications ({o}/{a}/{w}/{c} as printed)")


def identity_violations(rows):
    bad = []
    for r in rows:
        if r['applications'] == '' or r['offered'] == '':
            continue
        parts = sum(r[c] for c in ('offered', 'waitlisted', 'cancelled', 'not_placed') if r[c] != '')
        CHECKS['rows with applications = offered+waitlisted+cancelled(+not_placed) testable'] += 1
        if parts != r['applications']:
            bad.append(r)
    return bad


def check_languages():
    """SCHOOL_LANG against data/dli_sites.csv (status-quo elementary and middle rows)."""
    with open(SITES, encoding='utf-8') as fh:
        for r in csv.DictReader(fh):
            if r['scenario'] == 'sq' and r['band'] == 'K-5' and r['pps_school'] in SCHOOL_LANG:
                if SCHOOL_LANG[r['pps_school']] != r['language']:
                    fail(f"SCHOOL_LANG says {r['pps_school']} is {SCHOOL_LANG[r['pps_school']]}, "
                         f"dli_sites.csv says {r['language']}")
                CHECKS['SCHOOL_LANG entries confirmed by dli_sites.csv'] += 1


# ---------------------------------------------------------------- main
FILES = [
    ('2021-22_Elementary_Lottery.pdf', parse_2021_22_elem),
    ('2022-23_Elementary_Lottery.pdf', parse_2022_23_elem),
    ('2023-24_Elementary_Lottery.pdf', lambda p: parse_header_first(
        p, '2023-24', ['slots', 'offered', 'waitlisted', 'cancelled', 'applications'])),
    ('2024-25_Elementary_Lottery.pdf', lambda p: parse_header_first(
        p, '2024-25', ['offered', 'applications', 'waitlisted', 'cancelled'], ascending=True)),
    ('2025-26_Elementary_Lottery.pdf', lambda p: parse_header_first(
        p, '2025-26', ['offered', 'applications', 'waitlisted', 'cancelled'], split_page0_at=300)),
    ('2026-27_Kindergarten_Lottery.pdf', parse_2026_27_k),
    ('2026-27_FocusMLC_Grades1-5_Lottery.pdf', parse_2026_27_focus),
    ('2021-22_MiddleHigh_Lottery.pdf', parse_mshs_2021_22),
    ('2022-23_MiddleHigh_Lottery.pdf', parse_mshs_2022_23),
    ('2023-24_MiddleHigh_Lottery.pdf', parse_mshs_2023_24),
    ('2024-25_MiddleHigh_Lottery.pdf', lambda p: parse_mshs_positional(p, '2024-25')),
    ('2025-26_MiddleHigh_Lottery.pdf', lambda p: parse_mshs_positional(p, '2025-26')),
    ('2026-27_MiddleHigh_Lottery.pdf', lambda p: parse_mshs_positional(p, '2026-27')),
]


def main():
    check_languages()
    summary = []
    for name, parser in FILES:
        path = os.path.join(PDF_DIR, name)
        if not os.path.exists(path):
            fail(f'missing {path}')
        n0 = len(ROWS)
        parser(path)
        new = ROWS[n0:]
        if not new:
            fail(f'{name}: no rows parsed')
        set_total_levels(new)
        if name.startswith('2025-26_Elementary'):
            fix_misordered_columns(new)
        validate_totals(new)
        bad = identity_violations(new)
        summary.append((name, len(new), len(bad)))
        for r in bad[:6]:
            warn(f"{name}: {r['school']} {r['program']} grade {r['grade'] or '-'} {r['group'] or '-'}: "
                 f"applications {r['applications']} != offered+waitlisted+cancelled(+not placed)")
    # immersion programs per year and level must include every school printed
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w', newline='', encoding='utf-8') as fh:
        w = csv.DictWriter(fh, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(ROWS)

    print('file summary (rows, rows violating applications = offered+waitlisted+cancelled(+not placed))')
    for name, n, nb in summary:
        print(f'  {name:42s} {n:4d} rows  {nb:3d} identity violations')
    print('checks passed:')
    for k, v in sorted(CHECKS.items()):
        print(f'  {v:4d}  {k}')
    progs = defaultdict(set)
    for r in ROWS:
        if r['program_type'] == DLI and r['is_total'] == 'FALSE':
            progs[(r['year'], r['level'])].add((r['pps_school'] or r['school'], r['language'], r['program']))
    print('immersion programs parsed (year, level: count)')
    for (y, lv), s in sorted(progs.items()):
        print(f'  {y} {lv}: {len(s)}  ' + ', '.join(sorted(f'{a} [{b or "?"}]' for a, b, _ in s)))
    rigler = [r for r in ROWS if 'rigler' in r['school'].lower()]
    print('Rigler rows:', len(rigler))
    for w_ in WARNINGS:
        print('note:', w_, file=sys.stderr)
    print('wrote', os.path.relpath(OUT), len(ROWS), 'rows')


if __name__ == '__main__':
    main()
