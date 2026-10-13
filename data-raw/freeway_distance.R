# Distance from each PPS school's grounds to the nearest freeway (Equity page, #sec-freeway).
#
# Sources: OpenStreetMap via the Overpass API (ODbL). Freeways = highway=motorway (mainline) and
# highway=motorway_link (ramps). School grounds = the amenity=school polygon that contains each school's map
# point (data/plan_school_points.csv, plus high schools and ACCESS from public/data/sq_*_schools.geojson).
# Cleveland High's polygon (way 32353700) is tagged disused:amenity=school; it is fetched by id.
# The Overpass response is cached in data-raw/osm/ (delete it to refresh).
#
# Distances are in meters, in UTM zone 10N (EPSG:32610):
#   grounds_to_freeway_m              grounds edge -> nearest mainline freeway (0 if they touch)
#   grounds_to_any_ramp_or_freeway_m  grounds edge -> nearest mainline or ramp
#   point_to_freeway_m                map point (roughly the building) -> nearest mainline
# The query box covers all of PPS, so every school gets a distance (the first, browser-based run left schools
# more than ~1.5 km away blank). Fails if a school point is not inside exactly one chosen polygon.

suppressPackageStartupMessages({ library(dplyr); library(readr); library(purrr); library(sf); library(httr2) })
here <- function(...) file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)))), "..", ...)
old_wd <- setwd(here()); source("R/site_data.R"); setwd(old_wd)
sf_use_s2(FALSE)

# ---- OpenStreetMap ------------------------------------------------------------------------------
cache <- here("data-raw", "osm", "overpass_freeways_schools.json")
if (!file.exists(cache)) {
  dir.create(dirname(cache), showWarnings = FALSE)
  q <- '[out:json][timeout:180];
(
  way["highway"~"^(motorway|motorway_link)$"](45.40,-122.90,45.68,-122.45);
  way["amenity"="school"](45.40,-122.90,45.68,-122.45);
  way(32353700);
);
out tags geom;'
  request("https://overpass-api.de/api/interpreter") |>
    req_user_agent("pps-dli-explorer (independent analysis; github.com/jminnier/pps-dli-explorer)") |>
    req_body_form(data = q) |> req_timeout(240) |> req_retry(max_tries = 3) |>
    req_perform(path = cache)
}
osm <- jsonlite::read_json(cache)
cat("OSM snapshot:", osm$osm3s$timestamp_osm_base, "\n")
el <- keep(osm$elements, \(e) e$type == "way" && length(e$geometry) >= 2)
tag <- function(e, k) if (is.null(e$tags[[k]])) NA_character_ else e$tags[[k]]
coords <- function(e) do.call(rbind, lapply(e$geometry, \(g) c(g$lon, g$lat)))

hw <- keep(el, \(e) !is.na(tag(e, "highway")))
roads <- st_sf(id = map_dbl(hw, "id"), highway = map_chr(hw, tag, "highway"), ref = map_chr(hw, tag, "ref"),
               geometry = st_sfc(lapply(hw, \(e) st_linestring(coords(e))), crs = 4326)) |> st_transform(32610)
sc <- keep(el, \(e) (identical(tag(e, "amenity"), "school") || e$id == 32353700) && {
  m <- coords(e); nrow(m) >= 4 && all(m[1, ] == m[nrow(m), ]) })
grounds <- st_sf(osm_way = map_dbl(sc, "id"), name = map_chr(sc, tag, "name"),
                 geometry = st_sfc(lapply(sc, \(e) st_polygon(list(coords(e)))), crs = 4326)) |>
  st_make_valid() |> st_transform(32610) |> mutate(grounds_m2 = as.numeric(st_area(geometry)))
cat(sprintf("freeway segments: %d mainline, %d ramps; school polygons: %d\n",
            sum(roads$highway == "motorway"), sum(roads$highway == "motorway_link"), nrow(grounds)))

# ---- school points ------------------------------------------------------------------------------
gj <- function(f) { s <- st_read(here("public", "data", f), quiet = TRUE); xy <- st_coordinates(s)
  tibble(name = s$name, lon = xy[, 1], lat = xy[, 2]) |> mutate(key = recode(school_key(name), wellsbarnett = "idabwellsbarnett")) }
plan_pts <- read_csv(here("data", "plan_school_points.csv"), show_col_types = FALSE)
extra <- bind_rows(gj("sq_912_schools.geojson"), gj("sq_k5_schools.geojson")) |>
  filter(key %in% setdiff(c(key[grepl("High|9-12", name)], "access"), plan_pts$key)) |> distinct(key, .keep_all = TRUE)
pts <- bind_rows(plan_pts, extra |> select(key, lon, lat)) |> distinct(key, .keep_all = TRUE) |>
  st_as_sf(coords = c("lon", "lat"), crs = 4326, remove = FALSE) |> st_transform(32610)

# Each point -> the smallest school polygon containing it.
hit <- st_join(pts, grounds, join = st_within) |> st_drop_geometry() |>
  group_by(key) |> slice_min(grounds_m2, n = 1, with_ties = FALSE) |> ungroup()
# A point just outside its own grounds (a map point on the street edge) takes the nearest school polygon within 30 m.
miss <- hit$key[is.na(hit$osm_way)]
for (k in miss) {
  d <- as.numeric(st_distance(pts[pts$key == k, ], grounds)); j <- which.min(d)
  if (d[j] > 30) stop("school point outside every OSM school polygon (nearest ", round(d[j]), " m): ", k)
  cat(sprintf("note: %s point is %.0f m outside OSM way %.0f (%s); using it\n", k, d[j], grounds$osm_way[j], grounds$name[j]))
  hit[hit$key == k, c("osm_way", "name", "grounds_m2")] <- st_drop_geometry(grounds[j, c("osm_way", "name", "grounds_m2")])
}

# ---- distances ----------------------------------------------------------------------------------
main <- filter(roads, highway == "motorway"); anyr <- roads
nearest <- function(geom, lines) { d <- st_distance(geom, lines); list(m = apply(d, 1, min), i = apply(d, 1, which.min)) }
g <- grounds[match(hit$osm_way, grounds$osm_way), ]
p <- pts[match(hit$key, pts$key), ]
gm <- nearest(g, main); ga <- nearest(g, anyr); pm <- nearest(p, main)
clean_ref <- function(r) { r <- sub(";.*", "", r); sub("^I ", "I-", r) }
cap <- function(x) round(x)
out <- hit |> transmute(key, osm_way, grounds_m2 = round(grounds_m2),
                        grounds_to_freeway_m = cap(gm$m), freeway = clean_ref(main$ref[gm$i]),
                        grounds_to_any_ramp_or_freeway_m = cap(ga$m), point_to_freeway_m = cap(pm$m)) |>
  arrange(key)

# ---- check against the first (browser) run, then write --------------------------------------------
prev_f <- here("data", "freeway_distance.csv")
if (file.exists(prev_f)) {
  prev <- read_csv(prev_f, show_col_types = FALSE)
  cmp <- inner_join(prev, out, by = "key", suffix = c("_prev", "_new"))
  cat(sprintf("compared %d schools; same OSM way for %d\n", nrow(cmp), sum(cmp$osm_way_prev == cmp$osm_way_new)))
  for (v in c("grounds_to_freeway_m", "grounds_to_any_ramp_or_freeway_m", "point_to_freeway_m")) {
    a <- cmp[[paste0(v, "_prev")]]; b <- cmp[[paste0(v, "_new")]]
    both <- !is.na(a) & !is.na(b)
    cat(sprintf("  %-34s max |diff| %4.0f m over %d pairs; blank in one only: %d\n", v, max(abs(a - b)[both]), sum(both), sum(xor(is.na(a), is.na(b)))))
  }
}
stopifnot(nrow(out) == nrow(pts), !anyDuplicated(out$key))
write_csv(out, prev_f, na = "")
cat(sprintf("wrote %d schools; %d within 150 m of a mainline freeway\n", nrow(out), sum(out$grounds_to_freeway_m <= 150, na.rm = TRUE)))
