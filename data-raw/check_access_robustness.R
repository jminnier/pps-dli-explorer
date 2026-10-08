# Robustness check for the "within 1 mile of a K-5 Spanish site" figures (acs_language_access.R).
#
# The main method places every speaker in a tract at the tract's interior point. Here each tract's
# speakers are instead spread over its 2020 census blocks in proportion to the block's population
# under 18 (2020 Census redistricting file: P1_001N total minus P3_001N age 18+), and distance is
# measured from each block's interior point. Results are reported for several distance thresholds,
# with 90% margins of error for the speaker totals.
#
# Usage: Rscript data-raw/check_access_robustness.R  ->  data/access_robustness.csv (and a printed table)

suppressPackageStartupMessages({
  library(tidycensus); library(sf); library(dplyr); library(tidyr); library(readr)
})
options(tigris_use_cache = TRUE)
sf_use_s2(FALSE)

here <- function(...) file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)))), "..", ...)
CRS <- 2838
M_PER_MI <- 1609.344
THRESHOLDS <- c(0.5, 1, 1.5, 2)

cache <- here("data-raw", "acs", "decennial2020_blocks_u18.rds")
if (!file.exists(cache)) {
  b <- get_decennial("block", variables = c(total = "P1_001N", adult = "P3_001N"), year = 2020, sumfile = "pl",
                     state = "OR", county = c("Multnomah", "Washington", "Clackamas"), geometry = TRUE, output = "wide")
  saveRDS(b, cache)
}
blocks <- readRDS(cache) |> st_transform(CRS) |>
  mutate(u18 = pmax(total - adult, 0), tract = substr(GEOID, 1, 11))

acs <- read_csv(here("data", "acs_language_tract.csv"), show_col_types = FALSE, col_types = cols(geoid = "c"))
blocks <- blocks |> filter(tract %in% acs$geoid)
bpts <- st_point_on_surface(st_geometry(blocks))

sites <- read_csv(here("data", "dli_sites.csv"), show_col_types = FALSE) |>
  filter(language == "Spanish", band == "K-5", change != "removed" | is.na(change)) |>
  st_as_sf(coords = c("lon", "lat"), crs = 4326) |> st_transform(CRS)

dist_to <- function(pts, scen) {
  s <- sites |> filter(scenario == scen)
  apply(st_distance(pts, s), 1, min) / M_PER_MI
}

# block level: allocate each tract's school-age Spanish speakers by under-18 population
alloc <- blocks |> st_drop_geometry() |> select(GEOID, tract, u18) |>
  group_by(tract) |> mutate(w = if (sum(u18) > 0) u18 / sum(u18) else 1 / n()) |> ungroup() |>
  left_join(select(acs, geoid, sp517 = age5_17_spanish, sp5 = spanish), by = c(tract = "geoid")) |>
  mutate(sp517 = sp517 * w, sp5 = sp5 * w)
for (s in c("sq", "a", "b")) alloc[[paste0("d_", s)]] <- dist_to(bpts, s)

# tract level (the published method), for comparison
tr <- read_csv(here("data", "access_tract.csv"), show_col_types = FALSE, col_types = cols(geoid = "c")) |>
  filter(band == "K-5", language == "Spanish") |>
  select(geoid, scenario, dist_mi) |> pivot_wider(names_from = scenario, values_from = dist_mi, names_prefix = "d_") |>
  left_join(select(acs, geoid, sp517 = age5_17_spanish, sp5 = spanish), by = "geoid")

share <- function(d, n, t) sum(n[d <= t]) / sum(n)
rows <- list()
for (lvl in c("tract point", "blocks by under-18 population")) for (grp in c("sp517", "sp5")) for (t in THRESHOLDS) {
  x <- if (lvl == "tract point") tr else alloc
  rows[[length(rows) + 1]] <- tibble(
    placement = lvl, speakers = if (grp == "sp517") "Spanish, ages 5-17" else "Spanish, ages 5+", miles = t,
    sq = share(x$d_sq, x[[grp]], t), a = share(x$d_a, x[[grp]], t), b = share(x$d_b, x[[grp]], t))
}
out <- bind_rows(rows)
write_csv(out, here("data", "access_robustness.csv"))

cat(sprintf("%d blocks in %d tracts; school-age Spanish speakers %d (90%% MOE +/- %d); age 5+ %d (+/- %d)\n",
            nrow(blocks), n_distinct(blocks$tract), sum(acs$age5_17_spanish), round(sqrt(sum(acs$age5_17_spanish_moe^2))),
            sum(acs$spanish), round(sqrt(sum(acs$spanish_moe^2)))))
print(as.data.frame(out |> mutate(across(c(sq, a, b), \(v) sprintf("%.0f%%", 100 * v)))), row.names = FALSE)

# Sampling uncertainty: redraw each tract's school-age Spanish count from a normal distribution
# with its ACS standard error (90% MOE / 1.645, floored at 0), re-allocate to blocks, recompute.
set.seed(2026)
sims <- replicate(2000, {
  draw <- pmax(rnorm(nrow(acs), acs$age5_17_spanish, acs$age5_17_spanish_moe / 1.645), 0)
  n <- alloc$w * draw[match(alloc$tract, acs$geoid)]
  c(sq = share(alloc$d_sq, n, 1), a = share(alloc$d_a, n, 1))
})
ci <- apply(sims, 1, quantile, c(0.05, 0.95))
diff_ci <- quantile(sims["sq", ] - sims["a", ], c(0.05, 0.95))
cat(sprintf("\nBlocks, ages 5-17, 1 mile, 90%% intervals from ACS sampling error: status quo %.0f-%.0f%%, Scenario A/B %.0f-%.0f%%, drop %.0f-%.0f points\n",
            100 * ci[1, "sq"], 100 * ci[2, "sq"], 100 * ci[1, "a"], 100 * ci[2, "a"], 100 * diff_ci[1], 100 * diff_ci[2]))
write_csv(tibble(measure = c("sq", "a", "drop_points"), lo = c(ci[1, ], diff_ci[1]), hi = c(ci[2, ], diff_ci[2])),
          here("data", "access_robustness_ci.csv"))
