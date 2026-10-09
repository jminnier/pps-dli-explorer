# Enrollment history for Lent, César Chávez and Bridger (history.qmd).
#
# Enrollment by program comes from the October actuals printed in the PSU Population Research Center
# forecasts for PPS (kindergarten through grade 12; pre-kindergarten excluded), 2022-23 to 2026-27
# editions. For each school, program and year the earliest edition that prints it is used; editions that
# print the same year are compared (Spanish counts must agree; restated totals are noted) and the
# first-reported value is used. Bridger Creative Science (from 2023-24) is Bridger's
# building after its Spanish program moved to Lent.
#
# Outputs:
#   data/history_enrollment.csv  school x program x year, 2019-20 to 2025-26, with grade configuration
#   data/history_projection.csv  PPS school-guide projections for Lent and César Chávez, 2027-28 to 2031-32
#
# Usage: Rscript data-raw/history_tables.R

suppressPackageStartupMessages({ library(dplyr); library(tidyr); library(readr) })
here <- function(...) file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)))), "..", ...)
old_wd <- setwd(here()); source("R/site_data.R"); setwd(old_wd)

YEARS <- c("2019-20", "2020-21", "2021-22", "2022-23", "2023-24", "2024-25", "2025-26")
act <- bind_rows(
  read_csv(here("data", "psu_forecast.csv"), show_col_types = FALSE) |> filter(table == "school_program"),
  read_csv(here("data", "psu_forecast_premove.csv"), show_col_types = FALSE)
) |>
  filter(type == "actual", year %in% YEARS) |>
  filter(school %in% c("Lent", "César Chávez", "Bridger"), program %in% c("Spanish", "Neighborhood", "Total")) |>
  distinct(forecast_vintage, school, program, year, enrollment)

# Later editions sometimes restate a past year under a school's new configuration (e.g. the 2024-25
# edition prints Bridger's 2021-22 and 2022-23 totals with Creative Science included). Use each year
# as first reported: the earliest edition that prints it. Spanish immersion counts must agree across
# editions; other restatements are printed as notes.
disagree <- act |> group_by(school, program, year) |> filter(max(enrollment) - min(enrollment) > 2) |> ungroup()
if (any(disagree$program == "Spanish")) stop("PSU editions disagree on Spanish immersion actuals:\n",
  paste(capture.output(print(as.data.frame(filter(disagree, program == "Spanish")))), collapse = "\n"))
if (nrow(disagree)) { cat("Note: restated in later editions (first-reported value used):\n")
  print(as.data.frame(disagree |> group_by(school, program, year) |> summarise(values = paste(sort(unique(enrollment)), collapse = " / "), .groups = "drop")), row.names = FALSE) }

hist <- act |> group_by(school, program, year) |> slice_min(forecast_vintage, n = 1, with_ties = FALSE) |> ungroup() |>
  select(school, program, year, enrollment, forecast_vintage)

# Bridger's Spanish program left after 2022-23; Lent's neighborhood program left after 2022-23.
hist <- hist |> complete(school, program, year = YEARS) |>
  mutate(enrollment = case_when(!is.na(enrollment) ~ enrollment,
                                school == "Bridger" & program == "Spanish" & year >= "2023-24" ~ 0,
                                school == "Lent" & program == "Neighborhood" & year >= "2023-24" ~ 0,
                                school == "Lent" & program == "Total" & year >= "2023-24" ~ NA_real_,
                                TRUE ~ NA_real_))
# fill totals from programs where a total isn't printed, then check programs sum to totals
hist <- hist |> group_by(school, year) |>
  mutate(prog_sum = sum(enrollment[program != "Total"]),
         enrollment = if_else(program == "Total" & is.na(enrollment), prog_sum, enrollment)) |> ungroup()
bad <- hist |> group_by(school, year) |>
  summarise(total = enrollment[program == "Total"], prog = sum(enrollment[program != "Total"]), .groups = "drop") |>
  filter(!is.na(total), !is.na(prog), abs(total - prog) > 2, !(school == "Bridger" & year >= "2023-24"))
if (nrow(bad)) stop("programs don't sum to totals:\n", paste(capture.output(print(as.data.frame(bad))), collapse = "\n"))

# Bridger is kept only for its Spanish program (its later totals are Bridger Creative Science, K-8)
hist <- hist |> select(-prog_sum) |> filter(!(school == "Bridger" & program != "Spanish")) |>
  mutate(grades = case_when(school == "César Chávez" ~ "K-8",
                            school == "Lent" & year < "2021-22" ~ "K-8",
                            school == "Lent" ~ "K-5",
                            school == "Bridger" & year < "2021-22" ~ "K-8",
                            school == "Bridger" & year < "2023-24" ~ "K-5",
                            TRUE ~ "K-8 (Bridger Creative Science)"))

# cross-check against PPS's own enrollment report (K-12, excluding PK) for 2024-25 and 2025-26
pps <- by_grade |> filter(year %in% c("2024-25", "2025-26"), grade != "PK", key %in% c("lent", "cesarchavez")) |>
  mutate(program = if_else(language %in% "Spanish", "Spanish", "Neighborhood")) |>
  group_by(school = if_else(key == "lent", "Lent", "César Chávez"), program, year) |> summarise(pps = sum(enrollment), .groups = "drop")
chk <- hist |> inner_join(pps, by = c("school", "program", "year")) |> filter(enrollment != pps)
if (nrow(chk)) stop("PSU actuals differ from PPS enrollment report:\n", paste(capture.output(print(as.data.frame(chk))), collapse = "\n"))
write_csv(hist, here("data", "history_enrollment.csv"))

proj <- read_csv(here("data", "guide_enrollment.csv"), show_col_types = FALSE) |>
  filter(school %in% c("Lent", "Cesar Chavez")) |>
  mutate(school = if_else(school == "Cesar Chavez", "César Chávez", school)) |>
  select(school, scenario, year, enrollment)
write_csv(proj, here("data", "history_projection.csv"))

cat("Enrollment by program (PSU actuals, K-12):\n")
print(as.data.frame(hist |> select(school, program, year, enrollment) |> pivot_wider(names_from = year, values_from = enrollment)), row.names = FALSE)
cat("\nPPS projections (school guides):\n")
print(as.data.frame(proj |> pivot_wider(names_from = year, values_from = enrollment)), row.names = FALSE)
