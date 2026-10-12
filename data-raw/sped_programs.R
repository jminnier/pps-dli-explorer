# Special education classrooms in the rightsizing scenarios (School changes page, #sec-sped).
#
# Inputs
#   data-raw/sped/sped_allocation_2026_27_raw.csv  "SPED" tab of the Google Sheet "Board Request as of 9/22"
#       (2026-27 projected special education staffing by school; shared in the PPS Community Advocacy group;
#       see data-raw/sped/README.md). Staff positions, not students.
#   data-raw/sped/sped_moves.csv  hand-entered: one row per special education program the PPS school guides
#       (October 8, 2026, page 3) say would move, with the guide's sentence.
#   data/plan_schools.csv  each school's role in each scenario (school_changes.R).
# Outputs
#   data/sped_allocation_2026_27.csv  tidy staffing by school.
#   data/sped_moves.csv  one row per scenario and program move, with the staff positions at the sending school
#       and whether each receiving school already has that kind of classroom.
# Checks: every school matches plan_schools.csv; every closing school (or school losing grades 6-8) with an
# SES, CB or ISC position has a row in sped_moves.csv.

suppressPackageStartupMessages({ library(dplyr); library(tidyr); library(readr); library(purrr) })
here <- function(...) file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)))), "..", ...)
old_wd <- setwd(here()); source("R/site_data.R"); setwd(old_wd)

# ---- staffing sheet -----------------------------------------------------------------------------
raw <- read_csv(here("data-raw", "sped", "sped_allocation_2026_27_raw.csv"), col_types = cols(.default = "c"), na = c("", "NA"),
                name_repair = "minimal")
stopifnot("unexpected sheet layout" = ncol(raw) == 13, grepl("LC FTE", names(raw)[3]),
          identical(trimws(names(raw)[4:13]), c("SES", "CB", "ISC", "QMHP", "SES Paras", "CB Paras", "ISC Paras", "1-1 Para", "NSM Building Para", "TIC")))
num <- function(x) suppressWarnings(as.numeric(x))   # "//" and blanks -> NA
names(raw) <- c("row", "school", "lc_fte", "ses", "cb", "isc", "qmhp", "ses_paras", "cb_paras", "isc_paras", "one_on_one_paras", "nsm_building_para", "tic")
alloc <- raw |> select(-row) |> mutate(across(-school, num)) |>
  filter(!is.na(school), school != "School") |>
  mutate(school = recode(school, "Lee" = "Sunrise", "RoseWay Heights" = "Roseway Heights"), key = school_key(school)) |>
  mutate(across(c(ses, cb, isc, ses_paras, cb_paras, isc_paras), \(x) coalesce(x, 0))) |>
  relocate(key)
stopifnot(!anyDuplicated(alloc$key))

ps <- read_csv(here("data", "plan_schools.csv"), show_col_types = FALSE)
unmatched <- setdiff(alloc$key, c(ps$key, "access"))   # ACCESS Academy (TAG program) is not in the race report or the plan
if (length(unmatched)) stop("staffing rows with no school in plan_schools.csv: ", paste(unmatched, collapse = ", "))
cat(sprintf("staffing sheet: %d schools; SES %g, CB %g, ISC %g teacher positions; %g Learning Center FTE\n",
            nrow(alloc), sum(alloc$ses), sum(alloc$cb), sum(alloc$isc), sum(alloc$lc_fte, na.rm = TRUE)))

# ---- program moves from the guides ----------------------------------------------------------------
mv <- read_csv(here("data-raw", "sped", "sped_moves.csv"), show_col_types = FALSE) |>
  mutate(scen = strsplit(scenario, "")) |> unnest(scen) |> select(-scenario) |> rename(scenario = scen) |>
  mutate(from_key = school_key(from_school))
stopifnot(all(mv$from_key %in% ps$key))
col <- c(SES = "ses", CB = "cb", ISC = "isc")
staff <- function(k, prog, what = "") {   # positions (or paras) of this program at school k; NA for DHH (CRIS, not in sheet)
  if (!prog %in% names(col)) return(NA_real_)
  v <- alloc[[paste0(col[[prog]], what)]][alloc$key == k]
  if (length(v)) v else 0
}
has_type <- function(to, prog) {           # does each receiving school have this kind of classroom today?
  if (!prog %in% names(col)) return(NA_character_)
  ks <- school_key(trimws(strsplit(to, " or ")[[1]]))
  paste(ifelse(vapply(ks, \(k) staff(k, prog) > 0, logical(1)), "yes", "no"), collapse = " / ")
}
out <- mv |>
  left_join(ps |> select(scenario, from_key = key, from_role = role), by = c("scenario", "from_key")) |>
  mutate(positions = map2_dbl(from_key, program, staff), paras = map2_dbl(from_key, program, \(k, p) staff(k, p, "_paras")),
         to_has_type = map2_chr(to_school, program, has_type)) |>
  select(scenario, from_school, from_role, program, grades, to_school, status, positions, paras, to_has_type, source, quote) |>
  arrange(scenario, status != "named", program, from_school)

# Every school that closes (or sends away grades 6-8 with a focus classroom) and has a focus position needs a row.
need <- ps |> filter(role == "Closes") |> select(scenario, key) |>
  bind_rows(tibble(scenario = c("a", "b"), key = "beverlycleary")) |>
  inner_join(alloc |> filter(ses + cb + isc > 0) |> select(key), by = "key")
missing <- anti_join(need, mv, by = c("scenario", "key" = "from_key"))
if (nrow(missing)) stop("closing schools with focus classrooms but no row in sped_moves.csv: ", paste(missing$scenario, missing$key, collapse = "; "))
stopifnot(all(out$from_role[out$status != "stays"] %in% c("Closes", "Takes in students and sends some away", "Sends students away")))

write_csv(alloc, here("data", "sped_allocation_2026_27.csv"))
write_csv(out, here("data", "sped_moves.csv"))
for (s in c("a", "b")) {
  o <- filter(out, scenario == s, status != "stays", program != "DHH")
  cat(sprintf("Scenario %s: %d focus-classroom moves from %d schools; %g teacher positions, %g paras\n",
              toupper(s), nrow(o), n_distinct(o$from_school), sum(o$positions), sum(o$paras)))
}
