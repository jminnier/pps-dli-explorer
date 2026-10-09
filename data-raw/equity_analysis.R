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
#   data/equity_pps_follow.csv share of a moved program PPS's school guides project to arrive / stay (guide_enrollment.csv + psu_forecast.csv)
#   data/equity_capture.csv    neighborhood capture rates: Lent, Southeast elementary areas, rest of PPS (capture_rate.csv)
#   data/equity_se_seats.csv   Southeast Spanish vs Richmond / Le Monde kindergarten seats and lottery demand
#   data/equity_site_context.csv  Lent, Rigler, Atkinson, Creston: distance to district edge, own-area share, nearby Spanish speakers, capacity (school_profiles_2025.csv; 2021 facility plan for comparison)
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

# ---- demand at each moving K-5 program (kindergarten lottery, 5-year average) -------------------
demand_moves <- moves |> filter(band == "K-5", kind == "program") |>
  distinct(scenario, language, from_school, from_key, to_school, to_key) |>
  left_join(select(lottery_avg, key, years, applications, offered, waitlisted), by = c(from_key = "key")) |>
  mutate(apps_per_offer = applications / offered)
write_csv(demand_moves, here("data", "equity_demand_moves.csv"))

# ---- multilingual learners inside moving programs vs closing schools ----------------------------
P <- profiles |> filter(year == YEAR)
ml_moving <- moves |> distinct(scenario, from_key, language, band) |>
  left_join(select(P, key, immersion_total, ml_and_immersion), by = c(from_key = "key")) |>
  group_by(scenario) |>
  summarise(group = "Immersion programs that move (whole program, all grades)",
            students = sum(immersion_total[!duplicated(from_key)], na.rm = TRUE),
            ml = sum(ml_and_immersion[!duplicated(from_key)], na.rm = TRUE), .groups = "drop")
# closing schools: ML share of the whole school from the immersion profiles where present; otherwise not available
write_csv(ml_moving |> mutate(pct_ml = ml / students), here("data", "equity_ml_moving.csv"))

# ---- opt-out: families who may stay in neighborhood schools rather than follow a moved program --
# Excess loss implied by the 2023-24 Bridger -> Lent consolidation (same method as scorecard.qmd):
# Lent kindergarten immersion (2024-25, 2025-26 average) vs Bridger + Lent immersion per grade
# (2021-22, 2022-23 average), relative to the district change on the same baseline.
bl <- profiles |> filter(key %in% c("bridgercreativescience", "lent"), year %in% c("2021-22", "2022-23")) |>
  group_by(year) |> summarise(per_grade = sum(imm_spanish) / 6)
lent_k <- by_grade |> filter(key == "lent", grade == "K", language == "Spanish", year %in% c("2024-25", "2025-26")) |>
  group_by(year) |> summarise(k = sum(enrollment))
district_k5_2022 <- c(3152, 3376, 3319, 3502, 3485, 3358)   # PPS Enrollment - Summary Comparison, Oct 3 2022
district_k_after <- by_grade |> filter(grade == "K", year %in% c("2024-25", "2025-26")) |> group_by(year) |> summarise(n = sum(enrollment))
lent_ratio <- mean(lent_k$k) / mean(bl$per_grade)
district_ratio <- mean(district_k_after$n) / mean(district_k5_2022)
precedent_excess <- 1 - lent_ratio / district_ratio
cat(sprintf("\nBridger->Lent precedent: Lent K / prior per-grade = %.2f; district = %.2f; excess loss = %.0f%%\n",
            lent_ratio, district_ratio, 100 * precedent_excess))

rates <- c(`Everyone follows` = 0, `7% (figure cited in public comment)` = 0.07, `Bridger to Lent precedent` = precedent_excess)
k_now <- by_grade |> filter(year == YEAR, grade == "K") |> group_by(key, language) |> summarise(k = sum(enrollment), .groups = "drop")
optout <- moves |> filter(kind == "program") |> rowwise() |>
  mutate(students = strand_students(from_key, language, band)) |> ungroup() |>
  left_join(rename(k_now, k_entry = k), by = c(from_key = "key", "language")) |>
  mutate(k_entry = if_else(band == "K-5", k_entry, NA_real_)) |>
  tidyr::crossing(tibble(assumption = names(rates), rate = unname(rates))) |>
  mutate(students_lost = students * rate, k_lost_per_year = k_entry * rate) |>
  select(scenario, language, band, from_school, to_school, students, k_entry, assumption, rate, students_lost, k_lost_per_year)
write_csv(optout, here("data", "equity_optout.csv"))
cat("Opt-out totals (students now in moving programs who might stay in neighborhood schools):\n")
print(as.data.frame(optout |> group_by(scenario, assumption) |>
  summarise(rate = first(rate), students = sum(students), students_lost = round(sum(students_lost)),
            k_lost_per_year = round(sum(k_lost_per_year, na.rm = TRUE)), .groups = "drop")), row.names = FALSE)

# ---- whole-school composition: schools losing an immersion program vs closing schools ----------
# PPS School/Neighborhood Enrollment by Ethnicity & Program (October 2025, School rows). This is the
# composition of the whole school, not of its immersion program (PPS doesn't publish race by
# program). Each school is counted once: schools that both close and lose an immersion program
# (Beach, James John, Rose City Park in A) are in "lose an immersion program". Clark is not printed
# in the report and is left out.
demo <- read_csv(here("data", "school_demographics.csv"), show_col_types = FALSE) |>
  filter(year == YEAR, row_type == "School") |> mutate(key = school_key(name))
pct_cols <- c("pct_latino", "pct_white", "pct_african_american", "pct_direct_cert", "pct_ell", "pct_hist_underserved", "pct_immersion")
comp <- bind_rows(lapply(c("a", "b"), function(sc) {
  send <- unique(moves$from_key[moves$scenario == sc])
  recv <- setdiff(unique(moves$to_key[moves$scenario == sc]), send)
  clo <- setdiff(closures$key[closures$scenario == sc], send)
  groups <- list(`Schools losing an immersion program` = send, `Schools receiving an immersion program` = recv,
                 `Schools closing (no immersion program)` = clo, `All PPS schools` = NULL)
  bind_rows(lapply(names(groups), function(g) {
    d <- if (is.null(groups[[g]])) read_csv(here("data", "school_demographics.csv"), show_col_types = FALSE) |>
      filter(year == YEAR, row_type == "Grand Total") else filter(demo, key %in% groups[[g]])
    missing <- setdiff(groups[[g]], demo$key)
    tibble(scenario = sc, group = g, schools = nrow(d), enrollment = sum(d$enrollment),
           missing = paste(missing, collapse = "; "),
           !!!setNames(lapply(pct_cols, \(col) weighted.mean(d[[col]], d$enrollment)), pct_cols))
  }))
}))
write_csv(comp, here("data", "equity_school_composition.csv"))
cat("\nWhole-school composition (October 2025, enrollment-weighted):\n")
print(as.data.frame(comp |> mutate(across(all_of(pct_cols), \(v) round(100 * v))) |> select(-missing)), row.names = FALSE)

# ---- did PPS's enrollment forecasts anticipate families not following the Bridger -> Lent move? --
# PSU Population Research Center forecasts (prepared for PPS). The 2023-24 edition (June 2023,
# based on October 2022) built the move in ("Bridger Spanish DLI (grades K-5) moved to Lent ES").
# The 2022-23 edition predates it, so its Bridger + Lent Spanish rows are the like-for-like pre-move
# program. Actuals are PSU's own K-12 October counts from the latest editions (Lent's PPS totals
# also include pre-kindergarten).
pm <- read_csv(here("data", "psu_forecast_premove.csv"), show_col_types = FALSE)
pf <- read_csv(here("data", "psu_forecast.csv"), show_col_types = FALSE)
actual <- bind_rows(
  pf |> filter(table == "school_program", school == "Lent", program == "Total", type == "actual") |> transmute(target = "Lent", year, actual = enrollment),
  pf |> filter(table == "district_by_grade", grade == "Total", scenario == "middle", type == "actual") |> transmute(target = "District", year, actual = enrollment)
) |> distinct(target, year, .keep_all = TRUE)
yrs <- c("2023-24", "2024-25", "2025-26")
fc <- bind_rows(
  pm |> filter(forecast_vintage == "2022-23", school %in% c("Lent", "Bridger"), program == "Spanish", year %in% yrs) |>
    group_by(year) |> summarise(forecast = sum(enrollment)) |> mutate(vintage = "2022-23", target = "Lent", note = "Bridger + Lent Spanish, before the move was planned in"),
  pm |> filter(forecast_vintage == "2023-24", school == "Lent", program == "Total", year %in% yrs) |>
    transmute(year, forecast = enrollment, vintage = "2023-24", target = "Lent", note = "move built in"),
  pm |> filter(school == "District", program == "Total", year %in% yrs, forecast_vintage %in% c("2022-23", "2023-24")) |>
    transmute(year, forecast = enrollment, vintage = forecast_vintage, target = "District", note = "district total")
) |> left_join(actual, by = c("target", "year")) |>
  mutate(error = forecast - actual, pct_error = error / actual) |>
  select(target, vintage, note, year, forecast, actual, error, pct_error)
write_csv(fc, here("data", "equity_forecast_check.csv"))
cat("\nForecast vs actual (PSU):\n"); print(as.data.frame(fc |> mutate(pct_error = sprintf("%+.1f%%", 100 * pct_error)) |> select(-note)), row.names = FALSE)

# ---- how many students does PPS's own scenario projection have following each moved program? ----
# PPS's per-school guides (Oct 2026) print projected enrollment for 2027-28 to 2031-32 under "No changes"
# and under the options. "No changes" equals PSU's 2026-27 forecast for every school checked, so the
# options rows can be read against PSU's program forecasts. Only moves where the receiving school's
# only change is the arriving program (and, where shown, the sending school's only change is losing
# it) are used: Atkinson -> Lent, Scott -> Rigler (Scott in Scenario B), Clark -> Woodstock.
# followed = receiving school (options - no changes) / moving program (PSU forecast);
# stayed    = sending school (options - its other programs, PSU forecast) / moving program.
ge <- read_csv(here("data", "guide_enrollment.csv"), show_col_types = FALSE)
gv <- function(s, sc) ge |> filter(school == s, scenario == sc) |> select(year, enrollment)
pp <- function(s, p) pf |> filter(forecast_vintage == "2026-27", table == "school_program", school == s, program == p, type == "forecast") |> select(year, enrollment)
sq_check <- ge |> filter(scenario == "sq", school %in% c("Lent", "Rigler", "Scott", "Woodstock", "Clark", "Atkinson")) |>
  inner_join(pf |> filter(forecast_vintage == "2026-27", table == "school_program", program == "Total", type == "forecast") |> select(school, year, psu = enrollment), by = c("school", "year"))
if (any(sq_check$enrollment != sq_check$psu)) stop("guide 'No changes' differs from PSU 2026-27 forecast:\n", paste(capture.output(print(filter(sq_check, enrollment != psu))), collapse = "\n"))
follow_one <- function(move, language, from, to, prog, scen, stay_school = NA, other_prog = NA) {
  m <- pp(from, prog) |> rename(program = enrollment) |>
    inner_join(gv(to, scen) |> rename(to_opt = enrollment), by = "year") |>
    inner_join(gv(to, "sq") |> rename(to_sq = enrollment), by = "year") |>
    mutate(move = move, language = language, scenario = scen, joined = to_opt - to_sq, followed = joined / program)
  if (!is.na(stay_school)) m <- m |> inner_join(gv(stay_school, scen) |> rename(from_opt = enrollment), by = "year") |>
    inner_join(pp(from, other_prog) |> rename(from_other = enrollment), by = "year") |>
    mutate(stayed_n = from_opt - from_other, stayed = stayed_n / program)
  m
}
pps_follow <- bind_rows(
  follow_one("Atkinson → Lent", "Spanish", "Atkinson", "Lent", "Spanish", "a"),
  follow_one("Scott → Rigler", "Spanish", "Scott", "Rigler", "Spanish", "b", "Scott", "Neighborhood"),
  follow_one("Clark → Woodstock", "Mandarin", "Clark", "Woodstock", "Mandarin", "a", "Clark", "Neighborhood")
) |> select(move, language, scenario, year, program, to_sq, to_opt, joined, followed, any_of(c("from_opt", "from_other", "stayed_n", "stayed")))
write_csv(pps_follow, here("data", "equity_pps_follow.csv"))
cat("\nPPS scenario projections: share of each moved program arriving at the receiving school:\n")
print(as.data.frame(pps_follow |> mutate(across(c(followed, stayed), \(v) round(100 * v)))), row.names = FALSE)

# ---- neighborhood capture rates: Southeast elementary areas vs the rest of PPS --------------------
# PPS "Neighborhood Capture Rate Metrics" (October counts, K-12 residents of each attendance area).
# Southeast = the elementary areas around the 2023 Southeast Enrollment and Program Balancing changes.
# Lent is shown separately: after 2023 its non-immersion neighborhood children were assigned to
# Marysville, which the report counts as "other neighborhood school", so its drop is partly by design.
cr <- read_csv(here("data", "capture_rate.csv"), show_col_types = FALSE)
SE_AREAS <- c("Abernethy", "Atkinson", "Bridger", "Bridger Creative Science", "Creston", "Duniway", "Grout", "Lewis",
              "Llewellyn", "Sunnyside Environmental", "Woodstock", "Marysville", "Kelly", "Arleta", "Whitman", "Woodmere")
stopifnot(all(SE_AREAS %in% cr$neighborhood))
cap_cols <- c("own_neighborhood_school", "other_neighborhood_school", "pps_alternative", "pps_charter", "total")
cap <- cr |> filter(level == "Elementary", row_type == "school") |>
  mutate(group = case_when(neighborhood == "Lent" ~ "Lent", neighborhood %in% SE_AREAS ~ "Southeast (excluding Lent)", TRUE ~ "Rest of PPS")) |>
  bind_rows(cr |> filter(row_type == "grand_total") |> mutate(group = "All PPS, K-12")) |>
  group_by(year, group) |> summarise(across(all_of(cap_cols), sum), areas = n(), .groups = "drop") |>
  mutate(capture = own_neighborhood_school / total, other_neighborhood = other_neighborhood_school / total, alternative = pps_alternative / total)
write_csv(cap, here("data", "equity_capture.csv"))
cat("\nNeighborhood capture rate, elementary areas:\n")
print(as.data.frame(cap |> select(year, group, capture) |> mutate(capture = round(100 * capture, 1)) |> pivot_wider(names_from = group, values_from = capture)), row.names = FALSE)

# ---- Southeast Spanish immersion: seats vs demand, and Lent vs Rigler as whole-school sites --------
# Kindergarten immersion seats (October 2025 kindergarten enrollment) and five-year lottery averages
# for Southeast Spanish (Atkinson, Lent), Richmond (Japanese) and Le Monde (French charter).
# Site context for whole-school / candidate sites: distance to the district edge, share of students
# living in the school's own area (Enrollment by Neighborhood of Residence), school-age Spanish speakers
# within 1.5 miles. Richmond's point on the pps-explorer map duplicates Atkinson's, so no distance is
# computed for Richmond.
k25 <- by_grade |> filter(year == "2025-26", grade == "K")
kseat <- function(k, lang = NULL) sum(k25$enrollment[k25$key == k & (is.null(lang) | k25$language %in% lang)])
se_seats <- tibble(
  program = c("Richmond (Japanese)", "Le Monde (French, charter)", "Lent (Spanish)", "Atkinson (Spanish)"),
  key = c("richmond", "lemonde", "lent", "atkinson"),
  k_2025 = c(kseat("richmond"), kseat("lemonde"), kseat("lent", "Spanish"), kseat("atkinson", "Spanish")),
  school_total = vapply(c("richmond", "lemonde", "lent", "atkinson"), \(k) sum(by_grade$enrollment[by_grade$key == k & by_grade$year == "2025-26" &
    (k %in% c("richmond", "lemonde", "lent") | by_grade$language %in% "Spanish")]), 0)) |>
  left_join(select(lottery_avg, key, applications, offered, waitlisted, years), by = "key")
stopifnot(all(se_seats$k_2025 > 0))
write_csv(se_seats, here("data", "equity_se_seats.csv"))

ebn25 <- read_csv(here("data", "enroll_by_neighborhood.csv"), show_col_types = FALSE) |> filter(year == "2025-26") |> mutate(key = school_key(school))
site_keys <- c(Lent = "lent", Rigler = "rigler", Atkinson = "atkinson", Creston = "creston")
spts <- st_read(here("public", "data", "sq_k5_schools.geojson"), quiet = TRUE) |> mutate(key = school_key(name)) |>
  filter(key %in% site_keys) |> group_by(key) |> slice(1) |> ungroup() |> st_transform(CRS)
edge <- st_boundary(st_union(st_make_valid(st_transform(st_read(here("public", "data", "sq_912.geojson"), quiet = TRUE), CRS))))
dsp <- st_distance(bp, spts) / M_PER_MI
site_ctx <- tibble(school = names(site_keys), key = site_keys) |>
  left_join(tibble(key = spts$key, edge_mi = as.numeric(st_distance(spts, edge)) / M_PER_MI,
                   spanish_517_within_1_5mi = vapply(seq_len(nrow(spts)), \(i) sum(blocks$sp517[as.numeric(dsp[, i]) <= 1.5]), 0)), by = "key") |>
  left_join(ebn25 |> filter(program %in% c("Spanish Immersion") | (key == "rigler" & is.na(program))) |>
              group_by(key) |> summarise(own_area = sum(students[area_level == "own_neighborhood"]),
                                         out_of_district = sum(students[area_level == "other"]), students = first(row_total)), by = "key")
# building capacity vs October 2025 enrollment and PPS's 2027-28 projection. Current functional capacity and
# utilization are from PPS's School Profiles dashboard (2025-26); the 2021 Long-Range Facility Plan figure is kept
# for comparison.
fcap <- read_csv(here("data", "facility_capacity_2021.csv"), show_col_types = FALSE) |> mutate(key = school_key(site))
prof <- read_csv(here("data", "school_profiles_2025.csv"), show_col_types = FALSE) |> mutate(key = school_key(school)) |>
  select(key, functional_capacity = functional_capacity, profile_enrollment_2025 = enrollment_2025, profile_use_2025 = utilization)
gopt <- read_csv(here("data", "guide_enrollment.csv"), show_col_types = FALSE) |> filter(year == "2027-28", scenario == "a") |>
  mutate(key = school_key(school)) |> select(key, projected_2027_a = enrollment)
site_ctx <- site_ctx |>
  left_join(prof, by = "key") |>
  left_join(select(fcap, key, functional_capacity_2021 = functional_capacity), by = "key") |>
  left_join(by_grade |> filter(year == "2025-26", grade != "PK") |> group_by(key) |> summarise(enrolled_2025 = sum(enrollment)), by = "key") |>
  left_join(gopt, by = "key") |>
  mutate(use_2025 = enrolled_2025 / functional_capacity, use_2027_a = projected_2027_a / functional_capacity,
         mi_from_atkinson = as.numeric(st_distance(spts[match(key, spts$key), ], spts[spts$key == "atkinson", ])) / M_PER_MI)
stopifnot(!anyNA(site_ctx$functional_capacity), !anyNA(site_ctx$functional_capacity_2021))
write_csv(site_ctx, here("data", "equity_site_context.csv"))
cat("\nSoutheast seats vs demand:\n"); print(as.data.frame(se_seats), row.names = FALSE)
cat("\nWhole-school site context:\n"); print(as.data.frame(site_ctx), row.names = FALSE)
