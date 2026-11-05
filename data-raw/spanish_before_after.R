# Makeup of Spanish immersion before and after the 2023 Bridger -> Lent move, with Atkinson's Spanish
# program (same region, never moved) as the comparison. This compares programs, not students: nobody
# has published who stayed in or left Bridger's program.
#
# Inputs:
#   data-raw/se_baseline_2021_dli.csv   hand-entered from PPS's SEGC baseline sheet (Attachment A, May 24, 2022,
#                                       data-raw/pps_board/se_balancing_attachment_a_baseline_2022-05-24.pdf):
#                                       students, BIPOC and ELL from 2021-22; low income from 2020-21
#   data/race_by_program_2025.csv, data/dli_track_profiles.csv, data/school_demographics.csv
# Output: data/equity_spanish_before_after.csv

suppressMessages({library(dplyr); library(readr); library(here)})
base <- read_csv(here("data-raw", "se_baseline_2021_dli.csv"), show_col_types = FALSE)
race <- read_csv(here("data", "race_by_program_2025.csv"), show_col_types = FALSE)
prof <- read_csv(here("data", "dli_track_profiles.csv"), show_col_types = FALSE)
demo <- read_csv(here("data", "school_demographics.csv"), show_col_types = FALSE)

# Hand entry check: each school's two program rows must reproduce its printed Total row.
for (s in unique(base$school)) {
  p <- filter(base, school == s, program != "Total"); t <- filter(base, school == s, program == "Total")
  stopifnot(sum(p$students) == t$students)
  for (m in c("pct_bipoc", "pct_ell", "pct_low_income")) {
    w <- weighted.mean(p[[m]], p$students)
    if (abs(w - t[[m]]) > 0.51) stop(sprintf("%s %s: programs give %.1f, Total row prints %.1f", s, m, w, t[[m]]))
  }
}

# The sheet's ELL column and PPS's immersion profiles must be the same measure in 2021-22.
ml21 <- filter(prof, year == "2021-22", school %in% c("Atkinson", "Bridger", "Lent"))
chk <- inner_join(filter(base, program == "Spanish"), ml21, by = "school")
stopifnot(all(chk$students == chk$immersion_total), all(abs(100 * chk$ml_and_immersion / chk$students - chk$pct_ell) <= 0.51))

ml_of <- function(s, y) prof$ml_and_immersion[prof$school %in% s & prof$year == y]
spanish <- filter(base, program == "Spanish")
before <- function(s, label) {
  d <- filter(spanish, school %in% s)
  tibble(group = label, period = "before", students = sum(d$students), not_white = weighted.mean(d$pct_bipoc, d$students),
         ml = sum(ml_of(s, "2021-22")), low_income = weighted.mean(d$pct_low_income, d$students))
}
after <- function(s, label, low_income) {
  r <- filter(race, school == s, program == "Spanish Immersion")
  p <- filter(prof, school == s, year == "2025-26")
  stopifnot(r$total == p$immersion_total)
  tibble(group = label, period = "after", students = r$total, not_white = 100 * (1 - r$white_n / r$total), ml = p$ml_and_immersion, low_income = low_income)
}
# Lent is all immersion, so its whole-school direct certification rate is the program's. PPS publishes none by program elsewhere.
lent_low <- 100 * demo$pct_direct_cert[demo$year == "2025-26" & demo$row_type == "School" & demo$name == "Lent"]
atk_school_low <- 100 * demo$pct_direct_cert[demo$year == "2025-26" & demo$row_type == "School" & demo$name == "Atkinson"]
out <- bind_rows(before(c("Bridger", "Lent"), "moved"), after("Lent", "moved", lent_low),
                 before("Atkinson", "stayed"), after("Atkinson", "stayed", NA_real_),
                 tibble(group = "atkinson_school", period = c("before", "after"), low_income = c(base$pct_low_income[base$school == "Atkinson" & base$program == "Total"], atk_school_low))) |>
  mutate(pct_ml = 100 * ml / students)
stopifnot(sum(out$students[out$period == "before" & out$group == "moved"]) == 337)
write_csv(out, here("data", "equity_spanish_before_after.csv"))
print(out)
