# Freeway distance (data/freeway_distance.csv)

Built by `data-raw/freeway_distance.R` from OpenStreetMap (Overpass API; the response is cached in
`data-raw/osm/overpass_freeways_schools.json`, snapshot 2026-10-13T02:16Z). See methods.qmd `#freeway`.

The first version (Oct 12, 2026) was computed by hand in a browser on a flat local projection. The script
reproduces it: the same OSM grounds for all 82 schools, and distances within 7 m for the 43 schools that run
measured within its 1.5 km search box. The browser run left schools beyond that box blank; the script measures
every school.

Limits: OSM grounds outlines are volunteer-mapped and may include or exclude fields and adjoining parks.
Distance ignores wind, terrain, sound walls, traffic volume and trucks. Busy arterials (82nd, Powell,
Lombard, Columbia Blvd) are not counted. Reference: EPA (2015) *Best Practices for Reducing Near-Road
Pollution Exposure at Schools*: concentrations highest within ~150 m (500 ft), background by ~600 m (2,000 ft).
