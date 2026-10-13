# Freeway air and the rightsizing plan (Equity page, #sec-freeway).
#
# Inputs: data/freeway_distance.csv (freeway_distance.R) and the exact (unsuppressed) school and flow counts
# from data-raw/school_changes.R, which this script runs first (it rewrites the same plan_* files).
# Distance bands follow EPA (2015): within 150 m (500 ft) of a freeway, where near-road pollution is highest;
# 150-600 m; beyond 600 m (2,000 ft), about background.
#
# Outputs
#   data/freeway_schools.csv  one row per school: distance, band, role and students today / after A / after B,
#                             share from underserved racial groups (ours and PPS's guide).
#   data/freeway_summary.csv  students in each band today and after each scenario.
#   data/freeway_flows.csv    each group of students the plan moves: from/to distance, band, students.
#   data/freeway_test.csv     the equity test: race/ethnicity of students moved INTO schools within 150 m (from
#                             farther away) vs all students the plan moves vs all students today. Counts under 5
#                             are hidden (methods #small-numbers).

suppressPackageStartupMessages({ library(dplyr); library(tidyr); library(readr); library(purrr) })
here <- function(...) file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)))), "..", ...)
sc <- new.env()
invisible(capture.output(sys.source(here("data-raw", "school_changes.R"), envir = sc, chdir = FALSE)))
plan <- sc$plan; fr <- sc$fr; NC <- sc$NC; HU <- sc$HU
G <- sub("_n$", "", NC)
HU_G <- intersect(G, sub("_n$", "", HU))
if (!length(HU_G)) HU_G <- c("latino", "black", "native_american", "pacific_islander", "other_multi")
stopifnot(setequal(HU_G, c("latino", "black", "native_american", "pacific_islander", "other_multi")))

fd <- read_csv(here("data", "freeway_distance.csv"), show_col_types = FALSE)
band <- function(m) cut(m, c(-Inf, 150, 600, Inf), labels = c("within 150 m", "150-600 m", "over 600 m"))
miss <- setdiff(unique(plan$key), fd$key)
if (length(miss)) stop("schools with no freeway distance: ", paste(miss, collapse = ", "))

# ---- schools ------------------------------------------------------------------------------------
sch <- plan |> select(scenario, key, school, level, role, students_now, students_after, hu_now, hu_after, hu_now_pps, hu_after_pps) |>
  left_join(fd |> select(key, dist_m = grounds_to_freeway_m, ramp_m = grounds_to_any_ramp_or_freeway_m, point_m = point_to_freeway_m, freeway), by = "key") |>
  mutate(band = band(dist_m))
schools_out <- sch |> filter(scenario == "a") |>
  select(key, school, level, dist_m, ramp_m, point_m, freeway, band, students_now, hu_now, hu_now_pps, role_a = role, after_a = students_after, hu_after_a = hu_after) |>
  left_join(sch |> filter(scenario == "b") |> select(key, role_b = role, after_b = students_after, hu_after_b = hu_after), by = "key") |>
  mutate(across(c(students_now, after_a, after_b), round), across(starts_with("hu_"), \(x) round(x, 3))) |>
  arrange(dist_m)

# High schools (and MLC's grades 9-12) are outside the K-8 counts. They are kept here only for the
# "with high schools" side notes: no high school student moves to or from a freeway school in the plan.
hs <- sc$hs |> filter(scenario == "a") |> left_join(fd |> select(key, dist_m = grounds_to_freeway_m), by = "key") |> mutate(band = band(dist_m))
stopifnot(!anyNA(hs$dist_m))
hs_n <- bind_rows(lapply(seq_len(nrow(hs)), \(i) as.list(sc$part_counts(hs$key[i], if (hs$change[i] == "Grades 9-12 end") "9-12" else "whole"))))
hs <- bind_cols(hs, hs_n) |> mutate(students = rowSums(across(all_of(NC))))
stopifnot(all(abs(hs$students - hs$students_now) < 1))

k8 <- bind_rows(
  sch |> filter(scenario == "a") |> group_by(band) |> summarise(students = sum(students_now), schools = sum(students_now > 0)) |> mutate(state = "now"),
  sch |> group_by(state = scenario, band) |> summarise(students = sum(students_after), schools = sum(students_after > 0), .groups = "drop"))
with_hs <- bind_rows(lapply(c("now", "a", "b"), \(st) {   # "_hs": the same with high school students added
  h <- if (st == "now") hs else filter(hs, change != "Grades 9-12 end")   # MLC's grades 9-12 leave in A and B
  filter(k8, state == st) |>
    full_join(h |> group_by(band) |> summarise(hs = sum(students), hs_schools = sum(change != "Grades 9-12 end")), by = "band") |>
    transmute(state = paste0(st, "_hs"), band, students = coalesce(students, 0) + coalesce(hs, 0), schools = coalesce(schools, 0L) + coalesce(hs_schools, 0L))
}))
summ <- bind_rows(k8, with_hs) |>
  group_by(state) |> mutate(share = students / sum(students)) |> ungroup() |>
  mutate(students = round(students), share = round(share, 4)) |> relocate(state)

# ---- flows --------------------------------------------------------------------------------------
fl <- fr |> left_join(fd |> select(from_key = key, from_m = grounds_to_freeway_m), by = "from_key") |>
  left_join(fd |> select(to_key = key, to_m = grounds_to_freeway_m), by = "to_key") |>
  mutate(from_band = band(from_m), to_band = band(to_m),
         into_near = !is.na(to_m) & to_m <= 150 & (is.na(from_m) | from_m > 150),
         out_of_near = !is.na(from_m) & from_m <= 150 & (is.na(to_m) | to_m > 150))
flows_out <- fl |> mutate(hu_n = rowSums(across(all_of(paste0(HU_G, "_n"))))) |>
  transmute(scenario, from_school, part, to_school, students = round(students), from_m, to_m, from_band, to_band, into_near, out_of_near,
            hu_pct = ifelse(hu_n < SMALL_N | students - hu_n < SMALL_N, NA, round(hu_n / students, 3))) |>   # hidden if it implies a count under 5
  arrange(scenario, to_m)

# ---- equity test --------------------------------------------------------------------------------
grp <- function(d, label) d |> summarise(across(all_of(NC), sum), students = sum(students)) |> mutate(group = label)
now_all <- plan |> filter(scenario == "a") |> transmute(across(all_of(paste0(G, "_now")), identity), students = students_now)
names(now_all) <- c(NC, "students")
near_now <- plan |> filter(scenario == "a", key %in% fd$key[fd$grounds_to_freeway_m <= 150]) |> transmute(across(all_of(paste0(G, "_now")), identity), students = students_now)
names(near_now) <- c(NC, "students")
test <- bind_rows(
  grp(now_all, "All students today") |> mutate(scenario = "now"),
  grp(near_now, "Students at schools within 150 m today") |> mutate(scenario = "now"),
  grp(bind_rows(now_all, select(hs, all_of(NC), students)), "All students today, with high schools") |> mutate(scenario = "now"),
  grp(bind_rows(near_now, select(filter(hs, dist_m <= 150), all_of(NC), students)), "Students at schools within 150 m today, with high schools") |> mutate(scenario = "now"),
  bind_rows(lapply(c("a", "b"), \(s) bind_rows(
    grp(filter(fl, scenario == s), "All students the plan moves"),
    grp(filter(fl, scenario == s, into_near), "Moved into schools within 150 m"),
    grp(filter(fl, scenario == s, out_of_near), "Moved out of schools within 150 m")) |> mutate(scenario = s)))) |>
  mutate(hu_n = rowSums(across(all_of(paste0(HU_G, "_n")))), hu_pct = hu_n / students,
         across(all_of(NC), \(x) x / students, .names = "{sub('_n$', '_pct', .col)}")) |>
  relocate(scenario, group, students)
cat("\nEquity test (exact, before hiding small counts):\n")
print(as.data.frame(test |> transmute(scenario, group, students = round(students), hu = round(hu_pct, 3),
                                      latino = round(latino_pct, 3), black = round(black_pct, 3), white = round(white_pct, 3), asian = round(asian_pct, 3))), row.names = FALSE)
test_out <- suppress_counts(test |> mutate(students = round(students, 1)), G) |>
  mutate(students = round(students), hu_n = ifelse(hu_n < SMALL_N, NA, round(hu_n)), hu_pct = ifelse(is.na(hu_n), NA, round(hu_pct, 3)))
assert_no_small(test_out, c(NC, "hu_n"), "freeway_test")

write_csv(schools_out, here("data", "freeway_schools.csv"), na = "")
write_csv(summ, here("data", "freeway_summary.csv"), na = "")
write_csv(flows_out, here("data", "freeway_flows.csv"), na = "")
write_csv(test_out, here("data", "freeway_test.csv"), na = "")
cat("\nStudents by band:\n"); print(as.data.frame(summ), row.names = FALSE)
cat("\nFlows into schools within 150 m:\n"); print(as.data.frame(flows_out |> filter(into_near)), row.names = FALSE)
