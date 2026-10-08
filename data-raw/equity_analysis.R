# Who the scenarios' school changes fall on: students in immersion programs that move vs students at
# schools that close, compared with the district, plus how far their school moves and an estimate of
# the change in home-to-school distance.
#
# Inputs (all in data/ or public/data/; see methods.qmd):
#   dli_moves.csv                    program moves and the César Chávez 6-8 grade change (export_dli_tables.mjs)
#   dli_sites.csv                    immersion sites per scenario, band and language
#   enrollment_by_program_grade.csv  October 2025 enrollment by school, program, grade
#   enrollment_by_language.csv       October 2025 home language by school and program
#   public/data/<scen>_<band>.geojson, <scen>_<band>_schools.geojson   attendance areas and school points (pps-explorer)
#   src/lib/changes-data.mjs         closures (read via node)
#   data-raw/acs/decennial2020_blocks_u18.rds   2020 census blocks with population under 18 (acs_language_access.R)
#   data/acs_language_tract.csv      ACS school-age Spanish speakers by tract
#
# Outputs:
#   data/equity_groups.csv     one row per scenario x group (DLI moves, closures, district)
#   data/equity_changes.csv    one row per scenario x change (each program move or closure)
#   data/equity_home_distance.csv  home-to-school distance before/after, per scenario x change
#
# Usage: Rscript data-raw/equity_analysis.R

suppressPackageStartupMessages({
  library(sf); library(dplyr); library(tidyr); library(readr); library(jsonlite)
})
sf_use_s2(FALSE)
here <- function(...) file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)))), "..", ...)
old_wd <- setwd(here()); source("R/site_data.R"); setwd(old_wd)
CRS <- 2838
M_PER_MI <- 1609.344
YEAR <- "2025-26"
BANDS_FILE <- c(`K-5` = "k5", `6-8` = "68", `9-12` = "912")

# ---- closures (from the map's memo transcription) ----------------------------------------------
closures <- fromJSON(system2("node", c("--input-type=module", "-e", shQuote(
  'import { CHANGES } from "./src/lib/changes-data.mjs";
   const out = []; for (const s of ["a","b"]) for (const e of CHANGES[s]) if (e.kind === "close") out.push({ scenario: s, school: e.school });
   console.log(JSON.stringify(out));')), stdout = TRUE, env = character()))
closures <- as_tibble(closures) |> mutate(key = school_key(school))

pts <- function(scen, band) {
  st_read(here("public", "data", sprintf("%s_%s_schools.geojson", scen, BANDS_FILE[[band]])), quiet = TRUE) |>
    mutate(key = school_key(name)) |> st_transform(CRS)
}
areas <- function(scen, band) {
  st_read(here("public", "data", sprintf("%s_%s.geojson", scen, BANDS_FILE[[band]])), quiet = TRUE) |>
    st_make_valid() |> mutate(key = school_key(name)) |> st_transform(CRS)
}
band_of_school <- function(key) {
  for (b in names(BANDS_FILE)) if (key %in% areas("sq", b)$key) return(b)
  NA_character_
}

L <- by_lang |> filter(year == YEAR)
mix <- function(k, prog_language = NA) {
  d <- L |> filter(key == k, if (is.na(prog_language)) is.na(program_language) else program_language %in% prog_language)
  tibble(n = sum(d$students), spanish = sum(d$students[d$language == "Spanish"]), non_english = sum(d$students[d$language != "English"]))
}

# ---- each change: students, home language, school-to-school distance ---------------------------
dli <- moves |> rowwise() |>
  mutate(students = strand_students(from_key, language, band),
         m = list(mix(from_key, language)),
         pct_spanish_home = m$spanish / m$n, pct_non_english_home = m$non_english / m$n,
         school_miles = as.numeric(st_distance(st_sfc(st_point(c(from_lon, from_lat)), crs = 4326) |> st_transform(CRS),
                                               st_sfc(st_point(c(to_lon, to_lat)), crs = 4326) |> st_transform(CRS))) / M_PER_MI) |>
  ungroup() |>
  transmute(scenario, type = "Immersion program moves", language, band, from_school, to_school,
            students, pct_spanish_home, pct_non_english_home, school_miles)

clo <- bind_rows(lapply(seq_len(nrow(closures)), function(i) {
  c <- closures[i, ]; b <- band_of_school(c$key)
  sq_pt <- pts("sq", b) |> filter(key == c$key) |> slice(1)
  sq_area <- areas("sq", b) |> filter(key == c$key)
  # where the closing school's area goes on the scenario map: receiving schools weighted by area overlap
  sc_areas <- areas(c$scenario, b)
  ov <- suppressWarnings(st_intersection(select(sc_areas, recv = key), st_geometry(sq_area))) |>
    mutate(a = as.numeric(st_area(geometry))) |> st_drop_geometry() |> group_by(recv) |> summarise(a = sum(a)) |>
    filter(a > 0.02 * sum(a))
  recv_pts <- pts(c$scenario, b) |> filter(key %in% ov$recv) |> group_by(key) |> slice(1) |> ungroup()
  d <- as.numeric(st_distance(sq_pt, recv_pts)) / M_PER_MI
  w <- ov$a[match(recv_pts$key, ov$recv)]
  m <- mix(c$key)
  tibble(scenario = c$scenario, type = "School closures (non-immersion students)", language = NA, band = b,
         from_school = c$school, to_school = paste(recv_pts$key, collapse = "; "),
         students = m$n, pct_spanish_home = m$spanish / m$n, pct_non_english_home = m$non_english / m$n,
         school_miles = sum(d * w) / sum(w))
}))
changes <- bind_rows(dli, clo)
write_csv(changes, here("data", "equity_changes.csv"))

district <- L |> summarise(n = sum(students), spanish = sum(students[language == "Spanish"]), non_english = sum(students[language != "English"]))
groups <- changes |> group_by(scenario, type) |>
  summarise(school_miles = weighted.mean(school_miles, students), spanish_home = sum(students * pct_spanish_home),
            non_english_home = sum(students * pct_non_english_home), students = sum(students), .groups = "drop") |>
  bind_rows(tibble(scenario = c("a", "b"), type = "All PPS students", students = district$n,
                   spanish_home = district$spanish, non_english_home = district$non_english, school_miles = NA)) |>
  mutate(pct_spanish_home = spanish_home / students, pct_non_english_home = non_english_home / students)
write_csv(groups, here("data", "equity_groups.csv"))

# ---- home-to-school distance, estimated from census blocks -------------------------------------
# Children (population under 18, 2020 Census) in each block are assigned to the school they would
# attend today and under the scenario:
#   immersion: the block's nearest current site of that language and grade band is its program
#     (a catchment by proximity); after the move, the program's new school.
#   closures: the closing school's status-quo attendance area; after, the school whose scenario
#     attendance area contains the block.
# For Spanish, a second weighting uses school-age Spanish speakers (ACS tract counts spread over
# blocks by under-18 population).
blocks <- readRDS(here("data-raw", "acs", "decennial2020_blocks_u18.rds")) |> st_transform(CRS) |>
  mutate(u18 = pmax(total - adult, 0), tract = substr(GEOID, 1, 11))
acs <- read_csv(here("data", "acs_language_tract.csv"), show_col_types = FALSE, col_types = cols(geoid = "c"))
blocks <- blocks |> filter(tract %in% acs$geoid) |>
  group_by(tract) |> mutate(w = if (sum(u18) > 0) u18 / sum(u18) else 1 / n()) |> ungroup() |>
  mutate(sp517 = w * acs$age5_17_spanish[match(tract, acs$geoid)])
bp <- st_point_on_surface(st_geometry(blocks))

site_pts <- sites |> filter(change != "removed" | is.na(change)) |>
  st_as_sf(coords = c("lon", "lat"), crs = 4326) |> st_transform(CRS) |> mutate(key = school_key(school))

home <- list()
for (i in seq_len(nrow(moves))) {
  mv <- moves[i, ]
  cur <- site_pts |> filter(scenario == "sq", band == mv$band, language == mv$language)
  near <- apply(st_distance(bp, cur), 1, which.min)
  inside <- cur$key[near] == mv$from_key
  if (!any(inside)) next
  from_pt <- cur |> filter(key == mv$from_key) |> slice(1)
  to_pt <- st_sfc(st_point(c(mv$to_lon, mv$to_lat)), crs = 4326) |> st_transform(CRS)
  d0 <- as.numeric(st_distance(bp[inside], from_pt)) / M_PER_MI
  d1 <- as.numeric(st_distance(bp[inside], to_pt)) / M_PER_MI
  wk <- blocks$u18[inside]; ws <- blocks$sp517[inside]
  home[[length(home) + 1]] <- tibble(scenario = mv$scenario, type = "Immersion program moves", language = mv$language,
    band = mv$band, from_school = mv$from_school, to_school = mv$to_school, children = sum(wk),
    before_mi = weighted.mean(d0, wk), after_mi = weighted.mean(d1, wk),
    before_mi_spanish = if (mv$language == "Spanish") weighted.mean(d0, ws) else NA,
    after_mi_spanish = if (mv$language == "Spanish") weighted.mean(d1, ws) else NA)
}
for (i in seq_len(nrow(closures))) {
  c <- closures[i, ]; b <- band_of_school(c$key)
  sq_area <- areas("sq", b) |> filter(key == c$key)
  inside <- lengths(st_intersects(bp, sq_area)) > 0
  if (!any(inside)) next
  from_pt <- pts("sq", b) |> filter(key == c$key) |> slice(1)
  sc_areas <- areas(c$scenario, b); sc_pts <- pts(c$scenario, b)
  j <- st_intersects(bp[inside], sc_areas)
  recv <- sc_areas$key[vapply(j, \(x) if (length(x)) x[1] else NA_integer_, 1L)]
  to_xy <- sc_pts[match(recv, sc_pts$key), ]
  ok <- !is.na(recv) & !st_is_empty(st_geometry(to_xy))
  d0 <- as.numeric(st_distance(bp[inside][ok], from_pt)) / M_PER_MI
  d1 <- as.numeric(st_distance(bp[inside][ok], st_geometry(to_xy)[ok], by_element = TRUE)) / M_PER_MI
  wk <- blocks$u18[inside][ok]; ws <- blocks$sp517[inside][ok]
  home[[length(home) + 1]] <- tibble(scenario = c$scenario, type = "School closures (non-immersion students)", language = NA,
    band = b, from_school = c$school, to_school = paste(unique(recv[ok]), collapse = "; "), children = sum(wk),
    before_mi = weighted.mean(d0, wk), after_mi = weighted.mean(d1, wk),
    before_mi_spanish = weighted.mean(d0, ws), after_mi_spanish = weighted.mean(d1, ws))
}
home <- bind_rows(home) |> mutate(change_mi = after_mi - before_mi)
write_csv(home, here("data", "equity_home_distance.csv"))

# ---- print -------------------------------------------------------------------------------------
fmt <- function(x) sprintf("%.0f%%", 100 * x)
cat("Who is affected (October 2025 enrollment):\n")
print(as.data.frame(groups |> transmute(scenario, type, students, spanish = fmt(pct_spanish_home), non_english = fmt(pct_non_english_home),
                                        school_miles = round(school_miles, 2))), row.names = FALSE)
cat("\nHome-to-school distance (children under 18 in the catchment / attendance area):\n")
# students-weighted summary: weight each change's mean change by its enrolled students
hs <- home |> left_join(select(changes, scenario, from_school, to_school_c = to_school, students, language) |>
                          distinct(scenario, from_school, language, .keep_all = TRUE),
                        by = c("scenario", "from_school", "language")) |>
  group_by(scenario, type) |>
  summarise(before = weighted.mean(before_mi, students), after = weighted.mean(after_mi, students), .groups = "drop") |>
  mutate(change = after - before)
print(as.data.frame(hs |> mutate(across(c(before, after, change), \(v) round(v, 2)))), row.names = FALSE)
write_csv(hs, here("data", "equity_home_distance_summary.csv"))

# ---- sensitivity of the home-to-school estimate --------------------------------------------------
# The immersion estimate assumes families live in the area nearest their program's current school.
# Report how the result changes with the programs included and with the weighting.
hx <- home |> left_join(select(changes, scenario, from_school, language, students) |> distinct(scenario, from_school, language, .keep_all = TRUE),
                        by = c("scenario", "from_school", "language"))
sens1 <- function(d, variant, w = "children") {
  d |> group_by(scenario) |>
    summarise(variant = variant,
              before = if (w == "spanish") weighted.mean(before_mi_spanish, students) else weighted.mean(before_mi, students),
              after = if (w == "spanish") weighted.mean(after_mi_spanish, students) else weighted.mean(after_mi, students),
              .groups = "drop") |> mutate(change = after - before)
}
dli_h <- filter(hx, type == "Immersion program moves"); clo_h <- filter(hx, type != "Immersion program moves")
sens <- bind_rows(
  sens1(dli_h, "Immersion moves: all (main estimate)"),
  sens1(filter(dli_h, language != "Vietnamese"), "Immersion moves: excluding Vietnamese (one site, whole-district catchment)"),
  sens1(filter(dli_h, language == "Spanish"), "Immersion moves: Spanish only"),
  sens1(filter(dli_h, language == "Spanish"), "Immersion moves: Spanish only, weighted by Spanish-speaking children", "spanish"),
  sens1(clo_h, "Closures: all (main estimate)"),
  sens1(clo_h, "Closures: weighted by Spanish-speaking children", "spanish"))
write_csv(sens, here("data", "equity_home_sensitivity.csv"))
cat("\nSensitivity of the home-to-school estimate:\n")
print(as.data.frame(sens |> mutate(across(c(before, after, change), \(v) round(v, 2)))), row.names = FALSE)
