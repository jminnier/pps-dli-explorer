# Check the modeled home-to-school distances (equity_analysis.R) against where immersion students
# actually live, from PPS's School Enrollment by Neighborhood of Residence report (October 2025).
#
# The model places each immersion program's families in the census blocks nearest the program's current
# site. The report gives, for each school and program, how many students live in the school's own
# attendance area and, for everyone else, which high-school area they live in. Here those counts are
# placed on census blocks:
#   own neighborhood   -> blocks in the school's status-quo attendance area (its grade band)
#   high-school area X -> blocks in high-school area X, outside the school's own attendance area
#   Jefferson/Grant, Jefferson/McDaniel, Jefferson/Roosevelt -> blocks in the Jefferson area, split by
#     which of the Grant / McDaniel / Roosevelt areas is nearest (the report doesn't map these sub-areas)
#   out of district / undetermined -> left out (share reported)
# Within each area, students are spread like children under 18 (2020 Census). Two placements are
# reported: all of the area's children ("area average"), and only the half of the area's children who
# live closest to the program's current school ("nearer half", since families who choose a program tend
# to live closer to it). Distances are straight lines to the current site and to the scenario's new site.
#
# Usage: Rscript data-raw/check_home_distance.R  ->  data/equity_home_check.csv, data/equity_home_check_summary.csv

suppressPackageStartupMessages({ library(sf); library(dplyr); library(tidyr); library(readr) })
sf_use_s2(FALSE)
here <- function(...) file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)))), "..", ...)
old_wd <- setwd(here()); source("R/site_data.R"); setwd(old_wd)
CRS <- 2838; M_PER_MI <- 1609.344
BANDS_FILE <- c(`K-5` = "k5", `6-8` = "68")

ebn <- read_csv(here("data", "enroll_by_neighborhood.csv"), show_col_types = FALSE) |>
  filter(year == "2025-26") |> mutate(key = school_key(school))
model <- read_csv(here("data", "equity_home_distance.csv"), show_col_types = FALSE) |> filter(type == "Immersion program moves")

blocks <- readRDS(here("data-raw", "acs", "decennial2020_blocks_u18.rds")) |> st_transform(CRS) |>
  mutate(u18 = pmax(total - adult, 0)) |> filter(u18 > 0)
bp <- st_point_on_surface(st_geometry(blocks))
hs <- st_read(here("public", "data", "sq_912.geojson"), quiet = TRUE) |> st_make_valid() |> st_transform(CRS) |>
  mutate(area = sub(" High School$", "", name), area = if_else(area == "Wells-Barnett", "Ida B. Wells-Barnett", area))
in_hs <- st_intersects(bp, hs)
blocks$hs <- hs$area[vapply(in_hs, \(x) if (length(x)) x[1] else NA_integer_, 1L)]
# Jefferson sub-areas: nearest of the Grant / McDaniel / Roosevelt areas
jf <- which(blocks$hs == "Jefferson")
cand <- hs |> filter(area %in% c("Grant", "McDaniel", "Roosevelt"))
blocks$hs[jf] <- paste0("Jefferson/", cand$area[apply(st_distance(bp[jf], cand), 1, which.min)])

areas <- function(band) st_read(here("public", "data", sprintf("sq_%s.geojson", BANDS_FILE[[band]])), quiet = TRUE) |>
  st_make_valid() |> mutate(key = school_key(name)) |> st_transform(CRS)

moves_used <- moves |> filter(kind %in% c("program", "grades")) |> distinct(scenario, language, band, from_school, from_key, to_school, to_lon, to_lat, from_lon, from_lat)
out <- list()
for (i in seq_len(nrow(moves_used))) {
  mv <- moves_used[i, ]
  r <- ebn |> filter(key == mv$from_key, program == paste(mv$language, "Immersion"))
  if (!nrow(r)) { message("no residence row for ", mv$from_school, " ", mv$language); next }
  own <- areas(mv$band) |> filter(key == mv$from_key)
  if (!nrow(own)) { message("no attendance area for ", mv$from_school, " ", mv$band); next }
  in_own <- lengths(st_intersects(bp, own)) > 0
  from_pt <- st_sfc(st_point(c(mv$from_lon, mv$from_lat)), crs = 4326) |> st_transform(CRS)
  to_pt <- st_sfc(st_point(c(mv$to_lon, mv$to_lat)), crs = 4326) |> st_transform(CRS)
  res <- list()
  for (j in seq_len(nrow(r))) {
    a <- r[j, ]
    if (a$students == 0 || a$area_level == "other") next
    sel <- if (a$area_level == "own_neighborhood") in_own else (!in_own & blocks$hs %in% a$residence_area)
    if (!any(sel)) stop("no blocks for ", a$residence_area, " (", mv$from_school, ")")
    d0 <- as.numeric(st_distance(bp[sel], from_pt)) / M_PER_MI
    d1 <- as.numeric(st_distance(bp[sel], to_pt)) / M_PER_MI
    w <- blocks$u18[sel]
    near <- d0 <= {o <- order(d0); d0[o][which(cumsum(w[o]) >= sum(w) / 2)[1]]}
    res[[j]] <- tibble(area = a$residence_area, students = a$students,
                       b0 = weighted.mean(d0, w), b1 = weighted.mean(d1, w),
                       n0 = weighted.mean(d0[near], w[near]), n1 = weighted.mean(d1[near], w[near]))
  }
  res <- bind_rows(res)
  m <- model |> filter(scenario == mv$scenario, from_school == mv$from_school, language == mv$language, band == mv$band)
  out[[length(out) + 1]] <- tibble(
    scenario = mv$scenario, language = mv$language, band = mv$band, from_school = mv$from_school, to_school = mv$to_school,
    students = sum(r$students), own_area = sum(r$students[r$area_level == "own_neighborhood"]),
    out_of_district = sum(r$students[r$area_level == "other"]),
    before_mi = weighted.mean(res$b0, res$students), after_mi = weighted.mean(res$b1, res$students),
    before_mi_nearer = weighted.mean(res$n0, res$students), after_mi_nearer = weighted.mean(res$n1, res$students),
    model_before_mi = m$before_mi[1], model_after_mi = m$after_mi[1])
}
# weight moves as the model's summary does: students in the grades that move (equity_changes.csv)
moving <- read_csv(here("data", "equity_changes.csv"), show_col_types = FALSE) |> filter(type == "Immersion program moves") |>
  distinct(scenario, from_school, language, band, .keep_all = TRUE) |> select(scenario, from_school, language, band, moving = students)
chk <- bind_rows(out) |> left_join(moving, by = c("scenario", "from_school", "language", "band")) |>
  mutate(change_mi = after_mi - before_mi, change_mi_nearer = after_mi_nearer - before_mi_nearer, model_change_mi = model_after_mi - model_before_mi)
write_csv(chk, here("data", "equity_home_check.csv"))

summ <- chk |> filter(!is.na(model_change_mi)) |> group_by(scenario) |>
  summarise(across(c(before_mi, after_mi, change_mi, before_mi_nearer, after_mi_nearer, change_mi_nearer, model_before_mi, model_after_mi, model_change_mi),
                   \(v) weighted.mean(v, moving)),
            own_share = sum(own_area) / sum(students), moving = sum(moving), .groups = "drop")
write_csv(summ, here("data", "equity_home_check_summary.csv"))
cat("Per move (miles):\n")
print(as.data.frame(chk |> mutate(across(where(is.numeric) & !c(students, own_area, out_of_district), \(v) round(v, 2))) |>
  select(scenario, from_school, to_school, language, band, students, own_area, before_mi, after_mi, change_mi, change_mi_nearer, model_before_mi, model_after_mi, model_change_mi)), row.names = FALSE)
cat("\nStudent-weighted averages:\n")
print(as.data.frame(summ |> mutate(across(where(is.numeric) & !moving, \(v) round(v, 2)))), row.names = FALSE)
