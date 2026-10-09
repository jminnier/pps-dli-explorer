"""Warn when a Spanish page (es/<page>.qmd) has drifted from its English page (<page>.qmd).

Runs before every render (pre-render in _quarto.yml). For each English page it compares, with the
Spanish copy: chunk labels, section anchors ({#...}), the number of inline `r ...` expressions and the
number of cite(...) calls. A difference usually means the English page was edited and the Spanish page
wasn't. It prints a warning and never stops the render; pass --strict to exit non-zero instead.

Usage: python3 tools/check_es_sync.py [--strict]
"""
import os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
PAGES = ["index", "scorecard", "equity", "history", "research", "methods"]

def features(path):
    s = open(path, encoding="utf-8").read()
    return {
        "chunk labels": re.findall(r"^#\| label: (\S+)", s, re.M),
        "anchors": re.findall(r"\{#([\w-]+)\}", s),
        "inline r expressions": len(re.findall(r"`r [^`]+`", s)),
        "cite() calls": len(re.findall(r"\bcite\(", s)),
    }

problems = []
for p in PAGES:
    en, es = os.path.join(ROOT, f"{p}.qmd"), os.path.join(ROOT, "es", f"{p}.qmd")
    if not os.path.exists(es):
        problems.append(f"{p}: es/{p}.qmd is missing")
        continue
    fe, fs = features(en), features(es)
    for k in fe:
        if fe[k] != fs[k]:
            a, b = fe[k], fs[k]
            if isinstance(a, list):
                detail = f"only in English: {sorted(set(a) - set(b)) or '-'}; only in Spanish: {sorted(set(b) - set(a)) or '-'}" if set(a) != set(b) else "same set, different order or count"
            else:
                detail = f"English {a}, Spanish {b}"
            problems.append(f"{p}: {k} differ ({detail})")

if problems:
    print("WARNING: Spanish pages out of sync with English (update es/ to match):\n  " + "\n  ".join(problems))
    if "--strict" in sys.argv:
        sys.exit(1)
else:
    print("Spanish pages in sync with English.")
