# Race and ethnicity of the students the scenarios would move, by program.
#
# PPS's Enrollment Summary by Race and Ethnicity (October 2025; data/race_by_program_2025.csv, from
# parse_race_by_program.py) splits schools with an immersion program into an immersion row and a
# neighborhood-program row. That lets us describe the students in each moving immersion program,
# not only their whole school.
#
# Inputs: data/race_by_program_2025.csv, data/dli_moves.csv (via R/site_data.R), data/equity_changes.csv
#         (closures, from equity_analysis.R), data/guide_school.csv (PPS per-school scenario guides).
# Outputs:
#   data/equity_race_groups.csv    scenario x group (immersion program moves, closures, PPS K-8): counts and shares
#   data/equity_race_programs.csv  each moving program: the program, its school's neighborhood program, the receiving school
#   data/equity_race_schools.csv   sending and receiving schools: PPS's projected share of students from
#                                  underserved racial groups, now vs the scenario (guide_school.csv)
#
# Definitions:
#   historically underserved (PPS): Latino, Black (African American), Native American, Pacific Islander and
#     multi-racial "other ancestries". Asian and Asian/White students are not in PPS's definition.
#   Movers: the whole immersion program's row, scaled to the grades that move (only César Chávez's 6-8 grade
#     change moves part of a program; its race split is assumed to match the K-8 program's).
#   Closures: students at closing schools outside immersion (the neighborhood-program row where a closing
#     school also has an immersion program, otherwise the school row).
#   Comparison: all PPS elementary and middle schools (the report's two section totals), since every move
#     and closure is K-8.
#
# Usage: Rscript data-raw/equity_race.R

suppressPackageStartupMessages({ library(dplyr); library(tidyr); library(readr) })
here <- function(...) file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)))), "..", ...)
old_wd <- setwd(here()); source("R/site_data.R"); setwd(old_wd)

RACE <- c(latino = "Latino", black = "Black", asian = "Asian", native_american = "Native American",
          pacific_islander = "Pacific Islander", white = "White", asian_white = "Multiracial: Asian and White",
          other_multi = "Multiracial: other")
HU <- c("latino", "black", "native_american", "pacific_islander", "other_multi")
ncols <- paste0(names(RACE), "_n")

race <- read_csv(here("data", "race_by_program_2025.csv"), show_col_types = FALSE) |>
  mutate(key = school_key(school),
         program_language = sub(" Immersion$", "", if_else(grepl("Immersion$", program), program, NA_character_)))

stopifnot(all(rowSums(race[ncols]) == race$total))

row_for <- function(k, prog_language = NA) {
  d <- if (is.na(prog_language)) {
    nb <- filter(race, key == k, program == "Neighborhood Program")
    if (nrow(nb)) nb else filter(race, key == k, program == "School")
  } else filter(race, key == k, program_language == prog_language)
  if (nrow(d) != 1) stop(sprintf("expected one race row for %s / %s, found %d", k, prog_language, nrow(d)))
  d
}
whole_school <- function(k) {
  d <- filter(race, key == k, program %in% c("Total", "School") | (program_language %in% c("Spanish", "Japanese") & !any(race$key == k & race$program == "Total")))
  d <- if (any(d$program == "Total")) filter(d, program == "Total") else d
  if (nrow(d) != 1) stop(sprintf("expected one whole-school row for %s, found %d", k, nrow(d)))
  d
}
shares <- function(d) {
  out <- as.list(colSums(d[ncols]))
  tot <- sum(unlist(out))
  c(list(students = tot), out, setNames(lapply(out, \(x) x / tot), sub("_n$", "_pct", names(out))),
    list(hu_n = sum(unlist(out[paste0(HU, "_n")])), hu_pct = sum(unlist(out[paste0(HU, "_n")])) / tot,
         poc_pct = 1 - out$white_n / tot))
}

# ---- movers: one row per moving program, scaled to the grades that move ----------------------
movers <- moves |> rowwise() |>
  mutate(r = list(row_for(from_key, language)), program_total = r$total,
         moving = strand_students(from_key, language, band), scale = moving / program_total) |>
  ungroup()
cat("Moving programs: race-report total vs October 2025 grade counts for the grades that move\n")
print(as.data.frame(distinct(movers, from_school, language, band, program_total, moving, scale)), row.names = FALSE)
# whole programs must agree with the grade counts (within 2 students, for late changes between reports)
whole <- movers |> filter(!(kind == "grades"))
if (any(abs(whole$moving - whole$program_total) > 2)) stop("a whole-program move doesn't match the race report's program total")

scaled <- function(r, s) { r <- r; r[ncols] <- r[ncols] * s; r }
mover_rows <- bind_rows(lapply(seq_len(nrow(movers)), function(i) {
  m <- movers[i, ]
  scaled(m$r[[1]], if (m$kind == "grades") m$scale else 1) |> mutate(scenario = m$scenario)
}))
clo <- read_csv(here("data", "equity_changes.csv"), show_col_types = FALSE) |>
  filter(type == "School closures (non-immersion students)") |> mutate(key = school_key(from_school))
clo_rows <- bind_rows(lapply(seq_len(nrow(clo)), function(i) row_for(clo$key[i]) |> mutate(scenario = clo$scenario[i])))
chk <- clo_rows$total == clo$students
if (!all(chk)) stop("closure counts differ between the race report and equity_changes.csv: ", paste(clo$from_school[!chk], collapse = ", "))

# Neighborhood students moved out of a school that becomes an immersion hub. In both scenarios César
# Chávez becomes a K-5 Spanish immersion school: "Neighborhood (non-DLI) K-5 students would move to Rosa
# Parks K-5. Middle grade (6th-8th) students would move to George Middle School" (PPS school guide).
HUB_NB <- c("cesarchavez")
hub_rows <- bind_rows(lapply(c("a", "b"), \(sc) bind_rows(lapply(HUB_NB, row_for)) |> mutate(scenario = sc)))

k8 <- race |> filter(row_type == "section_total", level %in% c("Elementary", "Middle"))
# every K-8 immersion program row (strands and whole-school immersion schools), for access by race
k8_imm <- race |> filter(level %in% c("Elementary", "Middle"), !is.na(program_language))
groups <- bind_rows(
  bind_rows(lapply(c("a", "b"), \(sc) as_tibble(shares(filter(hub_rows, scenario == sc))) |>
    mutate(scenario = sc, group = "Neighborhood program moved out of an immersion hub"))),
  as_tibble(shares(k8_imm)) |> mutate(scenario = "all", group = "All PPS K-8 immersion programs"),
  bind_rows(lapply(c("a", "b"), \(sc) as_tibble(shares(filter(mover_rows, scenario == sc))) |>
    mutate(scenario = sc, group = "Immersion program moves"))),
  bind_rows(lapply(c("a", "b"), \(sc) as_tibble(shares(filter(clo_rows, scenario == sc))) |>
    mutate(scenario = sc, group = "School closures (non-immersion students)"))),
  as_tibble(shares(k8)) |> mutate(scenario = "all", group = "All PPS elementary and middle schools")
) |> relocate(scenario, group)
groups_out <- suppress_counts(groups, names(RACE))   # counts under 5 hidden (methods #small-numbers)
assert_no_small(groups_out, ncols, "equity_race_groups")
write_csv(groups_out, here("data", "equity_race_groups.csv"))

# ---- Black students who would have to change schools, by school and cause (for fig-black-displaced) --
by_school <- function(rows, cause, place, language, kind) rows |>
  mutate(cause = cause, school = place, language = language, kind = kind, students = rowSums(across(all_of(ncols)))) |>
  select(scenario, cause, school, language, kind, black_n, students)
black <- bind_rows(
  by_school(mover_rows, "Immersion program moves", movers$from_school, movers$language, if_else(movers$kind == "grades", "grades 6-8", "program")),
  by_school(clo_rows, "School closures (non-immersion students)", clo$from_school, NA_character_, "closes"),
  by_school(hub_rows, "Neighborhood program moved out of an immersion hub", "César Chávez", NA_character_, "neighborhood program")
) |> mutate(black_pct = black_n / students)
chk_b <- black |> group_by(scenario, cause) |> summarise(b = sum(black_n), .groups = "drop") |>
  left_join(groups |> select(scenario, cause = group, g = black_n), by = c("scenario", "cause"))
if (any(abs(chk_b$b - chk_b$g) > 1e-6)) stop("Black counts by school don't add up to the group totals")
# Small numbers: schools/programs with fewer than 5 Black students are pooled into one "other" row per
# scenario and cause. If the pool itself is under 5, the next-smallest school joins it, so no hidden
# count can be found by subtracting from the cause total.
black_out <- black |> group_by(scenario, cause) |> group_modify(function(d, k) {
  d <- arrange(d, black_n); pool <- is_small(d$black_n)
  while (any(pool) && sum(d$black_n[pool]) < SMALL_N && !all(pool)) pool[which(!pool)[1]] <- TRUE
  if (!any(pool)) return(d)
  other <- tibble(school = NA_character_, language = NA_character_, kind = "other", black_n = sum(d$black_n[pool]),
                  students = sum(d$students[pool]), places = paste(sort(d$school[pool]), collapse = "; "))
  bind_rows(d[!pool, ], other)
}) |> ungroup() |> mutate(black_pct = black_n / students, black_n = if_else(is_small(black_n), NA_real_, round(black_n, 1)),
                          black_pct = if_else(is.na(black_n), NA_real_, black_pct))
assert_no_small(black_out, "black_n", "equity_race_black")
write_csv(black_out, here("data", "equity_race_black.csv"))

cat("\nRace and ethnicity of directly displaced students (shares):\n")
print(as.data.frame(groups |> mutate(across(ends_with("_pct"), \(v) round(100 * v, 1)), students = round(students)) |>
  select(scenario, group, students, black_n, latino_pct, black_pct, asian_pct, native_american_pct, pacific_islander_pct, white_pct, hu_pct)), row.names = FALSE)

# ---- each moving program vs the rest of its school and the receiving school -------------------
prog <- movers |> filter(scenario == "a" | !(paste(from_key, language, band) %in% paste(from_key, language, band)[scenario == "a"])) |>
  distinct(from_key, from_school, to_key, to_school, language, band, kind, .keep_all = TRUE) |>
  rowwise() |>
  mutate(scenarios = paste(sort(toupper(unique(movers$scenario[movers$from_key == from_key & movers$language == language & movers$band == band]))), collapse = " and "),
         p = list(shares(r)),
         nb = list(if (any(race$key == from_key & race$program == "Neighborhood Program")) shares(row_for(from_key)) else NULL),
         rc = list(shares(whole_school(to_key)))) |>
  ungroup()
# a group's share, or NA when it has fewer than 5 students (methods #small-numbers)
sp <- function(lst, g) sapply(lst, \(x) if (is.null(x)) NA else if (is_small(x[[paste0(g, "_n")]])) NA else round(x[[paste0(g, "_pct")]], 2))
progs <- prog |> transmute(
  scenarios, from_school, to_school, language, band, kind, program_students = program_total, moving,
  latino_pct = sp(p, "latino"), black_pct = sp(p, "black"), asian_pct = sp(p, "asian"),
  white_pct = sp(p, "white"), hu_pct = sapply(p, `[[`, "hu_pct"),
  nb_students = sapply(nb, \(x) if (is.null(x)) NA else x$students),
  nb_latino_pct = sp(nb, "latino"), nb_black_pct = sp(nb, "black"),
  nb_white_pct = sp(nb, "white"), nb_hu_pct = sapply(nb, \(x) if (is.null(x)) NA else x$hu_pct),
  to_students = sapply(rc, `[[`, "students"), to_latino_pct = sp(rc, "latino"), to_black_pct = sp(rc, "black"),
  to_white_pct = sp(rc, "white"), to_hu_pct = sapply(rc, `[[`, "hu_pct"),
  from_closes)
write_csv(progs, here("data", "equity_race_programs.csv"))
cat("\nEach moving program (shares, %):\n")
print(as.data.frame(progs |> mutate(across(ends_with("_pct"), \(v) round(100 * v))) |>
  select(scenarios, from_school, language, band, moving, latino_pct, black_pct, asian_pct, white_pct, hu_pct, nb_black_pct, nb_hu_pct, to_school, to_hu_pct)), row.names = FALSE)

# ---- PPS's own projections: share of students from underserved racial groups, now vs scenario --
gs <- read_csv(here("data", "guide_school.csv"), show_col_types = FALSE) |> mutate(key = school_key(school))
sch <- bind_rows(lapply(c("a", "b"), function(sc) {
  send <- unique(movers$from_key[movers$scenario == sc]); recv <- unique(movers$to_key[movers$scenario == sc])
  tibble(scenario = sc, key = c(send, setdiff(recv, send)), role = c(rep("Loses an immersion program", length(send)), rep("Receives an immersion program", length(setdiff(recv, send)))))
})) |>
  left_join(gs |> filter(scenario == "sq") |> select(key, school, now = pct_underserved_race), by = "key") |>
  left_join(gs |> filter(scenario != "sq") |> separate_rows(scenario, sep = "/") |> select(scenario, key, after = pct_underserved_race), by = c("scenario", "key")) |>
  mutate(closes = is.na(after), change = after - now)
write_csv(sch, here("data", "equity_race_schools.csv"))
cat("\nPPS guide: share of students from underserved racial groups, now -> scenario:\n")
print(as.data.frame(sch |> mutate(across(c(now, after, change), \(v) round(100 * v)))), row.names = FALSE)
