"""Check prose added since a git commit against STYLE.md rules.

Flags, in lines added since BASE (code chunks and table code skipped; quotations excluded from length):
sentences over 25 words, paragraphs over 150 words, "e.g."/"i.e."/"and/or", dashes used as connectors, and
(English only) likely passive voice. It is a screen, not a judge: read the flagged lines and the whole section.

Usage: python3 tools/plaincheck.py <base-commit> <file.qmd> [...]
       python3 tools/plaincheck.py --prerender   # uncommitted edits to any .qmd, warnings only (run before every render)
"""
import re, subprocess, sys
PRE = sys.argv[1:] == ["--prerender"]
if PRE:
    BASE = "HEAD"
    changed = subprocess.run(["git", "diff", "--name-only", "HEAD", "--", "*.qmd"], capture_output=True, text=True).stdout.split()
    new = subprocess.run(["git", "ls-files", "--others", "--exclude-standard", "--", "*.qmd"], capture_output=True, text=True).stdout.split()
    files = changed + new
else:
    BASE = sys.argv[1]; files = sys.argv[2:]
flagged = 0
for f in files:
    diff = subprocess.run(["git", "diff", "-U0", BASE, "--", f], capture_output=True, text=True).stdout
    if f in (new if PRE else []):
        diff = "\n".join("+" + l for l in open(f, encoding="utf-8").read().split("\n"))
    added = [l[1:] for l in diff.split("\n") if l.startswith("+") and not l.startswith("+++")]
    es = f.startswith("es/")
    out = []
    in_chunk = False
    for l in added:
        if l.startswith("```"): in_chunk = not in_chunk; continue
        if in_chunk or l.startswith("#|") or l.strip().startswith(("|", "tab_", "cols_", "gt(", "fmt_", "mutate", "filter", "select", "rg ", "rp ", "rs ", "transmute", "arrange", "bind_rows", "sub_missing")) or "<-" in l: continue
        t = re.sub(r"`r [^`]+`", "12", l); t = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", t); t = re.sub(r"[*_]", "", t)
        t = re.sub(r"\{#[^}]*\}", "", t).strip()
        if not t or t.startswith(":::"): continue
        words = len(re.findall(r"\w+", t))
        if not t.startswith("#") and words > 150: out.append(f"PARA {words}w: {t[:80]}")
        noq = re.sub(r"[\"“][^\"”]*[\"”]", "Q", t)
        for s in re.split(r"(?<=[.!?;:])\s+(?=[A-Z¿¡\"“(])", noq):
            n = len(re.findall(r"\w+", s))
            if n > 25: out.append(f"LONG {n}w: {s[:160]}")
        if re.search(r"\be\.g\.|\bi\.e\.|and/or|y/o", t): out.append(f"BANNED: {t[:100]}")
        if re.search(r" — | – |--", noq): out.append(f"DASH: {t[:120]}")
        if not es:
            for m in re.finditer(r"\b(is|are|was|were|be|been|being)\s+(\w+ed|shown|given|made|done|taken|seen|known|left|kept|counted)\b", noq):
                out.append(f"PASSIVE? '{m.group(0)}': {noq[max(0,m.start()-50):m.end()+30]}")
    flagged += len(out)
    if PRE and not out:
        continue
    print(f"== {f}: {len(out)} flags" + (" (plain language, STYLE.md)" if PRE else "")); print("\n".join(out))
if PRE and flagged:
    print(f"PLAIN LANGUAGE: {flagged} flag(s) in uncommitted text. Fix them (or confirm they are quotations) before publishing.")
elif PRE:
    print("Plain-language check: no flags in uncommitted text.")
