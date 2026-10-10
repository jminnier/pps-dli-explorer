"""Reading-level check for the site's prose (English and Spanish pages).

Strips YAML, code chunks, inline `r ...` (replaced by a number), tables, HTML and Markdown markup, then reports
per page: words, average sentence length, share of sentences over 25 words, and a grade level:
  English: Flesch-Kincaid grade (target: 8 to 10 for this site's body text; plain-language guidance aims at 8).
  Spanish: Fernández-Huerta readability (higher = easier; 60-70 = "normal", 70-80 = "bastante fácil").
Syllables are estimated from vowel groups, so treat the scores as a rough guide, not a measurement.

Usage: python3 tools/readability.py [--long N]   (--long prints the N longest sentences per page)
"""
import os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
PAGES = ["index", "scorecard", "equity", "history", "research", "methods"]

def prose(path):
    s = open(path, encoding="utf-8").read()
    s = re.sub(r"\A---.*?\n---\n", "", s, flags=re.S)
    s = re.sub(r"```.*?```", "", s, flags=re.S)
    s = re.sub(r"`r [^`]+`", "12", s)
    s = re.sub(r"`[^`]*`", "x", s)
    s = re.sub(r"^\s*\|.*$", "", s, flags=re.M)          # pipe tables
    s = re.sub(r"<[^>]+>", " ", s)
    s = re.sub(r"\{[#.][^}]*\}", "", s)                   # attributes
    s = re.sub(r"^:::.*$", "", s, flags=re.M)
    s = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", s)       # links
    s = re.sub(r"https?://\S+", "", s)
    s = re.sub(r"^#+\s.*$", "", s, flags=re.M)            # headings scored separately (short by design)
    s = re.sub(r"^\s*([-*+]|\d+\.)\s+", "", s, flags=re.M)
    s = re.sub(r"[*_>]", "", s)
    return s

def sentences(text):
    paras = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
    out = []
    for p in paras:
        p = re.sub(r"\s+", " ", p)
        p = re.sub(r"\b(e\.g|i\.e|vs|p|pp|Dr|St|Ave|No|U\.S|EE\. UU|approx|Fig|Tbl|et al)\.", lambda m: m.group(0).replace(".", "§"), p)
        p = re.sub(r"(\d)\.(\d)", r"\1§\2", p)
        for x in re.split(r"(?<=[.!?:;])\s+", p):
            w = re.findall(r"[A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9§%'-]+", x)
            if len(w) >= 3:
                out.append((x.replace("§", "."), w))
    return out

def syl(word, es):
    w = word.lower()
    if re.fullmatch(r"[\d§%.,-]+", w):
        return 2
    if es:
        return max(1, len(re.findall(r"[aeiouáéíóúü]+", w)))
    w = re.sub(r"(?:[^laeiouy]es|ed|[^laeiouy]e)$", "", w)
    w = re.sub(r"^y", "", w)
    return max(1, len(re.findall(r"[aeiouy]{1,2}", w)))

def score(path, es, nlong=0):
    sents = sentences(prose(path))
    words = [w for _, ws in sents for w in ws]
    n_s, n_w = len(sents), len(words)
    n_syl = sum(syl(w, es) for w in words)
    asl = n_w / n_s
    long_share = sum(len(ws) > 25 for _, ws in sents) / n_s
    if es:
        grade = 206.84 - 60 * (n_syl / n_w) - 1.02 * asl     # Fernández-Huerta
    else:
        grade = 0.39 * asl + 11.8 * (n_syl / n_w) - 15.59     # Flesch-Kincaid grade
    longest = sorted(sents, key=lambda s: -len(s[1]))[:nlong]
    return n_w, asl, long_share, grade, longest

nlong = int(sys.argv[sys.argv.index("--long") + 1]) if "--long" in sys.argv else 0
print(f"{'page':<18}{'words':>7}{'avg sent':>10}{'>25 words':>11}{'score':>8}")
for es in (False, True):
    print("English (Flesch-Kincaid grade, lower = easier)" if not es else "Spanish (Fernández-Huerta, higher = easier)")
    for p in PAGES:
        path = os.path.join(ROOT, "es" if es else "", f"{p}.qmd")
        n_w, asl, ls, g, longest = score(path, es, nlong)
        print(f"  {p:<16}{n_w:>7}{asl:>10.1f}{ls:>10.0%}{g:>8.1f}")
        for s, w in longest:
            print(f"      [{len(w)}] {s[:220]}")
