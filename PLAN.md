# Plan: PPS DLI Rightsizing Explorer (fork of browniefed/pps-explorer)

## Context

[browniefed/pps-explorer](https://github.com/browniefed/pps-explorer) is a React/Leaflet map of Portland Public Schools boundaries under the Status Quo and the rightsizing Scenarios A and B released Oct 6, 2026. It already contains much of what a DLI view needs:
- school labels on the maps that name each immersion program (e.g. "Rigler K-5 Spanish Immersion")
- every program move in the board memo, copied by hand into `src/lib/changes-data.mjs`: Scott→Rigler, Atkinson→Lent, Beach/James John/Sitton→César Chávez, Clark→Woodstock, Rose City Park→Vestal (A only), and others
- an overlay with rings per language and arrows for program moves (`src/lib/programs.mjs`)

The goal is a copy under the user's GitHub account that focuses on dual language immersion (DLI):
- **Access and distance:** how far families are from a site in their language, by scenario
- **Enrollment and demographics:** DLI enrollment and student mix per site
- **Per-language scorecard:** sites, moves and students affected, by scenario
- **DLI enrollment projections:** per school, over the coming years
- **Lent and César Chávez:** how enrollment changed over the past 5 years

It will be a **Quarto website on GitHub Pages**. Interactive parts use **Shinylive (R running in the browser via webR)**, so there's no server. The existing map app is kept and published under `/map/` on the same site, and the Quarto pages link to it for address lookup.

**License caveat:** the upstream repo has **no LICENSE file**. Forking on GitHub is allowed under GitHub's terms, but publishing a modified copy isn't clearly permitted. Step 0 handles this.

## Architecture

```
pps_explorer_dli_2026/            (clone of your fork; this folder is currently empty)
├── _quarto.yml                   website config, navbar, shinylive filter
├── index.qmd                     overview + headline per-language scorecard
├── scorecard.qmd                 interactive scorecard (shinylive-r)
├── access.qmd                    distance / access by language & scenario (shinylive-r + leaflet)
├── history.qmd                   5-yr enrollment trends, Lent & César Chávez focus (static R)
├── projections.qmd               interactive DLI projection model (shinylive-r)
├── methods.qmd                   sources, definitions, caveats, data gaps
├── R/                            shared functions (sourced at render time AND bundled into shinylive apps)
│   ├── dli_sites.R               DLI site table per scenario (port of languagesOf/immersionSites)
│   ├── projection.R              cohort-survival model + scenario adjustments
│   └── access.R                  distance helpers
├── data-raw/                     offline R scripts that fetch/clean public data → data/
├── data/                         small processed CSV/GeoJSON committed to repo (read by webR)
├── tests/testthat/               tests for R/ functions
├── map/                          upstream app (src/, public/, scripts/pipeline/, package.json …) moved here
└── .github/workflows/publish.yml build map + render Quarto + deploy to Pages
```

How the work is split:
- **Data fetching and heavy geometry run offline in R** (`data-raw/`, using sf and tidycensus). The outputs are small CSVs, because webR can't call the Census API (no CORS support, and it needs an API key), and running sf in the browser is slow.
- **The browser only does interactive work:** sliders for projection assumptions, scenario and language filters, and redrawing charts and the leaflet map.
- **Static charts are rendered once at build time** with ordinary `{r}` chunks. Only the interactive pieces use webR, which keeps page loads fast.

## Steps

### 0. Fork and housekeeping
1. Open an issue on browniefed/pps-explorer asking the author to add a license (e.g. MIT), and credit them prominently either way.
2. Fork to your GitHub account and rename the fork (e.g. `pps-dli-explorer`). Clone it into this folder.
3. Keep `upstream` as a git remote so boundary and memo fixes can be merged in later.
4. Move the app into `map/` with `git mv`, so later upstream merges still apply to the right files (merges may need `-X subtree=map`).

### 1. Publish the map app as a static site under `/map/`
- `map/vite.config.ts`:
  - Set `base: '/<repo>/map/'`.
  - Turn on TanStack Start SPA/prerender mode.
  - Drop `@cloudflare/vite-plugin` from the Pages build. Keep `wrangler.jsonc` in case you want Cloudflare later.
- Check that the data `fetch` calls in `map/src/components/BoundaryMap.tsx` and `map/src/routes/index.tsx` use paths relative to `base`.
- Small DLI-focused changes to the map:
  - Turn on the immersion overlay by default.
  - Add a deep-link parameter so Quarto pages can open the map at a given school or scenario. The URL hash state already exists.
- Run `npm test` in `map/` to confirm the existing tests still pass (`tests/programs.test.mjs` already checks DLI sites and moves).

### 2. Data layer (`data-raw/` → `data/`)
| Script | Source | Output |
|---|---|---|
| `01_dli_sites.R` | `map/public/data/*_schools.geojson` (labels → language, using the same regex as `programs.mjs::languagesOf`) and `map/src/lib/changes-data.mjs` program moves, copied into a CSV | `dli_sites.csv` (school, language, grade band, scenario, own_area, lon/lat) and `dli_moves.csv` (from, to, language, scenario) |
| `02_ode_membership.R` | ODE **Fall Membership Reports** 2021-22 → 2025-26 (school × grade × race/ethnicity) | `enrollment_history.csv` |
| `03_ode_profiles.R` | ODE **At-a-Glance school profiles** and English learner reports (% EL, % economically disadvantaged, languages spoken) | `school_demographics.csv` |
| `04_dli_enrollment.R` | DLI-specific counts: PPS school choice/lottery results by program, Oct 2026 board-packet school profiles, [ppsdata.info / meub/pps-data](https://github.com/meub/pps-data) (MIT) | `dli_enrollment.csv` (school × language × grade × year) |
| `05_forecast.R` | PSU Population Research Center PPS enrollment forecast (school-level projections), plus the 2031-32 figures in the board packet | `forecast.csv` |
| `06_acs_language.R` | ACS 5-yr table C16001 (language spoken at home) by block group, via tidycensus, clipped to the district (union of the `sq_912` areas) | `acs_language_bg.csv` (block-group centroid, counts by language) |
| `07_access.R` | sf: distance from each block-group centroid and each K-5 area centroid to the nearest same-language DLI site, per scenario | `access_bg.csv`, `access_area.csv` |

**Known data gap:** ODE reports total school enrollment and doesn't split out DLI strands. César Chávez and Lent both have DLI and neighborhood strands, so if PPS doesn't publish strand-level counts, a **public records request to PPS** may be needed. Until then:
- Show total enrollment alongside any DLI estimates, and label which is which.
- Mark every number with its source and year in `methods.qmd`.

### 3. Pages
- **index.qmd / scorecard.qmd:** for each language (Spanish, Mandarin, Japanese, Vietnamese, Russian) and scenario, show:
  - number of K-5, 6-8 and 9-12 sites
  - sites gained, lost and moved
  - students in strands that move (from `dli_enrollment` × `dli_moves`)
  - whether the K-5→6-8→9-12 pathway is intact

  Shinylive app with scenario and language filters; gt or DT table.
- **access.qmd:**
  - Leaflet map of DLI sites by scenario, colored with the upstream `PROGRAM_COLORS`.
  - Change in distance per K-5 area from Status Quo to A or B.
  - Headline metric: "% of heritage-language households within X miles of a same-language site," using the ACS data, with a slider for X.
  - Link to `/map/` for looking up a specific address.
- **history.qmd** (static):
  - 5-year enrollment trends at Lent and César Chávez: total, by grade, DLI vs neighborhood where data exists, and demographics.
  - The same trends for all DLI sites, in small multiples.
  - Notes on context, such as Atkinson Spanish moving to Lent and Beach, James John and Sitton Spanish moving to Chávez.
- **projections.qmd** (Shinylive):
  - Model in `R/projection.R`: a **cohort-survival / grade-progression-ratio model** for each school and language strand.
  - Inputs:
    - kindergarten entry, from recent averages or scaled to the PSU forecast
    - progression ratios, from 5-year history
    - for scenarios A and B, receiving-strand enrollment = sum of the sending strands × a **"follow-the-program" retention** slider (the share of families who move with a relocated program)
  - Output: projected DLI enrollment by school, 2026-27 → 2031-32, for SQ/A/B, with uncertainty bands from the spread in historical ratios.
  - Cross-check against the PSU forecast and the board packet's 2031-32 figures.
- **methods.qmd:** sources, definitions (what counts as a DLI site, what "distance" means), caveats, data gaps, and credit to upstream and ppsdata.info.

### 4. Shinylive and Quarto setup
- Install the extension with `quarto add quarto-ext/shinylive`, then add `filters: [shinylive]` to `_quarto.yml`.
- Use only packages available in webR: shiny, dplyr, tidyr, ggplot2, leaflet, DT/gt. Check leaflet and gt in the webR repo first, and fall back to plotly or ggplot if either is missing.
- Load data in the apps with `read.csv()` from `data/` URLs (served next to the pages). Bundle the `R/` helpers into the app with `## file:` directives so the static pages and the apps use the same code.

### 5. Deploy (`.github/workflows/publish.yml`)
1. `actions/setup-node` → `npm ci && npm run build` in `map/` → copy the build output to `_site/map/`.
2. `r-lib/actions/setup-r` and `quarto-dev/quarto-actions/setup` → `quarto render`.
3. `actions/upload-pages-artifact` → `actions/deploy-pages`. In repo settings, set Pages to deploy from GitHub Actions.

The `data-raw/` scripts run locally because they need the Census API key. Their outputs are committed, so CI never needs secrets.

## Verification
- `cd map && npm test && npm run build`: the upstream tests still pass, and the build works with the `/map/` base.
- `Rscript -e 'testthat::test_dir("tests/testthat")'`:
  - The `dli_sites.csv` site list matches the expected sets in `map/tests/programs.test.mjs`:
    - Rigler, Kelly, César Chávez and Richmond are immersion-only in A and B
    - the move lists match per scenario
  - Projection backtest: fit on 2021-22 → 2024-25, predict 2025-26, and report the error per school.
  - The projection model reproduces the input history exactly in the years it was fit on.
- `quarto preview`: every page renders, each Shinylive app loads in the browser, sliders update the outputs, and the link to `/map/` opens the right view.
- Spot-check the Lent and César Chávez numbers by hand against the ODE spreadsheets.
- After pushing, check the live GitHub Pages URL in a fresh browser, including on a phone.

## Open items to confirm during implementation
- Whether PPS publishes DLI strand enrollment publicly. If not, file a public records request.
- That leaflet and gt are available in webR.
- TanStack Start SPA mode with a sub-path base. If it's awkward, the archived `map/public/original` viewer is a fallback.
