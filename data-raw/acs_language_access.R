# Home-language counts by census tract (ACS 5-year) and straight-line distance from each tract and
# each attendance area to the nearest DLI site of the same language, per scenario and grade band.
#
# Inputs
#   ACS 2020-2024 5-year, tract level, Multnomah, Washington and Clackamas counties (OR):
#     C16001  language spoken at home, population 5+: Spanish, Chinese (incl. Mandarin),
#             Vietnamese, "Russian, Polish, or other Slavic" (stands in for Russian; in Portland it
#             also counts Ukrainian speakers) and "Other Asian and Pacific Island" (Japanese is in
#             here and has no tract-level count). The detailed table B16001, which lists Russian
#             and Japanese separately, is published for states only: tract and county values are NA.
#     B16007  language spoken at home by age; used for school-age (5-17) counts, which ACS gives
#             only for Spanish, other Indo-European, Asian and Pacific Island, and other
#   public/data/sq_912.geojson   district outline (union of the 9-12 areas)
#   public/data/sq_k5.geojson, sq_68.geojson   status quo attendance areas
#   data/dli_sites.csv           DLI sites per scenario, band and language (export_dli_tables.mjs)
#
# A tract is in the district when its interior point (sf::st_point_on_surface) is; distances run
# from that point. Distances are straight-line, in miles, in Oregon North (EPSG:2838).
# The Census API is called without a key (fine at this volume); set CENSUS_API_KEY to use one.
# Raw ACS results are cached in data-raw/acs/ so reruns don't call the API.
#
# Usage: Rscript data-raw/acs_language_access.R
#   -> data/acs_language_tract.csv, data/tracts.geojson, data/access_tract.csv, data/access_area.csv

suppressPackageStartupMessages({
  library(tidycensus); library(sf); library(dplyr); library(tidyr); library(readr)
})
options(tigris_use_cache = TRUE)
sf_use_s2(FALSE)

ACS_YEAR <- 2024
COUNTIES <- c("Multnomah", "Washington", "Clackamas")
CRS <- 2838 # NAD83(HARN) / Oregon North, metres
M_PER_MI <- 1609.344
LANGUAGES <- c("Spanish", "Mandarin", "Japanese", "Russian", "Vietnamese")

here <- function(...) file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)))), "..", ...)
dir.create(here("data-raw", "acs"), showWarnings = FALSE)

vars <- c(
  pop5 = "C16001_001", english_only = "C16001_002", spanish = "C16001_003", slavic = "C16001_012",
  chinese = "C16001_021", vietnamese = "C16001_024", other_asian_pacific = "C16001_030",
  age5_17 = "B16007_002", age5_17_spanish = "B16007_004", age5_17_other_indo_european = "B16007_005",
  age5_17_asian_pacific = "B16007_006"
)

# ---- ACS (cached) ------------------------------------------------------------------------------
cache <- here("data-raw", "acs", sprintf("acs5_%d_tracts_c16001.rds", ACS_YEAR))
if (!file.exists(cache)) {
  acs <- get_acs("tract", variables = vars, state = "OR", county = COUNTIES, year = ACS_YEAR,
                 survey = "acs5", geometry = TRUE, cb = TRUE, output = "wide")
  saveRDS(acs, cache)
}
acs <- readRDS(cache) |> st_transform(CRS)

# ---- district and tracts -----------------------------------------------------------------------
district <- st_read(here("public", "data", "sq_912.geojson"), quiet = TRUE) |>
  st_transform(CRS) |> st_make_valid() |> st_union() |> st_buffer(0)

pts <- st_point_on_surface(st_geometry(acs))
inside <- lengths(st_intersects(pts, district)) > 0
tracts <- acs[inside, ]
tract_pts <- pts[inside]
xy <- st_coordinates(st_transform(tract_pts, 4326))

est <- function(v) tracts[[paste0(v, "E")]]
moe <- function(v) tracts[[paste0(v, "M")]]
lang_tract <- tibble(
  geoid = tracts$GEOID, name = tracts$NAME, lon = round(xy[, 1], 6), lat = round(xy[, 2], 6),
  !!!setNames(lapply(names(vars), est), names(vars)),
  !!!setNames(lapply(names(vars), moe), paste0(names(vars), "_moe"))
)
write_csv(lang_tract, here("data", "acs_language_tract.csv"), na = "")

# simplified tract polygons for the map (clipped to the district)
st_intersection(tracts["GEOID"], district) |>
  st_simplify(dTolerance = 15, preserveTopology = TRUE) |>
  rename(geoid = GEOID) |> st_transform(4326) |>
  st_write(here("data", "tracts.geojson"), delete_dsn = TRUE, quiet = TRUE,
           layer_options = "COORDINATE_PRECISION=5")

# ---- distances to nearest same-language site ---------------------------------------------------
sites <- read_csv(here("data", "dli_sites.csv"), show_col_types = FALSE) |>
  filter(change != "removed" | is.na(change)) |>
  st_as_sf(coords = c("lon", "lat"), crs = 4326) |> st_transform(CRS)

nearest <- function(from, ids) {
  # one row per from-point x scenario x band x language that has at least one site
  combos <- sites |> st_drop_geometry() |> distinct(scenario, band, language)
  bind_rows(lapply(seq_len(nrow(combos)), function(i) {
    c <- combos[i, ]
    s <- sites |> filter(scenario == c$scenario, band == c$band, language == c$language)
    d <- st_distance(from, s)
    j <- apply(d, 1, which.min)
    tibble(id = ids, scenario = c$scenario, band = c$band, language = c$language,
           nearest_school = s$school[j], dist_mi = round(as.numeric(d[cbind(seq_along(j), j)]) / M_PER_MI, 3))
  }))
}

access_tract <- nearest(tract_pts, tracts$GEOID) |> rename(geoid = id)
write_csv(access_tract, here("data", "access_tract.csv"))

areas <- bind_rows(
  st_read(here("public", "data", "sq_k5.geojson"), quiet = TRUE) |> mutate(area_band = "K-5"),
  st_read(here("public", "data", "sq_68.geojson"), quiet = TRUE) |> mutate(area_band = "6-8")
) |> st_transform(CRS)
area_pts <- st_point_on_surface(st_geometry(st_make_valid(areas)))
access_area <- nearest(area_pts, seq_len(nrow(areas))) |>
  mutate(area = areas$name[id], area_band = areas$area_band[id]) |>
  filter(band == area_band) |>
  select(area, band, scenario, language, nearest_school, dist_mi)
write_csv(access_area, here("data", "access_area.csv"))

# ---- summary -----------------------------------------------------------------------------------
speakers <- lang_tract |>
  # Mandarin <- all Chinese; Russian <- Russian, Polish or other Slavic; no tract count for Japanese
  transmute(geoid, Spanish = spanish, Mandarin = chinese, Russian = slavic, Vietnamese = vietnamese) |>
  pivot_longer(-geoid, names_to = "language", values_to = "speakers")
summ <- access_tract |> filter(band == "K-5") |> inner_join(speakers, by = c("geoid", "language")) |>
  group_by(language, scenario) |>
  summarise(mean_mi = round(weighted.mean(dist_mi, speakers), 2),
            within_1mi = round(100 * sum(speakers[dist_mi <= 1]) / sum(speakers)),
            within_2mi = round(100 * sum(speakers[dist_mi <= 2]) / sum(speakers)),
            speakers = sum(speakers), .groups = "drop") |>
  arrange(factor(language, LANGUAGES), factor(scenario, c("sq", "a", "b")))
cat(sprintf("%d tracts in district (ACS %d-%d 5-year)\n", nrow(tracts), ACS_YEAR - 4, ACS_YEAR))
cat("Speakers (age 5+) by distance to nearest same-language K-5 DLI site:\n")
print(as.data.frame(summ), row.names = FALSE)
kids <- access_tract |> filter(band == "K-5", language == "Spanish") |>
  inner_join(select(lang_tract, geoid, speakers = age5_17_spanish), by = "geoid") |>
  group_by(scenario) |>
  summarise(mean_mi = round(weighted.mean(dist_mi, speakers), 2),
            within_1mi = round(100 * sum(speakers[dist_mi <= 1]) / sum(speakers)),
            within_2mi = round(100 * sum(speakers[dist_mi <= 2]) / sum(speakers)),
            speakers = sum(speakers), .groups = "drop") |>
  arrange(factor(scenario, c("sq", "a", "b")))
cat("School-age (5-17) Spanish speakers, same measure:\n")
print(as.data.frame(kids), row.names = FALSE)
cat("wrote data/acs_language_tract.csv, data/tracts.geojson, data/access_tract.csv, data/access_area.csv\n")
