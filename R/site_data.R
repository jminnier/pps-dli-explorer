# Shared data loading and helpers for the Quarto pages. Every table is read from data/, which the
# scripts in data-raw/ build from PPS, PSU and Census sources (see methods.qmd).
suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readr); library(stringr)
})

data_path <- function(...) file.path(here_root, "data", ...)
here_root <- local({
  d <- getwd()
  while (!file.exists(file.path(d, "_quarto.yml")) && dirname(d) != d) d <- dirname(d)
  d
})

LANGUAGES <- c("Spanish", "Mandarin", "Japanese", "Russian", "Vietnamese")
SCENARIOS <- c(sq = "Status quo", a = "Scenario A", b = "Scenario B")
BANDS <- c("K-5", "6-8", "9-12")
LOTTERY_YEARS <- c("2022-23", "2023-24", "2024-25", "2025-26", "2026-27") # 2021-22 prints no grade

# Reference palette (dataviz skill, validated): categorical slots in fixed order, light / dark.
PAL <- list(
  light = c(blue = "#2a78d6", orange = "#eb6834", aqua = "#1baf7a"),
  dark  = c(blue = "#3987e5", orange = "#d95926", aqua = "#199e70"),
  ink = "#0b0b0b", ink2 = "#52514e", muted = "#8a8984", grid = "#e7e6e2"
)
SCENARIO_COL <- c(sq = PAL$light[["blue"]], a = PAL$light[["orange"]], b = PAL$light[["aqua"]])

# Same normalisation as the map's schoolKey (src/lib/changes.mjs), so names from the map, the PPS
# enrollment PDFs and the lottery reports join: "Dr. Martin Luther King Jr." / "MLK Jr" -> "mlkjr".
school_key <- function(x) {
  k <- x |>
    str_remove("\\s(K-5|K-8|K-12|2-8|Middle|High|School|Building|Elementary)\\b.*$") |>
    stringi::stri_trans_general("Latin-ASCII") |> tolower() |>
    str_replace("metro\\.?\\s", "metropolitan ") |> str_remove_all("[^a-z]")
  aliases <- c(drmartinlutherkingjr = "mlkjr", martinlutherkingjr = "mlkjr", robertgray = "gray",
               sunnyside = "sunnysideenvironmental", bridger = "bridgercreativescience", chavez = "cesarchavez",
               lane = "brentwood")
  ifelse(k %in% names(aliases), aliases[k], k)
}

read_data <- function(f) read_csv(data_path(f), show_col_types = FALSE)

sites <- read_data("dli_sites.csv")
moves <- read_data("dli_moves.csv")
profiles <- read_data("dli_track_profiles.csv") |> mutate(key = school_key(school))
by_grade <- read_data("enrollment_by_program_grade.csv") |> mutate(key = school_key(school))
by_lang <- read_data("enrollment_by_language.csv") |> mutate(key = school_key(school))
lottery <- read_data("lottery_results.csv") |>
  mutate(key = school_key(coalesce(pps_school, school)), across(c(slots:not_placed), as.numeric))
access_tract <- read_data("access_tract.csv")
acs <- read_data("acs_language_tract.csv")

# Kindergarten (entry-grade) immersion lottery per school and year. Uses the printed school Total
# rows where a year prints them, otherwise the sum of applicant-group rows.
lottery_k <- lottery |>
  filter(level == "ES", !is.na(language), grade %in% c("K", NA)) |>
  group_by(key, year) |>
  filter(if (any(is_total)) is_total else !is_total) |>
  summarise(school = first(coalesce(pps_school, school)), language = first(language),
            applications = sum(applications, na.rm = TRUE), offered = sum(offered, na.rm = TRUE),
            waitlisted = sum(waitlisted, na.rm = TRUE), .groups = "drop")

lottery_avg <- lottery_k |>
  filter(year %in% LOTTERY_YEARS) |>
  group_by(key, school, language) |>
  summarise(years = n(), applications = mean(applications), offered = mean(offered),
            waitlisted = mean(waitlisted), .groups = "drop")

# Current immersion students in the grades a move affects (2025-26 October enrollment).
band_grades <- list(`K-5` = c("K", as.character(1:5)), `6-8` = as.character(6:8), `9-12` = as.character(9:12))
strand_students <- function(key, language, band) {
  g <- band_grades[[band]]
  sum(by_grade$enrollment[by_grade$year == "2025-26" & by_grade$key == key &
                            by_grade$language %in% language & by_grade$grade %in% g])
}

# Share of a school's immersion students whose home language is the program language (2025-26).
heritage_share <- function(key, language) {
  col <- if (language == "Mandarin") "Chinese" else language
  d <- by_lang |> filter(year == "2025-26", key == !!key, program_language == !!language)
  if (!nrow(d)) return(NA_real_)
  sum(d$students[d$language == col]) / sum(d$students)
}

fmt_n <- function(x) formatC(round(x), format = "d", big.mark = ",")
fmt_pct <- function(x) ifelse(is.na(x), "–", paste0(round(100 * x), "%"))
