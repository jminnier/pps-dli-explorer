# Every school the scenarios change: who moves where, which schools absorb them, how each school's
# race and ethnicity would change, Title I and SUN status, and whether schools become more segregated.
#
# Inputs:
#   data-raw/plan_flows.csv          one row per group of current students that changes buildings, with the
#                                    PPS school-guide sentence it rests on (hand-entered from data/guide_text.csv)
#   data/race_by_program_2025.csv    PPS race and ethnicity by school and program, October 2025
#   data/enrollment_by_program_grade.csv  grade counts, October 2025 (to split K-8 schools into K-5 and 6-8)
#   data/guide_school.csv            PPS per-school guides (Oct 8, 2026): type of change, projected share
#                                    from underserved racial groups and Title I designation, now and under A/B
#   data-raw/title1/title1_schools.csv  PPS Title IA school lists, 2025-26 and 2026-27 (pps.net/Page/1395)
#   data-raw/sun/sun_schools.csv     Multnomah County SUN Community School contact list, August 2026
# Outputs:
#   data/plan_flows_race.csv         each flow with its students by race and ethnicity
#   data/plan_schools.csv            school x scenario: role, students in/out, now vs after by group,
#                                    PPS's projected underserved share, Title I, SUN
#   data/plan_segregation.csv        dissimilarity index now vs A vs B (elementary and middle buildings)
#   data/title1_schools.csv, data/sun_schools.csv  tidy copies with school keys
#
# Assumptions (also in methods.qmd #school-changes):
#   - Snapshot: today's (October 2025) students are moved as the guides describe. PPS's own projections
#     (guide_school.csv) are for later years and include future boundary effects; they are the check.
#   - Within a school or program, race is assumed the same in every grade (the report has no grades).
#   - Splits PPS gives as boundary shares (Buckman 50/50, Maplewood 70/30, Stephenson 70/30) are applied
#     to enrolled students. Sellwood is split by feeder-school enrollment. Marysville goes to Arleta
#     (PPS projects Arleta +333 and Kelly +10 by 2031-32).
#   - Future-cohort feeder changes (for example Kelly-area middle schoolers to Harrison Park) move no
#     current students, so they are not flows; those schools count as "boundary change only".
#
# Usage: Rscript data-raw/school_changes.R

suppressPackageStartupMessages({ library(dplyr); library(tidyr); library(readr); library(purrr) })
here <- function(...) file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)))), "..", ...)
old_wd <- setwd(here()); source("R/site_data.R"); setwd(old_wd)

RACE <- c("latino", "black", "asian", "native_american", "pacific_islander", "white", "asian_white", "other_multi")
HU <- c("latino", "black", "native_american", "pacific_islander", "other_multi")
NC <- paste0(RACE, "_n")
key2 <- function(x) {
  k <- school_key(sub("\\s+(P?K-\\d+|MS|HS|\\(K-8\\))\\s*\\*?$", "", trimws(x)))
  recode(k, idabwellsbarnett = "idabwells", boiseeliot = "boiseeliothumboldt", drmartinlutherkingjr = "mlkjr", lee = "sunrise")
}

race <- read_csv(here("data", "race_by_program_2025.csv"), show_col_types = FALSE) |>
  filter(row_type %in% c("school", "program", "school_total"), level %in% c("Elementary", "Middle", "High", "Alternative programs")) |>
  mutate(key = recode(school_key(school), lee = "sunrise"),   # Lee Elementary (2222 NE 92nd Ave) is now Sunrise
         across(all_of(NC), \(x) coalesce(x, 0)))
grade <- by_grade |> filter(year == "2025-26")

whole_row <- function(k) {
  d <- filter(race, key == k)
  if (any(d$row_type == "school_total")) d <- filter(d, row_type == "school_total")
  else if (any(d$row_type == "school")) d <- filter(d, row_type == "school")
  if (nrow(d) != 1) stop("no single whole-school race row for ", k)
  d
}
grade_share <- function(k, grades, prog = NULL) {
  g <- filter(grade, key == k)
  if (!is.null(prog)) g <- if (prog == "Neighborhood Program") filter(g, program == "Neighborhood Program") else filter(g, language %in% prog)
  if (!nrow(g)) stop("no grade counts for ", k, " / ", prog)
  sum(g$enrollment[g$grade %in% grades]) / sum(g$enrollment)
}
# Race counts for one part of a school, as a named vector.
part_counts <- function(k, part) {
  m <- regmatches(part, regexec("^(whole|neighborhood|Spanish|Mandarin|Vietnamese)?\\s*(K-5|6-8|9-12)?$", part))[[1]]
  what <- if (m[2] == "") "whole" else m[2]; band <- m[3]
  row <- if (what == "whole") whole_row(k) else {
    lab <- if (what == "neighborhood") "Neighborhood Program" else paste(what, "Immersion")
    d <- filter(race, key == k, program == lab)
    if (nrow(d) != 1) stop("no race row for ", k, " / ", lab)
    d
  }
  s <- if (band == "") 1 else grade_share(k, band_grades[[band]],
                                           if (what == "whole") NULL else if (what == "neighborhood") "Neighborhood Program" else what)
  setNames(unlist(row[NC]) * s, NC)
}

flows0 <- read_csv(here("data-raw", "plan_flows.csv"), show_col_types = FALSE)
flows <- bind_rows(lapply(c("a", "b"), \(s) filter(flows0, scenario %in% c(s, "ab")) |> mutate(scenario = s))) |>
  mutate(from_key = school_key(from_school), to_key = if_else(grepl("^\\(", to_school), "other", school_key(to_school)))
fr <- bind_cols(flows, bind_rows(map2(flows$from_key, flows$part, \(k, p) as.list(part_counts(k, p))))) |>
  mutate(across(all_of(NC), \(x) x * share), students = rowSums(across(all_of(NC))))

# ---- schools: now and after --------------------------------------------------------------------
guide <- read_csv(here("data", "guide_school.csv"), show_col_types = FALSE) |> mutate(key = key2(school))
gsq <- guide |> filter(scenario == "sq") |> select(key, guide_name = school, hu_now_pps = pct_underserved_race, title1_guide_now = title1, pov_now_pps = pct_poverty)
gsc <- bind_rows(lapply(c("a", "b"), \(s) guide |> filter(scenario %in% c(s, "a/b")) |> mutate(scenario = s))) |>
  select(key, scenario, type_of_change, hu_after_pps = pct_underserved_race, title1_guide_after = title1, pov_after_pps = pct_poverty)

t1 <- read_csv(here("data-raw", "title1", "title1_schools.csv"), show_col_types = FALSE) |>
  transmute(school, school_year, key = key2(school), bridge = grepl("bridge", type))
sun <- read_csv(here("data-raw", "sun", "sun_schools.csv"), show_col_types = FALSE) |>
  filter(district == "Portland Public Schools") |>
  transmute(school, key = key2(sub(" (Elementary|Middle School|Middle|High School|K-8|PK-8)$", "", school)),
            proposed_cut_fy27, status_2026_27)
unmatched <- function(k, what) { bad <- setdiff(k, c(guide$key, race$key)); if (length(bad)) message(what, " keys not matched: ", paste(bad, collapse = ", ")) }
t1 <- filter(t1, !key %in% c("arthuracademy", "kairos")); sun <- filter(sun, key != "kairospdx")   # charter schools
unmatched(t1$key, "Title I"); unmatched(sun$key, "SUN")

level_of <- race |> filter(row_type %in% c("school", "school_total")) |> distinct(key, level)
# whole-school immersion schools (Lent, Rigler, Richmond) print only their immersion row
schools <- race |> filter(level != "Alternative programs" | key == "metropolitanlearningcenter") |>
  group_by(key) |> filter(n() == 1 | row_type %in% c("school", "school_total")) |> ungroup() |>
  distinct(key, school, level)
stopifnot(!anyDuplicated(schools$key))
now <- bind_rows(lapply(schools$key, \(k) as.list(part_counts(k, "whole")))) |> mutate(key = schools$key)

out <- fr |> group_by(scenario, key = from_key) |> summarise(across(all_of(NC), sum), students = sum(students), .groups = "drop")
inn <- fr |> filter(to_key != "other") |> group_by(scenario, key = to_key) |> summarise(across(all_of(NC), sum), students = sum(students), .groups = "drop")
stopifnot(all(inn$key %in% schools$key), all(out$key %in% schools$key))

long <- function(d, what) d |> select(any_of(c("scenario", "key")), all_of(NC)) |> pivot_longer(all_of(NC), names_to = "group", values_to = what)
grid <- expand_grid(scenario = c("a", "b"), key = schools$key, group = NC)
comp <- grid |>
  left_join(long(now, "now"), by = c("key", "group")) |>
  left_join(long(out, "out"), by = c("scenario", "key", "group")) |>
  left_join(long(inn, "in"), by = c("scenario", "key", "group")) |>
  mutate(across(c(out, `in`), \(x) coalesce(x, 0)), after = now - out + `in`, group = sub("_n$", "", group))
if (any(comp$after < -0.5)) stop("negative counts after moves: ", paste(unique(comp$key[comp$after < -0.5]), collapse = ", "))

closing <- guide |> filter(grepl("would close", type_of_change)) |> distinct(scenario, key)
closing <- bind_rows(lapply(c("a", "b"), \(s) closing |> filter(scenario %in% c(s, "a/b")) |> mutate(scenario = s)))
# Sellwood (middle school) closes in 2028; Odyssey's East Sylvan building closes and the program moves into MLC
closing <- bind_rows(closing, tibble(scenario = rep(c("a", "b"), 2), key = rep(c("sellwood", "odyssey"), each = 2))) |> distinct()

tot <- comp |> group_by(scenario, key) |>
  summarise(students_now = sum(now), students_out = sum(out), students_in = sum(`in`), students_after = sum(after),
            hu_now = sum(now[group %in% HU]) / sum(now), hu_after = sum(after[group %in% HU]) / sum(after), .groups = "drop")
wide <- comp |> select(scenario, key, group, now, after) |>
  pivot_wider(names_from = group, values_from = c(now, after), names_glue = "{group}_{.value}")

plan <- tot |> left_join(wide, by = c("scenario", "key")) |>
  left_join(schools, by = "key") |> left_join(gsq, by = "key") |> left_join(gsc, by = c("key", "scenario")) |>
  left_join(closing |> mutate(closes = TRUE), by = c("scenario", "key")) |>
  mutate(closes = coalesce(closes, FALSE),
         # whole-school closures send every student; César Chávez etc. keep the parts that stay
         check_closed = !closes | abs(students_after) < 1,
         school = coalesce(guide_name, school),
         role = case_when(key == "odyssey" ~ "Program moves to another building",
                          closes ~ "Closes",
                          students_in > 0 & students_out > 0 ~ "Takes in students and sends some away",
                          students_in > 0 ~ "Takes in students",
                          students_out > 0 ~ "Sends students away",
                          !is.na(type_of_change) & !grepl("^No changes", type_of_change) ~ "Boundary or feeder change only",
                          TRUE ~ "No change"),
         title1_2026_27 = key %in% t1$key[t1$school_year == "2026-27"],
         title1_bridge = key %in% t1$key[t1$school_year == "2026-27" & t1$bridge],
         sun_2026_27 = key %in% sun$key,
         sun_proposed_cut = key %in% sun$key[sun$proposed_cut_fy27 == "yes"],
         hu_after = if_else(closes, NA_real_, hu_after))
if (!all(plan$check_closed)) stop("closing school not fully allocated: ", paste(plan$key[!plan$check_closed], collapse = ", "))
# every school in the guides with a change must be in the table (high schools come from the race report too)
miss <- setdiff(guide$key[guide$scenario != "sq" & !grepl("^No changes", guide$type_of_change)], plan$key)
if (length(miss)) message("guide schools with changes but no race row: ", paste(miss, collapse = ", "))

# ---- checks against PPS's own projections -----------------------------------------------------
chk <- plan |> filter(!closes, students_after > 0, students_in + students_out > 0, !is.na(hu_after_pps)) |>
  transmute(scenario, school, ours = hu_after - hu_now, pps = hu_after_pps - hu_now_pps)
cat(sprintf("Change in underserved share, our snapshot vs PPS projection (%d schools): correlation %.2f, same direction %d of %d, median abs diff %.1f pts\n",
            nrow(chk), cor(chk$ours, chk$pps), sum(sign(round(chk$ours, 2)) == sign(round(chk$pps, 2))), nrow(chk), 100 * median(abs(chk$ours - chk$pps))))
print(as.data.frame(chk |> mutate(across(c(ours, pps), \(x) round(100 * x)))), row.names = FALSE)
stopifnot(cor(chk$ours, chk$pps) > 0.8)

# ---- segregation: building level and program level --------------------------------------------
# Two units of analysis, because some schools already hold two very different programs:
#   building: each open school building (what the rest of this page uses)
#   program:  each immersion program and each neighborhood program as its own unit, so children in
#             different programs under one roof count as separated. Moving a program between buildings
#             changes the building measure but barely the program measure; the difference is whether
#             children share a building, its playground and its services (SUN, Title I).
# Measures, for group a vs group b (Latino vs white, Black vs white, underserved vs not):
#   dissimilarity D = 1/2 sum_i |a_i/A - b_i/B|: share of one group that would have to change units for
#     every unit to match the area's mix (0 = even, 1 = complete separation)
#   exposure E = sum_i (a_i/A)(w_i/t_i): the white share of the typical Latino (or Black) student's unit
# Areas: all elementary (K-5, K-8) units, all middle units, and three local clusters.
dissim <- function(a, b) 0.5 * sum(abs(a / sum(a) - b / sum(b)))
expo <- function(a, w, t) sum(a / sum(a) * w / t)
seg_stats <- function(d) {
  hu <- rowSums(d[paste0(HU, "_n")]); oth <- d$white_n + d$asian_n + d$asian_white_n; t <- rowSums(d[NC])
  tibble(units = nrow(d),
         latino_white_D = dissim(d$latino_n, d$white_n), black_white_D = dissim(d$black_n, d$white_n),
         hu_other_D = dissim(hu, oth),
         latino_exposure_white = expo(d$latino_n, d$white_n, t), black_exposure_white = expo(d$black_n, d$white_n, t))
}

# program units now: each program row; a school without program rows is one unit
unit_name <- function(prog) case_when(prog == "Neighborhood Program" ~ "neighborhood",
                                      grepl("Immersion$", prog) ~ sub(" Immersion$", "", prog),
                                      TRUE ~ "neighborhood")
units_now <- race |> filter(key %in% schools$key[schools$level != "High"]) |> group_by(key) |>
  filter(if (any(row_type == "program")) row_type == "program" else TRUE) |> ungroup() |>
  mutate(unit = if_else(key == "odyssey", "Odyssey", unit_name(program))) |>
  select(key, unit, all_of(NC))
stopifnot(!anyDuplicated(units_now[c("key", "unit")]))
part_unit <- function(k, part) {
  lang <- regmatches(part, regexpr("^(Spanish|Mandarin|Vietnamese)", part))
  if (length(lang)) return(lang)
  if (grepl("^neighborhood", part)) return("neighborhood")
  u <- units_now$unit[units_now$key == k]
  if (length(u) != 1) stop("whole-school flow from a school with several programs: ", k)
  u
}
units_after <- function(s) {
  f <- fr |> filter(scenario == s) |> rowwise() |>
    mutate(from_unit = part_unit(from_key, part),
           to_unit = if (from_key == "odyssey") "Odyssey" else if (from_unit %in% LANGUAGES) from_unit else "neighborhood") |> ungroup()
  sub <- f |> group_by(key = from_key, unit = from_unit) |> summarise(across(all_of(NC), sum), .groups = "drop")
  add <- f |> filter(to_key != "other") |> group_by(key = to_key, unit = to_unit) |> summarise(across(all_of(NC), sum), .groups = "drop")
  u <- bind_rows(units_now, mutate(sub, across(all_of(NC), \(x) -x)), add) |>
    group_by(key, unit) |> summarise(across(all_of(NC), sum), .groups = "drop") |>
    filter(rowSums(across(all_of(NC))) > 1)
  if (any(as.matrix(u[NC]) < -0.5)) stop("negative program counts after moves (", s, ")")
  u |> mutate(across(all_of(NC), \(x) pmax(x, 0)))
}
U <- list(now = units_now, a = units_after("a"), b = units_after("b"))
# the building totals from the program units must match the building table
for (s in c("a", "b")) {
  bt <- U[[s]] |> group_by(key) |> summarise(n = sum(across(all_of(NC))))
  ct <- comp |> filter(scenario == s, key %in% schools$key[schools$level != "High"]) |> group_by(key) |> summarise(m = sum(after)) |> filter(m > 1)
  j <- full_join(bt, ct, by = "key")
  if (any(abs(coalesce(j$n, 0) - coalesce(j$m, 0)) > 1)) stop("program and building totals disagree (", s, ")")
}
CLUSTERS <- list(
  "Northeast: Scott, Rigler, Rose City Park, Vestal" = c("scott", "rigler", "rosecitypark", "vestal"),
  "North: MLK Jr., Sabin, Boise-Eliot/Humboldt" = c("mlkjr", "sabin", "boiseeliothumboldt"),
  "Southeast: Atkinson, Lent, Creston" = c("atkinson", "lent", "creston"))
AREAS <- c(list(`All elementary (K-5 and K-8) schools` = schools$key[schools$level == "Elementary"],
                `All middle schools` = schools$key[schools$level == "Middle"]), CLUSTERS)
seg <- bind_rows(lapply(names(AREAS), function(A) bind_rows(lapply(names(U), function(st) {
  pu <- U[[st]] |> filter(key %in% AREAS[[A]])
  bu <- pu |> group_by(key) |> summarise(across(all_of(NC), sum))
  bind_rows(seg_stats(bu) |> mutate(unit = "building"), seg_stats(pu) |> mutate(unit = "program")) |>
    mutate(area = A, state = st)
})))) |> relocate(area, state, unit)
cat("\nSegregation measures (D: 0 = even, 1 = complete separation; exposure: white share of the typical student's unit)\n")
print(as.data.frame(seg |> mutate(across(where(is.double), \(x) round(x, 3)))), row.names = FALSE)

# ---- write -------------------------------------------------------------------------------------
write_csv(fr |> select(scenario, from_school, part, share, to_school, students, all_of(NC), basis) |>
            mutate(across(c(students, all_of(NC)), \(x) round(x, 1))), here("data", "plan_flows_race.csv"))
write_csv(plan |> select(-check_closed) |> mutate(across(where(is.double), \(x) round(x, 4))) |>
            arrange(scenario, factor(role, c("Closes", "Program moves to another building", "Takes in students", "Takes in students and sends some away", "Sends students away", "Boundary or feeder change only", "No change")), school),
          here("data", "plan_schools.csv"))
write_csv(seg, here("data", "plan_segregation.csv"))
write_csv(t1, here("data", "title1_schools.csv")); write_csv(sun, here("data", "sun_schools.csv"))

# ---- summary printed for the page text --------------------------------------------------------
for (s in c("a", "b")) {
  p <- filter(plan, scenario == s, level != "High" | students_in + students_out > 0)
  cat(sprintf("\nScenario %s:\n", toupper(s)))
  print(as.data.frame(p |> count(role, wt = NULL) |> left_join(p |> group_by(role) |> summarise(students_now = sum(students_now), title1 = sum(title1_2026_27), sun = sum(sun_2026_27)), by = "role")), row.names = FALSE)
  cat(sprintf("  students who change buildings: %.0f\n", sum(fr$students[fr$scenario == s])))
}
