# Spanish-speaking children ages 5-17 within 2 miles (straight line) of Lent and Atkinson, split by whether
# they live inside PPS. For the Rumors & Facts page. Uses the same block allocation as acs_language_access.R:
# each tract's B16007 count is spread over its 2020 blocks by population under 18.
#
# Inputs: data-raw/acs/acs5_2024_tracts_c16001.rds, data-raw/acs/decennial2020_blocks_u18.rds, public/data/sq_912.geojson,
#         data/plan_school_points.csv
# Output: data/facts_spanish_kids_2mi.csv

suppressPackageStartupMessages({library(sf); library(dplyr); library(readr); library(here)})
sf_use_s2(FALSE)
CRS <- 2838
RADIUS <- 2 * 1609.344
# All tracts in the three counties: data/acs_language_tract.csv keeps only tracts in PPS, which would drop the children outside it.
tr <- readRDS(here("data-raw", "acs", "acs5_2024_tracts_c16001.rds")) |> st_drop_geometry() |>
  transmute(geoid = GEOID, age5_17_spanish = age5_17_spanishE, age5_17_spanish_moe = age5_17_spanishM)
blocks <- readRDS(here("data-raw", "acs", "decennial2020_blocks_u18.rds")) |> st_transform(CRS) |>
  mutate(u18 = pmax(total - adult, 0), tract = substr(GEOID, 1, 11)) |>
  group_by(tract) |> mutate(w = if (sum(u18) > 0) u18 / sum(u18) else 1 / n()) |> ungroup()
pts <- st_point_on_surface(st_geometry(blocks))
pps <- st_read(here("public", "data", "sq_912.geojson"), quiet = TRUE) |> st_transform(CRS) |> st_make_valid() |> st_union()
in_pps <- lengths(st_intersects(pts, pps)) > 0
d <- blocks |> st_drop_geometry() |> mutate(in_pps = in_pps) |>
  left_join(select(tr, tract = geoid, kids = age5_17_spanish, kids_moe = age5_17_spanish_moe), by = "tract") |>
  mutate(est = w * kids)
stopifnot(abs(sum(d$est, na.rm = TRUE) - sum(tr$age5_17_spanish, na.rm = TRUE)) / sum(tr$age5_17_spanish, na.rm = TRUE) < 0.001)

sch_pts <- read_csv(here("data", "plan_school_points.csv"), show_col_types = FALSE) |> filter(key %in% c("lent", "atkinson")) |>
  st_as_sf(coords = c("lon", "lat"), crs = 4326) |> st_transform(CRS)
out <- bind_rows(lapply(c("lent", "atkinson"), function(s) {
  p <- filter(sch_pts, key == s)
  stopifnot(nrow(p) == 1)
  near <- as.numeric(st_distance(pts, st_geometry(p))) <= RADIUS
  x <- d[near, ]
  stopifnot(!anyNA(x$est))
  touched <- distinct(x, tract, kids_moe)
  tibble(key = s, kids = sum(x$est, na.rm = TRUE), inside_pps = sum(x$est[x$in_pps], na.rm = TRUE), outside_pps = sum(x$est[!x$in_pps], na.rm = TRUE),
         missing_blocks = sum(is.na(x$est)), moe_sum = sum(touched$kids_moe, na.rm = TRUE),
         moe_tracts = sqrt(sum(touched$kids_moe^2, na.rm = TRUE))) |>
    mutate(pct_outside = 100 * outside_pps / kids)
}))
write_csv(out, here("data", "facts_spanish_kids_2mi.csv"))
print(as.data.frame(out))
