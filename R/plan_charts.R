# Figures for the School changes page (schools.qmd, es/schools.qmd), built from data/plan_schools.csv and
# data/plan_segregation.csv (data-raw/school_changes.R). Labels switch to Spanish when the page sets
# options(site.lang = "es"), so both pages run the same code.
#
# Encoding (validated PAL slots, the site's scenario colours, marker shape as a second cue because aqua is
# below 3:1 contrast): hollow gray ring = today, orange diamond = Scenario A, aqua square = Scenario B.

PC <- list(
  en = list(
    role = c("Closes" = "Closes", "Program moves to another building" = "Program moves to another building",
             "Takes in students" = "Takes in students", "Takes in students and sends some away" = "Takes in students and sends some away",
             "Sends students away" = "Sends some students away", "Boundary or feeder change only" = "Boundary or feeder change only",
             "No change" = "No change"),
    schools = "Number of schools", now = "Today (October 2025)", a = "Scenario A", b = "Scenario B",
    students_now = "students today", t1 = "Title I", sun = "SUN", hu = "Share of students from underserved racial groups",
    race = c(latino = "Latino", black = "Black", asian = "Asian", white = "White", asian_white = "Multiracial: Asian and White",
             other_multi = "Multiracial: other", native_american = "Native American", pacific_islander = "Pacific Islander"),
    takes_in = "takes in", sends = "sends away", students = "students", closes = "closes",
    latino_share = "Latino students", white_share = "White students",
    by_building = "Each building as one unit", by_program = "Each program as one unit",
    hdr_building = "By building", hdr_program = "By program", hdr_latino = "Latino", hdr_white = "White",
    d_axis = "Latino–white dissimilarity index (0 = even, 1 = fully separate)",
    area = c("All elementary (K-5 and K-8) schools" = "All elementary schools", "All middle schools" = "All middle schools",
             "Northeast: Scott, Rigler, Rose City Park, Vestal" = "Northeast: Scott, Rigler, Rose City Park, Vestal",
             "North: MLK Jr., Sabin, Boise-Eliot/Humboldt" = "North: MLK Jr., Sabin, Boise-Eliot/Humboldt",
             "Southeast: Atkinson, Lent, Creston" = "Southeast: Atkinson, Lent, Creston")
  ),
  es = list(
    role = c("Closes" = "Cierra", "Program moves to another building" = "El programa se muda a otro edificio",
             "Takes in students" = "Recibe estudiantes", "Takes in students and sends some away" = "Recibe estudiantes y envía a otros",
             "Sends students away" = "Envía a algunos estudiantes", "Boundary or feeder change only" = "Solo cambia de zona o de escuela de continuación",
             "No change" = "Sin cambios"),
    schools = "Número de escuelas", now = "Hoy (octubre de 2025)", a = "Escenario A", b = "Escenario B",
    students_now = "estudiantes hoy", t1 = "Título I", sun = "SUN", hu = "Porcentaje de estudiantes de grupos raciales desatendidos",
    race = c(latino = "Latinos", black = "Afrodescendientes", asian = "Asiáticos", white = "Blancos", asian_white = "Multirraciales: asiáticos y blancos",
             other_multi = "Multirraciales: otros", native_american = "Nativos americanos", pacific_islander = "De las islas del Pacífico"),
    takes_in = "recibe", sends = "envía", students = "estudiantes", closes = "cierra",
    latino_share = "Estudiantes latinos", white_share = "Estudiantes blancos",
    by_building = "Cada edificio como una unidad", by_program = "Cada programa como una unidad",
    hdr_building = "Por edificio", hdr_program = "Por programa", hdr_latino = "Latinos", hdr_white = "Blancos",
    d_axis = "Índice de disimilitud entre latinos y blancos (0 = parejo, 1 = totalmente separados)",
    area = c("All elementary (K-5 and K-8) schools" = "Todas las primarias", "All middle schools" = "Todas las intermedias",
             "Northeast: Scott, Rigler, Rose City Park, Vestal" = "Noreste: Scott, Rigler, Rose City Park, Vestal",
             "North: MLK Jr., Sabin, Boise-Eliot/Humboldt" = "Norte: MLK Jr., Sabin, Boise-Eliot/Humboldt",
             "Southeast: Atkinson, Lent, Creston" = "Sureste: Atkinson, Lent, Creston")
  )
)
pc_lab <- function() if (exists("SITE_ES") && isTRUE(SITE_ES)) PC$es else PC$en
PC_COL <- c(now = PAL$muted, a = PAL$light[["orange"]], b = PAL$light[["aqua"]])
PC_SYM <- c(a = "diamond", b = "square")
PC_SIZE <- c(a = 9, b = 12)
ROLES <- c("Closes", "Program moves to another building", "Takes in students", "Takes in students and sends some away",
           "Sends students away", "Boundary or feeder change only", "No change")
short_school <- function(x) dplyr::recode(x, "Dr. Martin Luther King Jr." = "MLK Jr.", "Cesar Chavez" = "César Chávez",
                                          "Boise-Eliot-Humboldt" = "Boise-Eliot/Humboldt", "Metropolitan Learning Center" = "MLC",
                                          "Bridger-Creative Science" = "Bridger")
p1 <- function(x) sprintf("%.0f%%", 100 * x)
race_tip <- function(d, L, when) {   # one line per group, now -> after
  g <- names(L$race)
  vapply(seq_len(nrow(d)), function(i) paste(sprintf("%s: %s → %s", L$race[g],
    p1(unlist(d[i, paste0(g, "_now")]) / d$students_now[i]), p1(unlist(d[i, paste0(g, "_after")]) / d$students_after[i])), collapse = "<br>"),
    character(1))
}

# 1. Bars: number of schools in each role, Scenario A and B; hover gives students today, Title I and SUN.
fig_plan_roles <- function(ps) {
  L <- pc_lab()
  d <- ps |> mutate(role = factor(role, ROLES)) |> group_by(scenario, role) |>
    summarise(n = n(), students = sum(students_now), t1 = sum(title1_2026_27), sun = sum(sun_2026_27), .groups = "drop") |>
    mutate(lab = factor(wrap_label(L$role[as.character(role)], 24), rev(wrap_label(L$role[ROLES], 24))))
  d$tip <- sprintf("<b>%s</b> (%s)<br>%d · %s %s<br>%s: %d · %s: %d", L$role[as.character(d$role)], unlist(L[d$scenario]), d$n,
                   fmt_n(d$students), L$students_now, L$t1, d$t1, L$sun, d$sun)
  p <- plot_ly()
  for (s in c("b", "a")) {
    p <- add_bars(p, data = filter(d, scenario == s), x = ~n, y = ~lab, orientation = "h", name = L[[s]],
                  marker = list(color = PC_COL[[s]], line = list(color = "white", width = 1)),
                  text = ~n, textposition = "outside", textfont = list(color = PAL$ink2, size = 11), cliponaxis = FALSE,
                  hovertext = ~tip, hoverinfo = "text")
  }
  viz_layout(p, xtitle = L$schools) |> layout(barmode = "group", bargap = 0.3, xaxis = list(rangemode = "tozero"),
                                              legend = list(traceorder = "reversed"))
}

# 2. Before/after rows (fig-home style): share from underserved racial groups at each school that takes
#    in students, today (ring) and in Scenario A (diamond) and B (square). Hover lists every group.
fig_plan_receivers <- function(ps) {
  L <- pc_lab()
  d <- ps |> filter(grepl("^Takes in", role)) |> mutate(school = short_school(school))
  ord <- d |> filter(scenario == "a") |> arrange(hu_after - hu_now) |> pull(school)
  ord <- unique(c(ord, d$school))
  d$y <- factor(d$school, rev(ord))
  d$tip <- sprintf("<b>%s</b> (%s)<br>%s %s %s · %s %s<br>%s", d$school, unlist(L[d$scenario]), L$takes_in, fmt_n(d$students_in), L$students,
                   L$sends, fmt_n(d$students_out), race_tip(d, L))
  today <- d |> distinct(y, school, hu_now, students_now)
  rng <- d |> group_by(y) |> summarise(lo = min(c(hu_now, hu_after)), hi = max(c(hu_now, hu_after)))
  p <- plot_ly() |>
    add_segments(data = rng, x = ~lo, xend = ~hi, y = ~y, yend = ~y, line = list(color = PAL$grid, width = 2), hoverinfo = "skip", showlegend = FALSE) |>
    identity()
  for (s in c("b", "a")) {   # B under A, both under the hollow ring, so equal values stay visible
    p <- add_markers(p, data = filter(d, scenario == s), x = ~hu_after, y = ~y, name = L[[s]], text = ~tip, hoverinfo = "text",
                     marker = list(color = PC_COL[[s]], symbol = PC_SYM[[s]], size = PC_SIZE[[s]], line = list(color = "white", width = 1)))
  }
  p <- add_markers(p, data = today, x = ~hu_now, y = ~y, name = L$now, hoverinfo = "text",
                   text = ~sprintf("<b>%s</b><br>%s: %s (%s %s)", school, L$now, p1(hu_now), fmt_n(students_now), L$students),
                   marker = list(color = "rgba(0,0,0,0)", size = 13, line = list(color = PAL$muted, width = 2)))
  viz_layout(p, xtitle = wrap_label(L$hu, 32)) |> layout(xaxis = list(tickformat = ".0%", range = c(0, 1)), legend = list(traceorder = "reversed"))
}

# 3. Two panels (Latino share, white share): schools in the three local clusters, today vs A vs B.
fig_plan_clusters <- function(ps) {
  L <- pc_lab()
  CL <- list(c("Scott", "Rigler", "Rose City Park", "Vestal"), c("Dr. Martin Luther King Jr.", "Sabin", "Boise-Eliot-Humboldt"),
             c("Atkinson", "Lent", "Creston"))
  d <- ps |> filter(school %in% unlist(CL)) |> mutate(school = short_school(school))
  ord <- short_school(unlist(CL))
  d$y <- factor(d$school, rev(ord))
  long <- bind_rows(
    d |> filter(scenario == "a") |> transmute(y, school, state = "now", n = students_now, latino = latino_now, white = white_now),
    d |> filter(!closes) |> transmute(y, school, state = scenario, n = students_after, latino = latino_after, white = white_after)) |>
    mutate(latino = latino / n, white = white / n)
  st_lab <- c(now = L$now, a = L$a, b = L$b)
  panel <- function(col, legend) {
    rng <- long |> group_by(y) |> summarise(lo = min(.data[[col]]), hi = max(.data[[col]]))
    p <- plot_ly() |>
      add_segments(data = rng, x = ~lo, xend = ~hi, y = ~y, yend = ~y, line = list(color = PAL$grid, width = 2), hoverinfo = "skip", showlegend = FALSE)
    for (s in c("b", "a", "now")) {   # ring drawn last so equal values stay visible
      ds <- filter(long, state == s)
      mk <- if (s == "now") list(color = "rgba(0,0,0,0)", size = 13, line = list(color = PAL$muted, width = 2)) else
        list(color = PC_COL[[s]], symbol = PC_SYM[[s]], size = PC_SIZE[[s]], line = list(color = "white", width = 1))
      p <- add_markers(p, data = ds, x = ds[[col]], y = ~y, name = st_lab[[s]], legendgroup = s, showlegend = legend, marker = mk, hoverinfo = "text",
                       text = sprintf("<b>%s</b> (%s)<br>%s: %s<br>%s: %s<br>%s %s", ds$school, st_lab[[s]], L$latino_share, p1(ds$latino),
                                      L$white_share, p1(ds$white), fmt_n(ds$n), L$students))
    }
    p
  }
  ax <- list(gridcolor = PAL$grid, zerolinecolor = PAL$grid, linecolor = PAL$grid, tickformat = ".0%", range = c(0, 1), tickvals = c(0, 0.4, 0.8), tickangle = 0,
             tickfont = list(color = PAL$ink2, size = 12))
  hdr <- function(x, txt) list(text = paste0("<b>", txt, "</b>"), x = x, xref = "paper", xanchor = "center", y = 1, yref = "paper", yanchor = "bottom",
                               showarrow = FALSE, font = list(color = PAL$ink2, size = 13))
  s <- subplot(panel("latino", TRUE), panel("white", FALSE), shareY = TRUE, margin = 0.04)
  viz_layout(s) |> layout(xaxis = ax, xaxis2 = ax, annotations = list(hdr(0.24, L$hdr_latino), hdr(0.76, L$hdr_white)),
                          legend = list(y = 1.08, traceorder = "reversed"))
}

# 4. Two panels: Latino-white dissimilarity index by area, counting buildings vs programs, today vs A vs B.
fig_plan_segregation <- function(seg) {
  L <- pc_lab()
  d <- seg |> mutate(area_lab = factor(wrap_label(L$area[area], 26), rev(wrap_label(unname(L$area), 26))))
  st_lab <- c(now = L$now, a = L$a, b = L$b)
  panel <- function(u, legend) {
    du <- filter(d, unit == u)
    rng <- du |> group_by(area_lab) |> summarise(lo = min(latino_white_D), hi = max(latino_white_D))
    p <- plot_ly() |>
      add_segments(data = rng, x = ~lo, xend = ~hi, y = ~area_lab, yend = ~area_lab, line = list(color = PAL$grid, width = 2), hoverinfo = "skip", showlegend = FALSE)
    for (s in c("b", "a", "now")) {
      ds <- filter(du, state == s)
      mk <- if (s == "now") list(color = "rgba(0,0,0,0)", size = 13, line = list(color = PAL$muted, width = 2)) else
        list(color = PC_COL[[s]], symbol = PC_SYM[[s]], size = PC_SIZE[[s]], line = list(color = "white", width = 1))
      p <- add_markers(p, data = ds, x = ~latino_white_D, y = ~area_lab, name = st_lab[[s]], legendgroup = s, showlegend = legend, marker = mk,
                       hoverinfo = "text", text = sprintf("<b>%s</b> (%s)<br>%s: %.2f", L$area[ds$area], st_lab[[s]],
                                                          if (u == "building") L$by_building else L$by_program, ds$latino_white_D))
    }
    p
  }
  ax <- list(gridcolor = PAL$grid, zerolinecolor = PAL$grid, linecolor = PAL$grid, range = c(0, 0.7), dtick = 0.2, tickangle = 0,
             tickfont = list(color = PAL$ink2, size = 12))
  hdr <- function(x, txt) list(text = paste0("<b>", txt, "</b>"), x = x, xref = "paper", xanchor = "center", y = 1, yref = "paper", yanchor = "bottom",
                               showarrow = FALSE, font = list(color = PAL$ink2, size = 12))
  s <- subplot(panel("building", TRUE), panel("program", FALSE), shareY = TRUE, margin = 0.04)
  viz_layout(s) |> layout(xaxis = ax, xaxis2 = ax, annotations = list(hdr(0.24, L$hdr_building), hdr(0.76, L$hdr_program)),
                          legend = list(y = 1.12, traceorder = "reversed"))
}
