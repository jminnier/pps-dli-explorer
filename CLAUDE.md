# CLAUDE.md

Guidance for working in this repository. See README.md for what the project is and how to rebuild it.

## Project in one paragraph

This is an independent analysis of how the Portland Public Schools (PPS) rightsizing Scenarios A and B (October 2026) affect dual language immersion (DLI). It is a Quarto website (R, plotly, gt) built from public PDFs that are parsed into tidy CSVs. It is a private copy of `browniefed/pps-explorer` by Jason Brown, which has no license. The `upstream` remote points to it, and its map app still lives at the repository root (`src/`, `public/`, `scripts/`, `tests/`). The repository is public and the site is published to Netlify (https://pps-dli-explorer.netlify.app/) with `quarto publish netlify --no-prompt` (site id in `_publish.yml`). An older copy is on GitHub Pages (gh-pages branch), which redirects to the user's personal domain. Always credit Jason Brown / pps-explorer, and ppsdata.info, which it credits.

## Layout

- `data-raw/`: source PDFs, and the parser and analysis scripts (Python with `pypdf`, Node, R).
- `data/`: cleaned tables, the only inputs the site reads.
- `R/site_data.R`: loads every table, plus `school_key()` (the same normalization as the map's `schoolKey`, so map, PPS and lottery names join), lottery summaries (`lottery_k`, `lottery_avg`), `strand_students()`, `heritage_share()`, and the source citations `SRC` / `cite()`.
- `R/charts.R`: `viz_layout()` for plotly styling.
- Pages: `index.qmd`, `scorecard.qmd`, `equity.qmd`, `schools.qmd` (School changes), `history.qmd`, `research.qmd`, `methods.qmd`. Register new pages in `_quarto.yml` (`project.render` and `navbar`).
- `STYLE.md`: plain-language writing rules (Federal Plain Language Guidelines; GSA Spanish style guide for es/). `tools/readability.py` scores each page.
- Spanish site: `es/<page>.qmd` mirrors each English page (Latin American Spanish; terms in `es/GLOSSARY.md`). Spanish pages start their setup chunk with `options(site.lang = "es")`, which makes `cite()` use `SRC_ES` (`R/site_data_es.R`; every `SRC` key needs a Spanish entry or the render stops). `lang-switch.html` adds the Español/English button and relabels the shared navbar and footer on Spanish pages. `execute-dir: project` lets es/ pages source `R/` and `data/` the same way.

## Commands

```sh
quarto render                    # build _site/
quarto render equity.qmd         # one page
python3 data-raw/<parser>.py     # each parser prints its checks and exits non-zero on failure
Rscript data-raw/equity_analysis.R
node --test tests/*.test.mjs     # map app data tests (should stay green)
```

To check a page visually, serve `_site` (`python3 -m http.server 8765`) and screenshot it with headless Chrome (`--headless=new --screenshot --virtual-time-budget=8000`). Look at every chart after changing it.

## Conventions

- **Plain language, every time new text is added (user requirement).** Every new or rewritten section, in English and Spanish, must follow the Federal Plain Language Guidelines (digital.gov/guides/plain-language) as set out in `STYLE.md`: main point first, one idea per sentence, active voice naming the actor, everyday words, terms defined at first use, descriptive headings, bold used sparingly. Plain language never drops a caveat: split the sentence instead. Before committing new text:
  - run `python3 tools/plaincheck.py <last-commit> <files>` (it also runs automatically as a pre-render warning on uncommitted `.qmd` edits) and fix every flag; long direct quotations are fine, in both languages
  - run `python3 tools/readability.py` (targets: English grade 9 or lower, Spanish Fernández-Huerta 70 or higher, under 10% of sentences over 25 words)
  - read the new section once against the STYLE.md checklist; the scripts can't check main-point-first, defined terms or bold
  - write the Spanish version by the Spanish section of `STYLE.md` and `es/GLOSSARY.md`, which draw on the resources the user chose (USDR language-access list): GSA's *Spanish Language Style Guide and Glossaries* (ANLE-reviewed: grammar, capitalization, dates, U.S. number format, frequently mistranslated terms), (Re)Nombrar for inclusive language, the RAE dictionary, and DOL's plain-language approach. Adapt rather than translate word for word; usted; Black = "afrodescendientes".
  - report the check results to the user.
- **Small numbers (privacy).** Never display a racial/ethnic count under 5 (0-4, actual or estimated) or a share that implies one. Use the helpers in `R/site_data.R`: `suppress_counts()` before writing derived CSVs (also hides one more count when a row has exactly one hidden), `assert_no_small()`, and on pages `fmt_share()` ("<X%"), `fmt_count()` ("<5"), `fmt_count_words()` ("fewer than 5"), `small_x()` (draw at 2.5 students' worth, open marker). Compute totals from exact values before suppressing. PPS's source table `race_by_program_2025.csv` stays as published. Methods: `#small-numbers`.
- **Cite everything.** Every table, figure, callout and headline number gets a source line: `tab_source_note(md(cite(...)))` for gt, or a `::: {.source}` block after a figure. Add new sources to `SRC` in `R/site_data.R` and to the sources table and calculation sections of `methods.qmd`.
- **Methods must keep pace.** Any new number needs its definition, formula and limitations in `methods.qmd`.
- **Parsers fail loudly.** Validate against totals printed in the source (row, school, section and district totals; printed percentages within ±0.51). Exit with a clear message rather than guess; leave a value blank if it is truly ambiguous.
- **Use computed values in prose.** Compute numbers inline (`` `r ...` ``); don't hard-code them, so the text can't drift from the data.
- **Charts:**
  - Use the validated palette in `PAL` (blue `#2a78d6`, orange `#eb6834`, aqua `#1baf7a`; gray for "unchanged").
  - Thin marks, a hover tooltip on every mark, a legend for two or more series, text in ink colors.
  - Never use two y-axes.
  - The site is light theme only.
- **Plotly sizing in Quarto:** set the height with the chunk option `#| fig-height:`, not `plot_ly(height = ...)`, which gets clipped by the container.
- **dplyr gotcha:** in `summarise()`, compute weighted means before overwriting the weight column (e.g. don't write `students = sum(students)` first).
- **Every English page edit needs the same edit in `es/<page>.qmd`** (text, chunks, labels, anchors). `tools/check_es_sync.py` runs before each render and warns when chunk labels, anchors, inline `r` counts or `cite()` counts differ. Every heading has an explicit `{#id}`, identical in both languages, so links and the language button keep the reader's section; give new headings an explicit id in both. After a render, compare the numbers on each English and Spanish page (they should match exactly).
- **No freeze.** `_quarto.yml` sets `freeze: false` so every render (and `quarto publish`, which renders first) re-runs every page against the current `data/`. Don't turn freeze back on: with `freeze: auto` a changed CSV doesn't trigger a re-run and the site shows stale numbers.
- **zsh gotcha:** never use a variable named `path`; it overwrites `PATH`.
- **Census:** B16001 (separate Russian/Japanese) is published for states only; use C16001 (tracts) and B16007 (ages 5–17). Census downloads are cached in `data-raw/acs/` (git-ignored). The key is in `~/.Renviron`.
- **pps.net rate-limits** (HTTP 429): pause about 5 s between downloads. Current reports are at `/fs/resource-manager/view/<uuid>`; the old `/cms/lib/...` URLs return 404.

## Working style the user expects

- Delegate PDF parsing and web searching to subagents with `model: sonnet`. Leave their output uncommitted, then review, re-run and spot-check it before committing it yourself.
- Commit with clear messages ending in the Co-Authored-By line, and push to `origin main`. Don't contact upstream without asking. Republish the live site (`quarto publish netlify --no-prompt`) only when the user asks.
- Verify surprising claims before stating them, and say so plainly when a number was wrong.

## Possible future additions (not promised on the site)

The user may add these later. They were removed from the home page's "Coming next" list and the README on Oct 9, 2026, so don't mention them on the site unless the user decides to build them.

- A map of access to immersion sites.
- Enrollment projections with adjustable assumptions (likely Observable JS in Quarto rather than Shinylive).
- The address-lookup map (pps-explorer's map, still at the repository root), published under `/map/`. Publishing it needs permission from the pps-explorer author; don't contact him without asking the user.

## Substantive pitfalls (already made once; don't repeat)

- **Lottery ≠ demand at Lent and Rigler.** These all-immersion schools enroll neighborhood children without the lottery: Lent had 43 kindergartners vs 14 offers in 2025-26, and Rigler never appears in the lottery. Richmond and mixed-program schools do fill through the lottery. Never compare lottery counts across a change in how children enter a school (the withdrawn "Bridger→Lent applications fell 64%").
- **Compare like with like.** If one side is an all-grades average, the comparison must be too (the Bridger→Lent precedent: −31% vs −14% district on the same baseline, not −9%).
- **Bridger was K-5** when it had Spanish immersion; it became the K-8 Bridger Creative Science after 2023.
- **Whole-school immersion:** Lent and Rigler (Spanish) and Richmond (Japanese). Some PPS reports print them as a single unlabeled row, and the PSU forecast omits Richmond's Japanese row.
- **Lottery quirk:** the 2021-22 lottery report gives no grade for immersion rows, so lottery averages use 2022-23 to 2026-27.
- **Access figures use block-level allocation.** Tract interior points were threshold-sensitive (59→35% vs 52→36%). Report the 90% intervals from `access_robustness_ci.csv`.
- **Race by program is published (October 2025 only).** PPS's *Enrollment Summary by Race and Ethnicity* (source 23, `race_by_program_2025.csv`, `parse_race_by_program.py` with `.venv/bin/python3` for PyMuPDF) splits immersion and neighborhood programs. Use it for movers' race (`equity_race.R`). Report each racial/ethnic group separately, not only PPS's combined "historically underserved" (which excludes Asian students). Income (direct certification) is still whole-school only. Earlier years: whole-school race only. Single-race groups count only non-Latino students who list one race (report footnote), so Native American and Pacific Islander counts are minimums: never say "no Native American students" without that note.
- **Measured vs modeled distances.** School-to-school distances (1.7 vs 1.2 mi) are measured from the maps. The home-to-school increase (about +1.0 vs +0.5 mi) is a model: immersion families are assumed to live in the area nearest their program's current site. Always lead with the measured distances, label the home figure an estimate, and cite `equity_home_sensitivity.csv`. It is now checked against PPS's *Enrollment by Neighborhood of Residence* report (`equity_home_check*.csv`): the increase holds up (+0.8 to +1.1 mi vs model +1.0), but the model overstates today's distance (1.8 vs 1.2 mi), so don't quote the model's absolute distances.
- **Whole-school vs program figures.** `school_demographics.csv` (source 12) is whole-school: it includes neighborhood-program students, who don't move. Say "schools losing a program are 51% underserved", never "movers are half underserved". For the movers themselves, use `equity_race_groups.csv` (Scenario A movers: 45% Latino, 13% Asian, 4% Black), plus home language and multilingual-learner share.
- **Black students and immersion.** Black students are 2% of K-8 immersion students (91 of 4,457) vs 8% of K-8 enrollment; 43 of the 91 are in MLK Jr.'s Mandarin program, which both scenarios move. The plan reaches Black students mainly through closures (247 in A) and through César Chávez's neighborhood program (143 students, 34% Black), which PPS moves to Rosa Parks/George to make César Chávez a K-5 Spanish hub (guide p. 3). The §1 "directly displaced" count includes those 143 (user decision, Oct 11, 2026). History context on the Equity page quotes PPS's own *Historical Context* page (source 24); don't add history claims without a verified quote.
- **Lent PK:** PPS school totals for Lent include pre-kindergarten (308 in 2023-24); PSU forecasts are K-12 (273). Compare forecasts with PSU's own actuals.
- **Two different 7% figures.** The audit appendix (p. 46) reports that Lent's pre-conversion students left PPS at 7% the year before the 2023 conversion and 13% in the conversion year. That is not the commenter's figure below; keep them apart.
- **Lent capture rate** fell 63% → 30% in 2023-24 partly by design (non-immersion neighborhood children were assigned to Marysville, which the report counts as "other neighborhood school"). Don't present it as families choosing to leave. For the Southeast trend, use `equity_capture.csv`, which excludes Lent.
- **The "7%" is not a PPS figure on record.** A public commenter at the Oct 6, 2026 board meeting attributed it to PPS, and it concerns leaving the district. PPS staff (Sept 8 committee) said students didn't necessarily leave the district but "may not have moved with the program". The SEGC equity audit found enrolled students generally followed moved programs. Don't summarize who *left* moved programs as "more often white": the audit doesn't define White vs Latino/a/x (likely non-Latino white, since it reports Latino/a/x as a parallel group), and it contradicts itself on the leavers' home language (p. 11 vs p. 49). Quote it with page numbers.
- **PPS's scenario projections exist** (per-school guides, `guide_*.csv`, Oct 8, 2026). Don't say PPS hasn't published school-level scenario enrollment. They give no capacity figures, only yes/no size and space goals. Current building capacity is in PPS's School Profiles dashboard (`school_profiles_2025.csv`, scraped; source 22). Use it, not the 2021 Long-Range Facility Plan (`facility_capacity_2021.csv`, comparison only). Don't say PPS publishes no current capacity. Implied by them: about 80% of a moved program arrives at the new school and about 20% stays at the old one (`equity_pps_follow.csv`). So don't claim PPS assumes everyone follows; the earlier 98% was PSU's 2023 forecast for Bridger → Lent.
- **Rigler loses its neighborhood boundary in both scenarios** (guide: "Rigler's non-DLI neighborhood boundary would shift to Scott K-5"; `dli_sites.csv` own_area true → false). Use the Rigler-vs-Lent contrast together with this, never Rigler alone as proof that the plan's hubs will work.
- **Richmond's map point was wrong upstream** (pps-explorer had it at Atkinson's location, SE 58th & Division). It is corrected here in `public/data/{sq,a,b}_k5_schools.geojson` to the Census geocode of 2276 SE 41st Ave (-122.620277, 45.506806). Re-running `scripts/pipeline/` would bring the wrong point back; re-apply the fix if so.
- **Atkinson has room for about 150 more students (~25 per grade; current capacity 519 vs 366 enrolled), enough for a second class per grade but not a doubling of its 178-student K-5 Spanish program, and not a whole-school program** unless its 188 neighborhood students move out (the Lent mistake). The whole-school Southeast option is Creston's building (0.8 mi from Atkinson vs 2.4 to Lent; current capacity 429, about 70 per grade; unreinforced masonry, needs seismic work). Don't use an assumed class size (the old "24 per class" isn't sourced).
- **"More Japanese than Spanish seats" is true only for the Southeast** (Richmond 89 K vs Lent + Atkinson 70, Oct 2025). District-wide Spanish K immersion is 306 vs Japanese 89.
- **No study compares whole-school vs. strand immersion outcomes** (search of Oct 9, 2026; see methods `#research`). RAND (Steele et al. 2017) tested immersion vs. not, never school structure. Don't cite the unverified "15 extra prep hours", burnout or "RAND RR-1765" claims. The Lent stayers' gains (audit p. 47) are the main local evidence for whole-school: always give their limits (43% who stayed, no comparison group, post-pandemic years, "do not prove causality"). Lent's ~60% departure includes 39 fifth-graders moving up as usual.
- **School changes page (`schools.qmd`, `school_changes.R`).** `data-raw/plan_flows.csv` is the hand-entered list of which current students go where, one row per PPS guide sentence; update it if PPS revises the guides. It is a snapshot (October 2025 students moved at once), so its student counts measure the size of each change, not children who will move (changes start 2027-28+; Sellwood's current students are gone by its 2028 closure). Say "groups that enroll about N students today", never "N current students would change buildings"; PPS's guide projections are the check (correlation 0.93), so quote PPS's own projected underserved share and Title I status where they exist. Marysville → Arleta (all), Sellwood split 36/64 and Odyssey as a program move (not a closure) are our assumptions; closures are 14 (A) / 11 (B).
- **Separation by race cuts both ways; say both.** Across all elementary buildings the dissimilarity index falls slightly, so don't say the plan makes the district more segregated. Locally it rises where immersion programs consolidate (Southeast Latino–white 0.35 → 0.58; Northeast up) and falls where neighborhood schools merge (Sabin into MLK Jr.). Counting programs as units, the hub moves barely change it: the split already existed inside the building, and what changes is sharing a building and its services. Middle schools: Latino–white rises 0.29 → 0.32.
- **Title I and SUN.** Title I = PPS's 2026-27 list (pps.net/Page/1395, 35 schools incl. 3 bridge schools: Arleta, Atkinson, Roosevelt). The guides' Title I column omits bridge schools; use the guides only for projected status after changes (Brentwood loses Title I in A and B, Markham in A, Arleta regains it). SUN = the county's August 2026 contact list (43 PPS sites); the county's printable SUN map is from 2018. The nine sites the county proposed cutting in 2026 were all restored (June 5, 2026 budget); 6 (A) / 5 (B) of them close. Neither PPS nor the county has said what happens to Title I money or a SUN site when a school closes. Title I counts on the School changes page are all students in each group (Title I is school-wide), never "low-income students": income is published for whole schools only.
- **Lee Elementary is now Sunrise** (2222 NE 92nd Ave). The October 2025 race report and the 2025-26 Title I list say Lee; the guides, profiles and 2026-27 lists say Sunrise.
- **PPS's subgroup table** is board PowerPoint slide 44 (K-8 students who move): multilingual learners 31%/28% vs all 27%/24%. PPS never defines "move".
