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

# Source citations (markdown), used under every table and figure. Details in methods.qmd.
PPS_REPORTS <- "https://www.pps.net/departments/dataaccountability/data-and-accountability/data-strategy-and-insights/data-and-reporting"
PPS_ARCHIVE <- "https://www.pps.net/departments/dataaccountability/data-and-accountability/data-strategy-and-insights/archives"
PPS_LOTTERY <- "https://www.pps.net/departments/enrollment-transfer/transfer-english/lottery/prior-transfer-data"
SRC <- list(
  profiles = sprintf("PPS, *Enrollment Details for Language Immersion Schools* (Language Immersion Track Profiles), October 2021–October 2025 ([current](%s), [archive](%s))", PPS_REPORTS, PPS_ARCHIVE),
  by_grade = sprintf("PPS, *Enrollment by Grade and Program Type*, October 2024 and October 2025 ([PPS Data & Reporting](%s))", PPS_REPORTS),
  by_lang = sprintf("PPS, *Enrollment by Language and School*, October 2024 and October 2025 ([PPS Data & Reporting](%s))", PPS_REPORTS),
  lottery = sprintf("PPS Enrollment & Transfer, *Elementary School / Kindergarten Lottery Results Summary*, lotteries for 2022-23 through 2026-27 ([prior lottery results](%s))", PPS_LOTTERY),
  lottery26 = sprintf("PPS Enrollment & Transfer, *2026-27 Kindergarten Lottery Results Summary* ([prior lottery results](%s))", PPS_LOTTERY),
  class_size = sprintf("PPS, *Class Size Detail*, 2021-22 through 2025-26 ([archive](%s), [current](%s))", PPS_ARCHIVE, PPS_REPORTS),
  district_k = sprintf("district enrollment by grade: PPS, *Enrollment – Summary Comparison*, October 3, 2022 ([archive](%s)), and *Enrollment by Grade and Program Type*, 2024 and 2025", PPS_ARCHIVE),
  scenarios = "PPS board packet for October 6, 2026: scenario maps and *Rightsizing Update: Scenario Release* memo, as digitized and transcribed in [pps-explorer](https://github.com/browniefed/pps-explorer) by Jason Brown",
  acs = "US Census Bureau, American Community Survey 2020–2024 5-year estimates, tables C16001 and B16007, census tracts in Multnomah, Washington and Clackamas counties",
  blocks = "US Census Bureau, 2020 Census redistricting data (P.L. 94-171), tables P1 and P3, census blocks",
  slide44 = "PPS Board of Education, *10/06/26 PowerPoint*, slide 44, \"Balance and Impact: Kindergarten – 8th Grade Students Who Move\" ([BoardBook](https://meetings.boardbook.org/Documents/DownloadPDF/14511742?org=915))",
  memo = "PPS, *Rightsizing Update: Scenario Release* board memo, October 5, 2026, pp. 1–2 ([BoardBook](https://meetings.boardbook.org/Documents/DownloadPDF/14509719?org=915))",
  closures = "school closures and receiving schools: PPS scenario maps and memo (October 2026) as transcribed in [pps-explorer](https://github.com/browniefed/pps-explorer)",
  demographics = sprintf("PPS, *School/Neighborhood Enrollment by Ethnicity & Program*, October 2025 (School rows; [PPS Data & Reporting](%s))", PPS_REPORTS),
  audit = "Green, T. L., & Hanson, H. (2026, June 10). *Equity audit evaluation of Portland Public Schools' Southeast Enrollment and Program Balancing*",
  tle0908 = "PPS Board of Education Teaching, Learning, and Enrollment Committee, September 8, 2026, at 33:22 ([video](https://www.youtube.com/watch?v=S-pk57P6f_o&t=2002s); automated transcript via [Save PDX Schools](https://savepdxschools.org/transcripts/))",
  summary10 = "PPS, *October 2025 Enrollment Summary, 10-year detail*, footnote 6 (\"Bridger Spanish Immersion moved to Lent\")",
  psu_premove = sprintf("Portland State University Population Research Center, *Portland Public Schools Enrollment Forecasts*, 2022-23, 2023-24 and 2026-27 editions (Appendix C / Table 5.5; [archive](%s))", PPS_ARCHIVE),
  guides = "PPS, *How Could Your School Be Impacted?* school guides (\"PPS Family-Friendly School Guide\", per-school PDFs dated October 8, 2026), page 4, projected enrollment 2027-28 to 2031-32 ([page](https://www.pps.net/about/portland-public-schools-information/rightsize/how-could-your-school-be-impacted))",
  audit_schools = "Green, T. L., & Hanson, H. (2026, June 29). *Equity audit evaluation of Portland Public Schools' Southeast Enrollment and Program Balancing initiative: School-by-school analysis* ([PPS SEGC documents](https://www.pps.net/about/portland-public-schools-information/rightsize/segc-documents))",
  capture = sprintf("PPS, *Neighborhood Capture Rate Metrics* (Enrollment Summary by K-12 Students' Neighborhood and Type of School Attended), October 2019 to October 2025 ([current](%s), [archive](%s))", PPS_REPORTS, PPS_ARCHIVE),
  by_residence = sprintf("PPS, *School Enrollment by Neighborhood of Residence*, October 2025 ([PPS Data & Reporting](%s))", PPS_REPORTS),
  isp = "National Center for Education Statistics, *Private School Universe Survey*, 2023-24 ([International School of Portland](https://nces.ed.gov/surveys/pss/privateschoolsearch/school_list.asp?Search=1&SchoolName=International+School+of+Portland&State=41)); grade counts as shown by [US News](https://www.usnews.com/education/k12/oregon/international-school-of-portland-324304); languages from the [school's website](https://www.intlschool.org/about-us/about), accessed October 8, 2026",
  lrfp = "PPS, *Long-Range Facility Plan 2021*, Volume 1, p. 53 (elementary) and p. 57 (K-8), functional capacity ([PDF](https://www.pps.net/fs/resource-manager/view/84245cbd-4298-4803-8ba9-d26fb13a9c7a)); compiled in [meub/pps-data](https://github.com/meub/pps-data) by Alex Meub (MIT license)",
  profiles25 = "PPS, *School Profiles*, 2025-26 (Power BI dashboard: functional capacity, utilization, enrollment, direct certification, capture rate; [page](https://www.pps.net/departments/dataaccountability/data-and-accountability/data-strategy-and-insights/internal-school-profiles)), retrieved October 9, 2026",
  tle0908s ="PPS Board of Education Teaching, Learning, and Enrollment Committee, September 8, 2026, at 13:15 ([video](https://www.youtube.com/watch?v=S-pk57P6f_o&t=795s); automated transcript via [Save PDX Schools](https://savepdxschools.org/transcripts/))",
  ode_assess = "Oregon Department of Education, *Assessment Group Reports* (state, district and school results by student group; [page](https://www.oregon.gov/ode/educator-resources/assessment/Pages/Assessment-Group-Reports.aspx)), accessed October 9, 2026",
  board1006 = "PPS Board of Education, regular meeting, October 6, 2026, staff presentation at 2:25:37 ([video](https://www.youtube.com/watch?v=zOUH2Jq7Owo&t=8737s); automated transcript via [Save PDX Schools](https://savepdxschools.org/transcripts/))",
  steele2017 = "Steele, J. L., Slater, R. O., Zamarro, G., Miller, T., Li, J., Burkhauser, S., & Bacon, M. (2017). Effects of dual-language immersion programs on student achievement: Evidence from lottery data. *American Educational Research Journal, 54*(1 suppl), 282S–306S ([doi](https://doi.org/10.3102/0002831216634463); [open manuscript](https://files.eric.ed.gov/fulltext/ED577026.pdf)); RAND brief [RB-9903](https://www.rand.org/pubs/research_briefs/RB9903.html)",
  rand_impl = "Li, J. J., Steele, J. L., Slater, R., Bacon, M., & Miller, T. (2016). *Implementing two-way dual-language immersion programs: Classroom insights from an urban district* (RAND Research Brief [RB-9921](https://www.rand.org/pubs/research_briefs/RB9921.html))",
  utah2021 = "Steele, J. L., Watzinger-Tharp, J., Slater, R. O., Roberts, G., & Bowman, K. (2021). *Achievement effects of dual language immersion in one-way and two-way programs: Evidence from a state scale-up in Utah* (working paper, University of Arkansas, [PDF](https://edre.uark.edu/_resources/pdf/Utah_DLI_2021Jan.pdf))",
  watzinger = "Watzinger-Tharp, J., Swenson, K., & Mayne, Z. (2018). Academic achievement of students in dual language immersion. *International Journal of Bilingual Education and Bilingualism, 21*(8), 913–928 ([doi](https://doi.org/10.1080/13670050.2016.1214675))",
  morales = "Morales, C. (2025). Dual language immersion programs and student achievement in early elementary grades. *Educational Evaluation and Policy Analysis, 47*(2), 616–623 ([doi](https://doi.org/10.3102/01623737241228829)); abstract only",
  bibler = "Bibler, A. J. Dual language education and student achievement. *Education Finance and Policy* ([doi](https://doi.org/10.1162/edfp_a_00320); quotes from the 2016 [working paper](https://economics.nd.edu/assets/187323/paper_dual_language_education_bibler_1_19.pdf), p. 6)",
  cal = "Howard, E. R., Lindholm-Leary, K. J., Rogers, D., Olague, N., Medina, J., Kennedy, D., Sugarman, J., & Christian, D. (2018). *Guiding principles for dual language education* (3rd ed.). Center for Applied Linguistics ([publisher](https://www.cal.org/publications/guiding-principles-3/))",
  cabe = "California Association for Bilingual Education, *Dual Language Immersion Planning Guide*, \"Implementation model\" ([page](https://di.gocabe.org/get-started/pedagogical-decisions/implementation-model)), accessed October 9, 2026",
  freire = "Freire, J. A., & Alemán, E., Jr. (2021). \"Two schools within a school\": Elitism, divisiveness, and intra-racial gentrification in a dual language strand. *Bilingual Research Journal, 44*(2), 249–269 ([doi](https://doi.org/10.1080/15235882.2021.1942325)); abstract",
  dejong = "de Jong, E. J., & Bearse, C. I. (2014). Dual language programs as a strand within a secondary school: Dilemmas of school organization and the TWI mission. *International Journal of Bilingual Education and Bilingualism, 17*(1), 15–31 ([doi](https://doi.org/10.1080/13670050.2012.725709)); abstract",
  nasem = "National Academies of Sciences, Engineering, and Medicine. (2017). *Promoting the educational success of children and youth learning English: Promising futures*, ch. 8, p. 300 ([read online](https://nap.nationalacademies.org/read/24677/chapter/10))",
  methods = "Method details: [Sources & methods](methods.qmd)"
)
# Spanish pages (es/) set options(site.lang = "es") before sourcing this file; their citations use the Spanish
# wording in R/site_data_es.R (document titles stay in their original language).
SITE_ES <- identical(getOption("site.lang"), "es")
if (SITE_ES) {
  source(file.path(here_root, "R", "site_data_es.R"))
  missing_es <- setdiff(names(SRC), names(SRC_ES))
  if (length(missing_es)) stop("R/site_data_es.R has no Spanish citation for: ", paste(missing_es, collapse = ", "))
  SRC <- SRC_ES[names(SRC)]
}
cite <- function(...) paste0(if (SITE_ES) "**Fuentes:** " else "**Sources:** ", paste(unlist(SRC[c(...)]), collapse = "; "), ". ", SRC$methods, ".")

fmt_n <- function(x) formatC(round(x), format = "d", big.mark = ",")
fmt_pct <- function(x) ifelse(is.na(x), "–", paste0(round(100 * x), "%"))
