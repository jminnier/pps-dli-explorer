# PPS Dual Language Immersion & Rightsizing

An independent analysis of what Portland Public Schools' rightsizing scenarios (A and B, released for the board on October 6, 2026) mean for **dual language immersion (DLI)** programs and the families in them: demand, sites, access, enrollment and equity. It is published as a Quarto website, built entirely from public PPS, Portland State University and US Census data.

This project builds on **[pps-explorer](https://github.com/browniefed/pps-explorer) by Jason Brown (@browniefed)**. pps-explorer provides the georeferenced attendance areas, the school locations and the transcription of the board memo that every scenario comparison here uses. Its address-lookup map is still in this repository. pps-explorer in turn credits [ppsdata.info](https://ppsdata.info) by Alex Meub.

> **Live site:** <https://pps-dli-explorer.netlify.app/> (Netlify). An older copy is on GitHub Pages. The repository is public. The upstream pps-explorer repository has no license; its author is credited throughout, and reuse terms have not yet been confirmed with him.

## What the site shows

| Page | Contents |
|---|---|
| `index.qmd`: Overview | Four headline numbers: K-5 Spanish sites (9 → 4), share of Spanish kindergarten lottery applications going to programs that move, students in moving programs, and school-age Spanish speakers within 1 mile of a K-5 site |
| `scorecard.qmd`: Demand & scorecard | Kindergarten lottery demand at each moving program vs its receiving school; the Bridger → Lent precedent (2023); Spanish waitlists over time; who is waitlisted; a scorecard of every program move; sites by language and grade band; distance to the nearest site |
| `equity.qmd`: Equity | PPS's own subgroup move rates (board slide 44) next to who the closures and immersion moves actually fall on (home language), and how far families' schools would move |
| `history.qmd`: Lent & César Chávez | Enrollment by program since 2019, the 2023 Bridger → Lent move and its projections, capture rates, César Chávez today, and PPS's projections for both schools to 2031-32 |
| `research.qmd`: Research | Whole-school vs. strand immersion: outcome studies, field guidance, case studies, PPS's Lent conversion (equity audit), and questions for the board |
| `es/*.qmd`: Spanish | Latin American Spanish version of every page (button **Español** / **English**); same R code and numbers; glossary in `es/GLOSSARY.md`; writing rules (plain language, GSA Spanish style) in `STYLE.md`; `tools/check_es_sync.py` warns when a Spanish page falls out of step |
| `methods.qmd`: Sources & methods | Every source, how each was parsed and checked, how each number is calculated, limitations, and how to reproduce |

## Repository layout

```
_quarto.yml, *.qmd        Quarto website (index, scorecard, equity, methods)
R/site_data.R             loads data/, school-name matching, helpers, source citations (SRC, cite())
R/charts.R                plotly styling (viz_layout)
styles/site.scss          site styles
data-raw/                 source documents (PDFs) and the scripts that turn them into tables
data/                     cleaned tables used by the site (CSV / GeoJSON)
public/, src/, scripts/,  the original pps-explorer map app (TanStack Start + Leaflet) and its
tests/, package.json      boundary-extraction pipeline
PLAN.md                   original project plan
```

## Data

Each source is saved under `data-raw/`, and each script stops on any row that fails its checks.

| Script | Source | Output (`data/`) |
|---|---|---|
| `parse_immersion_profiles.py` | PPS *Language Immersion Track Profiles*, Oct 2021–Oct 2025 | `dli_track_profiles.csv` |
| `parse_program_type.py` | PPS *Enrollment by Grade and Program Type*, Oct 2024–2025 | `enrollment_by_program_grade.csv` |
| `parse_language_by_school.py` | PPS *Enrollment by Language and School*, Oct 2024–2025 | `enrollment_by_language.csv` |
| `parse_lottery.py` | PPS lottery results summaries, 2021-22 to 2026-27 | `lottery_results.csv` |
| `parse_psu_forecast.py` | PSU Population Research Center forecasts (2025-26 and 2026-27 editions) | `psu_forecast.csv` |
| `export_dli_tables.mjs` | pps-explorer scenario maps and memo transcription | `dli_sites.csv`, `dli_moves.csv` |
| `acs_language_access.R` | ACS 2020–2024 (C16001, B16007) + 2020 Census blocks | `acs_language_tract.csv`, `tracts.geojson`, `access_*.csv` |
| `check_access_robustness.R` | same | `access_robustness*.csv` |
| `equity_analysis.R` | the tables above + scenario maps + census blocks | `equity_*.csv` |
| `parse_school_guides.py` | PPS *How Could Your School Be Impacted?* school guides (Oct 8, 2026) | `guide_enrollment.csv`, `guide_school.csv`, `guide_text.csv` |
| `parse_enroll_by_neighborhood.py` | PPS *School Enrollment by Neighborhood of Residence*, Oct 2023–Oct 2025 | `enroll_by_neighborhood.csv` |
| `check_home_distance.R` | the table above + scenario maps + census blocks | `equity_home_check*.csv` |
| `parse_lrfp_capacity.py` | PPS *Long-Range Facility Plan 2021* (via [meub/pps-data](https://github.com/meub/pps-data), MIT) | `facility_capacity_2021.csv` |
| `parse_capture_rate.py` | PPS *Neighborhood Capture Rate Metrics*, Oct 2019–Oct 2025 | `capture_rate.csv` |
| copied by hand | PPS *Class Size Detail*; PPS board slide 44 | `class_size_kg.csv`, `pps_slide44.csv` |

Other saved documents: `data-raw/pps_board/` (October 2026 board packet: PowerPoint, memo, district and regional summaries, ethnicity-by-program reports) and `data-raw/savepdxschools/` (PPS metrics compiled by [Save PDX Schools](https://savepdxschools.org/); no license stated, so credit them if used).

## Reproduce

Requirements:
- Python 3 with `pypdf`.
- Node 22.
- R with `tidycensus`, `sf`, `dplyr`, `tidyr`, `readr`, `stringr`, `jsonlite`, `gt`, `plotly`.
- Quarto.
- A free [Census API key](https://api.census.gov/data/key_signup.html) in `CENSUS_API_KEY` (e.g. in `~/.Renviron`).

```sh
python3 data-raw/parse_immersion_profiles.py
python3 data-raw/parse_program_type.py
python3 data-raw/parse_language_by_school.py
python3 data-raw/parse_lottery.py
python3 data-raw/parse_psu_forecast.py
node    data-raw/export_dli_tables.mjs
Rscript data-raw/acs_language_access.R      # caches Census downloads in data-raw/acs/ (git-ignored)
Rscript data-raw/check_access_robustness.R
Rscript data-raw/equity_analysis.R
Rscript data-raw/check_home_distance.R
Rscript data-raw/history_tables.R
quarto render                               # -> _site/
quarto preview                              # live local preview
quarto publish netlify --no-prompt         # render and publish to Netlify (site id in _publish.yml)
```

## The pps-explorer map app

The original map (address lookup across the status quo and Scenarios A and B) is unchanged at the repository root. See the [upstream README](https://github.com/browniefed/pps-explorer#readme). In short: `npm install && npm run dev` (Node 22.12+), then open http://localhost:3000; `npm test` runs its data tests. Its boundary data comes from the PPS scenario map PDFs via `scripts/pipeline/`.

## Caveats

This is not a PPS publication; where it differs from PPS documents, PPS is authoritative. The main caveats (all detailed on the methods page):
- Lottery counts are applications, not children.
- Lent's and Rigler's neighborhood children enroll in immersion without entering the lottery.
- The Census reports Russian and Japanese only at the state level.
- Distances are straight-line.
- The race/ethnicity of immersion programs isn't published.
