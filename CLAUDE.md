# CLAUDE.md

Guidance for working in this repository. See README.md for what the project is and how to rebuild it.

## Project in one paragraph

This is an independent analysis of how the Portland Public Schools (PPS) rightsizing Scenarios A and B (October 2026) affect dual language immersion (DLI). It is a Quarto website (R, plotly, gt) built from public PDFs that are parsed into tidy CSVs. It is a private copy of `browniefed/pps-explorer` by Jason Brown, which has no license. The `upstream` remote points to it, and its map app still lives at the repository root (`src/`, `public/`, `scripts/`, `tests/`). Keep the repository private, and always credit Jason Brown / pps-explorer, and ppsdata.info, which it credits.

## Layout

- `data-raw/`: source PDFs, and the parser and analysis scripts (Python with `pypdf`, Node, R).
- `data/`: cleaned tables, the only inputs the site reads.
- `R/site_data.R`: loads every table, plus `school_key()` (the same normalization as the map's `schoolKey`, so map, PPS and lottery names join), lottery summaries (`lottery_k`, `lottery_avg`), `strand_students()`, `heritage_share()`, and the source citations `SRC` / `cite()`.
- `R/charts.R`: `viz_layout()` for plotly styling.
- Pages: `index.qmd`, `scorecard.qmd`, `equity.qmd`, `methods.qmd`. Register new pages in `_quarto.yml` (`project.render` and `navbar`).

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

- **Cite everything.** Every table, figure, callout and headline number gets a source line: `tab_source_note(md(cite(...)))` for gt, or a `::: {.source}` block after a figure. Add new sources to `SRC` in `R/site_data.R` and to the sources table and calculation sections of `methods.qmd`.
- **Methods must keep pace.** Any new number needs its definition, formula and limitations in `methods.qmd`.
- **Parsers fail loudly.** Validate against totals printed in the source (row, school, section and district totals; printed percentages within ±0.51). Exit with a clear message rather than guess; leave a value blank if it is truly ambiguous.
- **Use computed values in prose.** Compute numbers inline (`` `r ...` ``); don't hard-code them, so the text can't drift from the data.
- **Charts:**
  - Use the validated palette in `PAL` (blue `#2a78d6`, orange `#eb6834`, aqua `#1baf7a`; gray for "unchanged").
  - Thin marks, a hover tooltip on every mark, a legend for two or more series, text in ink colors.
  - Never use two y-axes.
  - The site is light theme only.
- **Plotly sizing in Quarto:** set the height with the chunk option `#| fig-height:`, not `plot_ly(height = ...)`, which gets clipped by the container. If a chunk change doesn't take effect, delete `_freeze/<page>/`.
- **dplyr gotcha:** in `summarise()`, compute weighted means before overwriting the weight column (e.g. don't write `students = sum(students)` first).
- **zsh gotcha:** never use a variable named `path`; it overwrites `PATH`.
- **Census:** B16001 (separate Russian/Japanese) is published for states only; use C16001 (tracts) and B16007 (ages 5–17). Census downloads are cached in `data-raw/acs/` (git-ignored). The key is in `~/.Renviron`.
- **pps.net rate-limits** (HTTP 429): pause about 5 s between downloads. Current reports are at `/fs/resource-manager/view/<uuid>`; the old `/cms/lib/...` URLs return 404.

## Working style the user expects

- Delegate PDF parsing and web searching to subagents with `model: sonnet`. Leave their output uncommitted, then review, re-run and spot-check it before committing it yourself.
- Commit with clear messages ending in the Co-Authored-By line, and push to `origin main`. Don't contact upstream or publish anything without asking.
- Verify surprising claims before stating them, and say so plainly when a number was wrong.

## Substantive pitfalls (already made once; don't repeat)

- **Lottery ≠ demand at Lent and Rigler.** These all-immersion schools enroll neighborhood children without the lottery: Lent had 43 kindergartners vs 14 offers in 2025-26, and Rigler never appears in the lottery. Richmond and mixed-program schools do fill through the lottery. Never compare lottery counts across a change in how children enter a school (the withdrawn "Bridger→Lent applications fell 64%").
- **Compare like with like.** If one side is an all-grades average, the comparison must be too (the Bridger→Lent precedent: −31% vs −14% district on the same baseline, not −9%).
- **Bridger was K-5** when it had Spanish immersion; it became the K-8 Bridger Creative Science after 2023.
- **Whole-school immersion:** Lent and Rigler (Spanish) and Richmond (Japanese). Some PPS reports print them as a single unlabeled row, and the PSU forecast omits Richmond's Japanese row.
- **Lottery quirk:** the 2021-22 lottery report gives no grade for immersion rows, so lottery averages use 2022-23 to 2026-27.
- **Access figures use block-level allocation.** Tract interior points were threshold-sensitive (59→35% vs 52→36%). Report the 90% intervals from `access_robustness_ci.csv`.
- **Race of immersion programs isn't published.** PPS reports whole-school race only. Use home language (`enrollment_by_language.csv`) as the proxy, and say so.
- **Measured vs modeled distances.** School-to-school distances (1.7 vs 1.2 mi) are measured from the maps. The home-to-school increase (about +1.0 vs +0.5 mi) is a model: immersion families are assumed to live in the area nearest their program's current site. Always lead with the measured distances, label the home figure an estimate, and cite `equity_home_sensitivity.csv`. It is now checked against PPS's *Enrollment by Neighborhood of Residence* report (`equity_home_check*.csv`): the increase holds up (+0.8 to +1.1 mi vs model +1.0), but the model overstates today's distance (1.8 vs 1.2 mi), so don't quote the model's absolute distances.
- **Race and income are whole-school only** (`school_demographics.csv`, from PPS's ethnicity-by-program report; Clark is missing). They include neighborhood-program students, who don't move. Say "schools losing a program are 51% underserved", never "immersion families/movers are half underserved". For the movers themselves, use home language (29–34% Spanish at home) and multilingual-learner share (36%).
- **Lent PK:** PPS school totals for Lent include pre-kindergarten (308 in 2023-24); PSU forecasts are K-12 (273). Compare forecasts with PSU's own actuals.
- **Two different 7% figures.** The audit appendix (p. 46) reports that Lent's pre-conversion students left PPS at 7% the year before the 2023 conversion and 13% in the conversion year. That is not the commenter's figure below; keep them apart.
- **Lent capture rate** fell 63% → 30% in 2023-24 partly by design (non-immersion neighborhood children were assigned to Marysville, which the report counts as "other neighborhood school"). Don't present it as families choosing to leave. For the Southeast trend, use `equity_capture.csv`, which excludes Lent.
- **The "7%" is not a PPS figure on record.** A public commenter at the Oct 6, 2026 board meeting attributed it to PPS, and it concerns leaving the district. PPS staff (Sept 8 committee) said students didn't necessarily leave the district but "may not have moved with the program". The SEGC equity audit found enrolled students generally followed moved programs. Don't summarize who *left* moved programs as "more often white": the audit doesn't define White vs Latino/a/x (likely non-Latino white, since it reports Latino/a/x as a parallel group), and it contradicts itself on the leavers' home language (p. 11 vs p. 49). Quote it with page numbers.
- **PPS's scenario projections exist** (per-school guides, `guide_*.csv`, Oct 8, 2026). Don't say PPS hasn't published school-level scenario enrollment. They give no capacity figures, only yes/no size and space goals; building capacity comes from the 2021 Long-Range Facility Plan (`facility_capacity_2021.csv`; PPS's operating model differs for some buildings, e.g. Creston 282 without the annex vs 558). Implied by them: about 80% of a moved program arrives at the new school and about 20% stays at the old one (`equity_pps_follow.csv`). So don't claim PPS assumes everyone follows; the earlier 98% was PSU's 2023 forecast for Bridger → Lent.
- **Richmond's map point is wrong** in pps-explorer's `sq_k5_schools.geojson` / `dli_sites.csv`: it duplicates Atkinson's (SE 58th & Division). Richmond is on SE 41st/42nd just north of Division. Don't compute distances from it.
- **"More Japanese than Spanish seats" is true only for the Southeast** (Richmond 89 K vs Lent + Atkinson 70, Oct 2025). District-wide Spanish K immersion is 306 vs Japanese 89.
- **PPS's subgroup table** is board PowerPoint slide 44 (K-8 students who move): multilingual learners 31%/28% vs all 27%/24%. PPS never defines "move".
