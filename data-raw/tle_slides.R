# Tables hand-entered from PPS's October 13, 2026 Teaching, Learning and Enrollment Committee decks
# (data-raw/pps_board/tle_dli_programs_2026-10-13.pdf, tle_middle_grades_2026-10-13.pdf; BoardBook meeting 771664).
# The PDFs are Google Slides exports; text was read with PyMuPDF. Checks: printed totals on middle grades slide 5.
#
# Outputs
#   data/tle_dli_k_2026_27.csv   DLI slide 4: kindergarten enrollment and lottery slots by language, 2026-27.
#   data/tle_k8_subsidy.csv      middle grades slide 5: 6-8 enrollment and teacher FTE in each K-8, the formula FTE a
#                                comprehensive middle school would get, and the difference (the "subsidy").

suppressPackageStartupMessages({ library(dplyr); library(readr); library(tibble) })
here <- function(...) file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)))), "..", ...)

dli_k <- tribble(
  ~language,    ~enrolled_k, ~lottery_slots_k,
  "Chinese",    102,         127,
  "Japanese",   101,         104,
  "Russian",    14,          25,
  "Spanish",    250,         278,
  "Vietnamese", 38,          52
)

k8 <- tribble(
  ~school,                     ~enroll_6_8, ~actual_fte, ~formula_fte, ~subsidy_fte, ~subsidy_usd,
  "ACCESS",                    161, 8.9,  7.0, 1.9, 304000,
  "Astor",                     146, 8.4,  6.4, 2.0, 320000,
  "Beverly Cleary",            191, 9.8,  8.2, 1.6, 256000,
  "Bridger Creative Science",  131, 8.4,  5.6, 2.8, 448000,
  "César Chávez",              147, 9.2,  7.4, 1.8, 288000,
  "Faubion",                   209, 10.8, 10.0, 0.8, 128000,
  "Laurelhurst",               226, 12.0, 9.8, 2.2, 352000,
  "Metropolitan Learning Center", 136, 8.4, 5.8, 2.6, 416000,
  "Odyssey",                   81,  4.4,  3.6, 0.8, 128000,
  "Skyline",                   73,  4.4,  3.2, 1.2, 192000,
  "Sunnyside Environmental",   186, 8.4,  8.0, 0.4, 64000,
  "Vernon",                    181, 8.8,  7.8, 1.0, 160000,
  "Winterhaven",               149, 8.4,  6.4, 2.0, 320000
)

# Printed totals (slide 5): 2,017 students, 110.3 actual FTE, 89.2 formula FTE, 21.1 FTE, $3,376,000.
stopifnot(sum(k8$enroll_6_8) == 2017, isTRUE(all.equal(sum(k8$actual_fte), 110.3)), isTRUE(all.equal(sum(k8$formula_fte), 89.2)),
          isTRUE(all.equal(sum(k8$subsidy_fte), 21.1)), sum(k8$subsidy_usd) == 3376000,
          isTRUE(all.equal(k8$actual_fte - k8$formula_fte, k8$subsidy_fte)))
stopifnot(all(abs(k8$subsidy_usd - 160000 * k8$subsidy_fte) < 1))   # each row priced at $160,000 per FTE

write_csv(dli_k, here("data", "tle_dli_k_2026_27.csv"))
write_csv(k8, here("data", "tle_k8_subsidy.csv"))
cat("tle_slides: checks passed\n")
