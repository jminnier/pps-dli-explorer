#!/usr/bin/env python3
"""Parse pages 3-4 of the PPS Family-Friendly School Guide PDFs
(data-raw/pps_board/impact_page/*.pdf, downloaded from the PPS Google Drive 2026-10-08)
into tidy CSVs:

  data/guide_enrollment.csv  school, option, scenario, year, enrollment, status, source_file, pdf_moddate
  data/guide_school.csv      one row per school x option (as printed)
  data/guide_text.csv        page-3 narrative sections + snapshot details

`scenario` is sq / a / b; the printed "Options A and B" is expanded to both a and b.
Option set per school is taken from the page-4 "Measure" header. Options whose type of
change is "School would close" often have no enrollment row (blank enrollment,
status = "closes"); where a row is printed (Rose City Park zeros, Sellwood 2027-28 only)
it is kept as printed. Percentages are fractions. Exits non-zero if any check fails.
"""
import csv, glob, os, re, sys
from pypdf import PdfReader

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "data-raw", "pps_board", "impact_page")
OUT = os.path.join(ROOT, "data")
KNOWN_OPTIONS = {"No changes", "Option A", "Option B", "Options A and B"}
YEARS = ["2027-28", "2028-29", "2029-30", "2030-31", "2031-32"]
SCEN = {"No changes": ["sq"], "Option A": ["a"], "Option B": ["b"], "Options A and B": ["a", "b"]}
PCT = r"(\d+(?:\.\d+)?%?|N/A|Not Applicable)"
ROW_LABELS = ["Type of change", "Meets school size goal?", "Meets space use goal?",
              "Students living within 1 mile", "Grades and programs"]
GRID = {2: [270.7, 416.8], 3: [270.7, 368.1, 465.6]}   # x of option columns in the program table
errors = []


def err(school, msg):
    errors.append(f"{school}: {msg}")


def moddate(r):
    m = (r.metadata or {}).get("/ModDate", "") or ""
    g = re.match(r"D:(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)", m)
    return "%s-%s-%s %s:%s:%s" % g.groups() if g else ""


VOCAB = set()


def smart_join(pieces):
    """join text pieces of one line; pypdf drops the inter-word gap between pieces, so a
    junction is closed up only when it completes a word seen in the guides' plain text."""
    out = ""
    for p in pieces:
        p = p.replace("\n", " ")
        if out and not out[-1].isspace() and not p[:1].isspace():
            a = re.search(r"([A-Za-z]+)$", out)
            b = re.match(r"([A-Za-z]+)", p)
            if a and b and (a.group(1) + b.group(1)).lower() not in VOCAB:
                out += " "
        out += p
    return out


def fragments(page):
    """text fragments (y, x, text) with true PDF coordinates; drops block-level duplicates"""
    fr = []

    def v(text, cm, tm, fd, fs):
        if text.strip():
            y = round(cm[5] + tm[5] * cm[3], 1)
            if y > 0:
                fr.append((y, round(cm[4] + tm[4] * cm[0], 1), text))
    page.extract_text(visitor_text=v)
    norm = [re.sub(r"\s+", "", t) for _, _, t in fr]
    keep = []
    for i, (y, x, t) in enumerate(fr):
        if "\n" in t.strip():
            inside = sum(1 for j, n in enumerate(norm) if j != i and len(n) >= 8 and n in norm[i])
            if inside >= 2:
                continue
        keep.append((y, x, t))
    return keep


def parse_program_table(layout_lines, frs, options, school):
    """First-line cells come from layout text (split on 2+ spaces); wrapped continuation
    lines come from true x positions mapped to the option-column grid."""
    n = len(options)
    first = {}
    for ln in layout_lines:
        s = ln.strip()
        lab = next((l for l in ROW_LABELS if s.startswith(l)), None)
        if lab:
            cells = [c.strip() for c in re.split(r"\s{2,}", s[len(lab):].strip()) if c.strip()]
            first[lab] = cells
    rowy = {}
    for y, x, t in frs:
        lab = next((l for l in ROW_LABELS if t.strip().startswith(l)), None)
        if lab and lab not in rowy:
            rowy[lab] = y
    out = {}
    grid = GRID.get(n)
    if grid is None:
        err(school, f"no column grid for {n} options")
        return {}
    for lab in ROW_LABELS:
        cells = list(first.get(lab, []))
        if len(cells) != n:
            err(school, f"row '{lab}': {len(cells)} first-line cells, expected {n}: {cells}")
            cells = (cells + [""] * n)[:n]
        out[lab] = cells
    ys = sorted(rowy.items(), key=lambda kv: -kv[1])
    cont = [(y, x, t) for y, x, t in frs if x > 100 and ys and y < ys[0][1] - 3
            and all(abs(y - ry) > 3 for _, ry in ys)]
    # stop at the boundary section
    ystop = next((y for y, x, t in frs if t.strip().startswith("Where would the school boundary")), 0)
    for y, x, t in sorted(cont, key=lambda f: -f[0]):
        if y <= ystop:
            continue
        owner = [lab for lab, ry in ys if ry - 3 > y]
        if not owner:
            continue
        lab = owner[-1]
        if y > rowy[lab] - 3:
            continue
        k = min(range(n), key=lambda i: abs(grid[i] - x))
        if abs(grid[k] - x) > 12:
            err(school, f"continuation '{t.strip()}' at x={x} off-grid in row {lab}")
            continue
        out[lab][k] += " " + t.strip()
    return out


def page3_sections(frs):
    """Assign page-3 fragments to sections by column (x) and the nearest header above."""
    heads = {"why": "WHY IS PPS CONSIDERING THIS?", "proposed": "What is being proposed?",
             "gain": "What could students gain?", "considered": "What else was considered?",
             "special_ed": "What about special education?"}
    hpos = {}
    for y, x, t in frs:
        for k, h in heads.items():
            if t.strip() == h:
                hpos[k] = (y, x)
    sec = {k: [] for k in heads}
    snap = []
    for i, (y, x, t) in enumerate(frs):
        s = t.strip()
        if s in heads.values() or s.startswith("This is a proposal") or s.startswith("PORTLAND PUBLIC") \
                or s.startswith("RIGHTSIZE") or s.startswith("School proposal") or s == frs[2][2].strip():
            continue
        if x in (61.0, 255.0) or s.startswith("SCHOOL SNAPSHOT"):
            snap.append((y, i, t)); continue
        cands = [(hy - y, k) for k, (hy, hx) in hpos.items() if (hx < 300) == (x < 300) and hy > y]
        if not cands:
            continue
        sec[min(cands)[1]].append((y, i, t))
    res = {}
    for k, v in sec.items():
        res[k] = "".join(t + (" " if not t.endswith(" ") else "") if False else t for _, _, t in sorted(v, key=lambda a: (-a[0], a[1])))
    snapline = {}
    for y, i, t in sorted(snap, key=lambda a: (-a[0], a[1])):
        snapline.setdefault(y, []).append(t)
    res["snapshot"] = " ".join(smart_join(v) for y, v in sorted(snapline.items(), key=lambda a: -a[0]))
    # line joins: fragments on different y are separate lines -> join with space
    out = {}
    for k in heads:
        lines = {}
        for y, i, t in sorted(sec[k], key=lambda a: (-a[0], a[1])):
            lines.setdefault(y, []).append(t)
        out[k] = clean(" ".join(smart_join(v) for y, v in sorted(lines.items(), key=lambda a: -a[0])))
    # a header can be glued into the previous paragraph's fragment (Whitman): split it back out
    for k in list(heads):
        for k2, h in heads.items():
            if k2 != k and k2 != "why" and h in out[k]:
                before, after = out[k].split(h, 1)
                out[k] = before.strip()
                out[k2] = (after.strip() + " " + out[k2]).strip() if not out[k2] else out[k2]
    out["snapshot"] = clean(res["snapshot"])
    return out


def clean(t):
    t = re.sub(r"Version [\d.]+ \d+", "", t)
    return re.sub(r"\s+", " ", t).strip()


def main():
    files = sorted(glob.glob(os.path.join(SRC, "*.pdf")))
    for f in files:
        VOCAB.update(w.lower() for w in re.findall(r"[A-Za-z]+", PdfReader(f).pages[2].extract_text()))
    enr, sch, txt = [], [], []
    for f in files:
        fn = os.path.basename(f)
        school = fn[:-4]
        r = PdfReader(f)
        md = moddate(r)
        if len(r.pages) < 4:
            err(school, f"only {len(r.pages)} pages"); continue
        p3f = fragments(r.pages[2])
        p4f = fragments(r.pages[3])
        p4 = r.pages[3].extract_text(extraction_mode="layout").split("\n")
        # ---- program table header gives the option set
        i_m = next((i for i, ln in enumerate(p4) if re.match(r"\s*Measure\s", ln)), None)
        i_e = next((i for i, ln in enumerate(p4) if ln.strip().startswith("Where would the school boundary")), None)
        i_h = next((i for i, ln in enumerate(p4) if re.match(r"\s*School year\s+2027-28", ln)), None)
        if None in (i_m, i_e, i_h):
            err(school, "page-4 table markers not found"); continue
        opts = [c.strip() for c in re.split(r"\s{2,}", p4[i_m].strip()) if c.strip()][1:]
        for o in opts:
            if o not in KNOWN_OPTIONS:
                err(school, f"unknown option label {o!r}")
        if "No changes" not in opts:
            err(school, "no 'No changes' column")
        if len(set(opts)) != len(opts):
            err(school, f"duplicate options {opts}")
        scs = sorted({s for o in opts for s in SCEN.get(o, [])})
        if scs != ["a", "b", "sq"]:
            err(school, f"scenario coverage {scs}")
        tbl = parse_program_table(p4[i_m + 1:i_e], p4f, opts, school)
        toc = tbl.get("Type of change", [""] * len(opts))
        # ---- enrollment rows (printed)
        printed, enr_note = {}, ""
        lines = p4[i_h + 1:i_m]
        for j, ln in enumerate(lines):
            m = re.match(r"\s*(No changes|Options? [A-Z](?: and [A-Z])?|Scenario A/B Note:)\s{2,}(\d[\d,]*)(.*)$", ln)
            if not m:
                continue
            label = m.group(1)
            if label.startswith("Scenario A/B Note"):
                label = "Options A and B"
                enr_note = "; ".join(re.sub(r"\s+", " ", re.sub(r"Scenario A/B Note:", "", x.strip()[:25].split("  ")[0])).strip()
                                     for x in lines[j:j + 4] if x.strip() and re.match(r"\s{0,3}\S", x))
                enr_note = "Scenario A/B Note: " + re.sub(r"^;\s*", "", re.sub(r"Scenario A/B Note:\s*", "", " ".join(
                    re.split(r"\s{2,}", x.strip())[0] for x in lines[j:j + 4] if x.strip())).strip())
            if label not in KNOWN_OPTIONS:
                err(school, f"unknown enrollment option label {label!r}"); continue
            toks = re.split(r"\s{2,}", (m.group(2) + "  " + m.group(3)).strip())
            vals = []
            for tkn in toks:
                tkn = tkn.strip()
                if re.fullmatch(r"\d[\d,]*", tkn):
                    vals.append(int(tkn.replace(",", "")))
                elif tkn.startswith("School would"):
                    vals.append(None)
                elif tkn:
                    err(school, f"{label}: unexpected enrollment token {tkn!r}")
            if label in printed:
                err(school, f"duplicate enrollment row {label}")
            printed[label] = vals
        if "Options A and B" in opts and "Options A and B" not in printed and "Option A" in printed:
            if printed.get("Option A") == printed.get("Option B"):
                printed["Options A and B"] = printed.pop("Option A"); printed.pop("Option B")
            else:
                err(school, "header says Options A and B but A and B enrollment rows differ")
        for label, vals in printed.items():
            if label not in opts:
                err(school, f"enrollment row {label!r} not in program-table options {opts}")
            if len(vals) != 5:
                err(school, f"{label}: {len(vals)} year values, expected 5")
            for v in vals:
                if v is not None and not 0 <= v <= 3000:
                    err(school, f"{label}: implausible enrollment {v}")
        if "No changes" not in printed or any(v is None for v in printed.get("No changes", [None])):
            err(school, "missing complete 'No changes' enrollment row")
        for o, tc in zip(opts, toc):
            if o not in printed and "close" not in tc.lower():
                err(school, f"{o}: no enrollment row and not a closure ({tc!r})")
        for o, tc in zip(opts, toc):
            closes = "school would close" in tc.lower()
            vals = printed.get(o, [None] * 5)
            vals = (vals + [None] * 5)[:5]
            for y, v in zip(YEARS, vals):
                for sc in SCEN[o]:
                    enr.append(dict(school=school, option=o, scenario=sc, year=y,
                                    enrollment="" if v is None else v,
                                    status="closes" if closes else "open",
                                    printed_row="yes" if o in printed else "no",
                                    note=enr_note if o == "Options A and B" else "",
                                    source_file=fn, pdf_moddate=md))
        # ---- demographics (rows only for non-closing options, in order)
        i_w = next((i for i, ln in enumerate(p4) if ln.strip().startswith("Who would the school serve")), None)
        demo_txt = re.sub(r"Version [\d.]+ \d+", "", " ".join(p4[i_w + 1:]) if i_w is not None else "")
        demo_txt = re.sub(r"\bOptions A\s+and B\b", " ", demo_txt)
        demo_rows = re.findall(r"%s\s+%s\s+%s\s+%s\s+(Yes|No)\b" % ((PCT,) * 4), demo_txt)
        open_idx = [k for k, tc in enumerate(toc) if "school would close" not in tc.lower()]
        if len(demo_rows) != len(open_idx):
            err(school, f"demographic rows {len(demo_rows)} != non-closing options {len(open_idx)}")
            demo_rows = (demo_rows + [("",) * 5] * len(open_idx))[:len(open_idx)]
        demo = {k: d for k, d in zip(open_idx, demo_rows)}

        def frac(s, what):
            s = s.strip()
            if re.fullmatch(r"\d+(\.\d+)?%?", s):
                v = float(s.rstrip("%"))
                if not 0 <= v <= 100:
                    err(school, f"{what} out of range: {s}")
                return round(v / 100, 4)
            return ""
        # ---- page 3
        sec = page3_sections(p3f)
        snap = sec["snapshot"]
        cp = re.search(r"Current program (.*?) Expected enrollment", snap)
        goal = re.search(r"District school size goal (.*?) Students living", snap)
        bn = re.search(r"Building notes (.*)$", snap)
        prop = next((t.split("|", 1)[1].strip() for y, x, t in p3f if t.strip().startswith("School proposal")), "")
        if not cp or not goal:
            err(school, f"snapshot not parsed: {snap!r}")
        # completeness: alphanumeric characters recovered vs pypdf plain text of page 3
        plain = r.pages[2].extract_text()
        plain = re.sub(r"PORTLAND PUBLIC SCHOOLS.*?FAMILY GUIDE|RIGHTSIZE\. RIGHT SUPPORT\. RIGHT for STUDENTS\. \d+|"
                       r"This is a proposal, not a final decision\.|School proposal \| [^\n]*|WHY IS PPS CONSIDERING THIS\?|"
                       r"What is being proposed\?|What could students gain\?|What else was considered\?|What about special education\?|SCHOOL SNAPSHOT DETAILS",
                       "", plain, flags=re.S)
        plain = re.sub(r"\n[A-Z .'-]+\n", "\n", plain, count=1)   # school-name line
        got = sum(len(re.sub(r"\W", "", sec[k])) for k in ("why", "proposed", "gain", "considered", "special_ed", "snapshot"))
        want = len(re.sub(r"\W", "", plain))
        if want and not (0.97 <= got / want and got - want <= 60):
            err(school, f"page-3 text recovery {got}/{want} chars")
        for k in ("why", "proposed", "gain", "considered"):
            if not sec[k] and k != "gain" and k != "considered":
                err(school, f"page-3 section {k} empty")
        for k, o in enumerate(opts):
            def g(lab):
                return tbl.get(lab, [""] * len(opts))[k]
            sz, sp = g("Meets school size goal?"), g("Meets space use goal?")
            closes = "school would close" in toc[k].lower()
            for v, w in ((sz, "size goal"), (sp, "space goal")):
                if v not in ("Yes", "No") and not closes:
                    err(school, f"{o}: {w} = {v!r}")
            w1 = g("Students living within 1 mile")
            d = demo.get(k, ("",) * 5)
            sch.append(dict(
                school=school, option=o, scenario="/".join(SCEN[o]),
                type_of_change=toc[k], meets_size_goal=sz if sz in ("Yes", "No") else "",
                meets_space_goal=sp if sp in ("Yes", "No") else "",
                pct_within_1mi=frac(w1, "within 1 mile") if not closes else "",
                within_1mi_raw=w1, grades_programs=g("Grades and programs") if not closes else "",
                pct_poverty=frac(d[0], "poverty"), pct_sped=frac(d[1], "sped"),
                pct_multilingual=frac(d[2], "multilingual"),
                pct_underserved_race=frac(d[3], "underserved race"), title1=d[4],
                current_program=cp.group(1) if cp else "", district_size_goal=goal.group(1) if goal else "",
                source_file=fn, pdf_moddate=md))
        txt.append(dict(
            school=school, proposal_label=prop, why_considering=sec["why"], what_proposed=sec["proposed"],
            what_gain=sec["gain"], what_else_considered=sec["considered"],
            what_about_special_ed=sec["special_ed"],
            current_program=cp.group(1) if cp else "", district_size_goal=goal.group(1) if goal else "",
            building_notes=bn.group(1) if bn else "", snapshot_raw=snap,
            source_file=fn, pdf_moddate=md))
    # cross checks
    k_e = {(e["school"], e["option"]) for e in enr}
    k_s = {(s["school"], s["option"]) for s in sch}
    if k_e != k_s:
        err("ALL", f"option rows differ between enrollment and school tables: {sorted(k_e ^ k_s)[:5]}")
    if len(txt) != len(files):
        err("ALL", f"parsed {len(txt)} of {len(files)} files")
    if errors:
        print("CHECKS FAILED:")
        for e in errors:
            print("  -", e)
        sys.exit(1)

    def write(name, rows):
        with open(os.path.join(OUT, name), "w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
            w.writeheader(); w.writerows(rows)
    write("guide_enrollment.csv", enr)
    write("guide_school.csv", sch)
    write("guide_text.csv", txt)
    print(f"OK: {len(txt)} schools, {len(sch)} school x option rows, {len(enr)} enrollment rows")


if __name__ == "__main__":
    main()
