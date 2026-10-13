# Figures and tables for the School changes page (schools.qmd, es/schools.qmd), built from data/plan_schools.csv and
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
    schools = "Number of schools", schools_word = "schools", now = "Today (October 2025)", a = "Scenario A", b = "Scenario B",
    students_now = "students today", t1 = "Title I", sun = "SUN", hu = "Share of students from underserved racial groups",
    race = c(latino = "Latino", black = "Black", asian = "Asian", white = "White", asian_white = "Multiracial: Asian and White",
             other_multi = "Multiracial: other", native_american = "Native American", pacific_islander = "Pacific Islander"),
    hu_short = "Underserved racial groups, today → after", takes_in = "takes in", sends = "sends away", students = "students", closes = "closes",
    latino_share = "Latino students", white_share = "White students",
    by_building = "Each building as one unit", by_program = "Each program as one unit",
    hdr_building = "By building", hdr_program = "By program", hdr_latino = "Latino", hdr_white = "White",
    t1_cat = c(tt = "Move from a Title I school to a Title I school", tn = "Move from a Title I school to a school that would not be Title I",
               nt = "Move from a non-Title I school to a Title I school", lose = "Stay at a school that would lose Title I",
               gain = "Stay at a school that would become Title I"),
    enrolled_today = "Students enrolled today", stays = "stay",
    aff = c(closes = "Their school closes", odyssey = "Their whole program moves to another building (Odyssey)",
            prog = "Their program or grades move out of a school that stays open",
            move = "Change buildings", take = "Stay at a school that takes in students",
            send = "Stay at a school that loses a program or grades", sub = "Change buildings or see their school change",
            bound = "At a school with only a boundary or feeder change", total = "All students at a school the plan changes"),
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
    schools = "Número de escuelas", schools_word = "escuelas", now = "Hoy (octubre de 2025)", a = "Escenario A", b = "Escenario B",
    students_now = "estudiantes hoy", t1 = "Título I", sun = "SUN", hu = "Porcentaje de estudiantes de grupos raciales desatendidos",
    race = c(latino = "Latinos", black = "Afrodescendientes", asian = "Asiáticos", white = "Blancos", asian_white = "Multirraciales: asiáticos y blancos",
             other_multi = "Multirraciales: otros", native_american = "Nativos americanos", pacific_islander = "De las islas del Pacífico"),
    hu_short = "Grupos raciales desatendidos, hoy → después", takes_in = "recibe", sends = "envía", students = "estudiantes", closes = "cierra",
    latino_share = "Estudiantes latinos", white_share = "Estudiantes blancos",
    by_building = "Cada edificio como una unidad", by_program = "Cada programa como una unidad",
    hdr_building = "Por edificio", hdr_program = "Por programa", hdr_latino = "Latinos", hdr_white = "Blancos",
    t1_cat = c(tt = "Pasan de una escuela de Título I a otra de Título I", tn = "Pasan de una escuela de Título I a una que no sería de Título I",
               nt = "Pasan de una escuela sin Título I a una de Título I", lose = "Se quedan en una escuela que perdería el Título I",
               gain = "Se quedan en una escuela que pasaría a ser de Título I"),
    enrolled_today = "Estudiantes inscritos hoy", stays = "se quedan",
    aff = c(closes = "Su escuela cierra", odyssey = "Todo su programa se muda a otro edificio (Odyssey)",
            prog = "Su programa o sus grados salen de una escuela que sigue abierta",
            move = "Cambian de edificio", take = "Se quedan en una escuela que recibe estudiantes",
            send = "Se quedan en una escuela que pierde un programa o grados", sub = "Cambian de edificio o su escuela cambia",
            bound = "En una escuela que solo cambia de zona o de escuela de continuación", total = "Todos los estudiantes de escuelas que el plan cambia"),
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
    fmt_share(unlist(d[i, paste0(g, "_now_pct")]), d$students_now[i]), fmt_share(unlist(d[i, paste0(g, "_after_pct")]), d$students_after[i])), collapse = "<br>"),
    character(1))
}

# School names for a hover box: sorted, a few per line so the box stays narrow on phones.
school_lines <- function(x, per_line = 4) {
  x <- sort(short_school(x))
  paste(vapply(split(x, ceiling(seq_along(x) / per_line)), paste, character(1), collapse = ", "), collapse = ",<br>")
}

# Students the plan affects, one row per kind of change (October 2025 enrollment). Each student is counted once:
# at a school that sends some students away, those who leave count as "change buildings" and the rest by
# what happens to the school. The total equals all students at schools whose role is not "No change".
plan_affected <- function(ps) {
  one <- function(s) {
    d <- ps[ps$scenario == s, ]; r <- function(roles, col) sum(d[[col]][d$role %in% roles])
    stay <- function(roles) r(roles, "students_now") - r(roles, "students_out")
    v <- c(closes = r("Closes", "students_now"), odyssey = r("Program moves to another building", "students_now"),
           prog = r(c("Sends students away", "Takes in students and sends some away"), "students_out"))
    v <- c(v, move = sum(v), take = stay(c("Takes in students", "Takes in students and sends some away")),
           send = stay("Sends students away"))
    v <- c(v, sub = sum(v[c("move", "take", "send")]), bound = r("Boundary or feeder change only", "students_now"))
    v <- c(v, total = sum(v[c("sub", "bound")]))
    stopifnot(abs(v[["total"]] - sum(d$students_now[d$role != "No change"])) < 1)
    tibble::tibble(row = names(v), students = unname(v), share = unname(v) / sum(d$students_now))
  }
  dplyr::full_join(one("a"), one("b"), by = "row", suffix = c("_a", "_b"))
}
tbl_plan_affected <- function(ps) {
  L <- pc_lab(); d <- plan_affected(ps)
  bold <- d$row %in% c("move", "sub", "total")
  cell <- function(n, p) sprintf("%s (%s)", fmt_n(n), p1(p))
  d |> dplyr::transmute(row = unname(L$aff[row]), a = cell(students_a, share_a), b = cell(students_b, share_b)) |> gt::gt() |>
    gt::cols_label(row = "", a = L$a, b = L$b) |> gt::cols_align("right", c(a, b)) |>
    gt::tab_style(gt::cell_text(weight = "bold"), gt::cells_body(rows = bold)) |>
    gt::tab_style(gt::cell_borders(sides = "top", color = PAL$ink2, weight = gt::px(1.5)), gt::cells_body(rows = bold)) |>
    gt::tab_style(gt::cell_text(indent = gt::px(14)), gt::cells_body(columns = row, rows = !bold))
}

# 1. Bars: number of schools in each role, Scenario A and B; hover gives students today, Title I and SUN.
fig_plan_roles <- function(ps) {
  L <- pc_lab()
  d <- ps |> mutate(role = factor(role, ROLES)) |> group_by(scenario, role) |>
    summarise(n = n(), students = sum(students_now), t1 = sum(title1_2026_27), sun = sum(sun_2026_27),
              names = school_lines(school), .groups = "drop") |>
    mutate(lab = factor(wrap_label(L$role[as.character(role)], 24), rev(wrap_label(L$role[ROLES], 24))))
  d$tip <- sprintf("<b>%s</b> (%s)<br>%d %s · %s %s<br>%s: %d %s · %s: %d %s<br><br>%s", L$role[as.character(d$role)], unlist(L[d$scenario]), d$n, L$schools_word,
                   fmt_n(d$students), L$students_now, L$t1, d$t1, L$schools_word, L$sun, d$sun, L$schools_word, d$names)
  p <- plot_ly()
  for (s in c("b", "a")) {
    p <- add_bars(p, data = filter(d, scenario == s), x = ~n, y = ~lab, orientation = "h", name = L[[s]],
                  marker = list(color = PC_COL[[s]], line = list(color = "white", width = 1)),
                  text = ~n, textposition = "outside", textfont = list(color = PAL$ink2, size = 11), cliponaxis = FALSE,
                  hovertext = ~tip, hoverinfo = "text", hoverlabel = list(align = "left"))
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
  d$tip <- sprintf("<b>%s</b><br>%s<br>%s: %s → %s<br>%s %s %s · %s %s<br><br>%s", d$school, unlist(L[d$scenario]), L$hu_short, p1(d$hu_now), p1(d$hu_after),
                   L$takes_in, fmt_n(d$students_in), L$students, L$sends, fmt_n(d$students_out), race_tip(d, L))
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
    d |> filter(scenario == "a") |> transmute(y, school, state = "now", n = students_now, latino_p = latino_now_pct, white_p = white_now_pct),
    d |> filter(!closes) |> transmute(y, school, state = scenario, n = students_after, latino_p = latino_after_pct, white_p = white_after_pct)) |>
    mutate(latino = small_x(latino_p, n), white = small_x(white_p, n))   # a hidden share (<5 students) is drawn at 2.5 students' worth
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
                       text = sprintf("<b>%s</b><br>%s<br>%s: %s<br>%s: %s<br>%s %s", ds$school, st_lab[[s]], L$latino_share, fmt_share(ds$latino_p, ds$n),
                                      L$white_share, fmt_share(ds$white_p, ds$n), fmt_n(ds$n), L$students))
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
                       hoverinfo = "text", text = sprintf("<b>%s</b><br>%s<br>%s<br>%s: %.2f", L$area[ds$area], st_lab[[s]],
                                                          if (u == "building") L$by_building else L$by_program, L$d_axis, ds$latino_white_D))
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

# 5. Bars: students the changes touch, by Title I status before and after (PPS's guide designations, which
#    leave out bridge schools). Moves use each flow's sending school today and receiving school after;
#    stayers are students at schools whose own status would change. Hover lists the flows or schools.
t1_groups <- function(ps, fl) {
  st <- function(s, k, col) { v <- ps[[col]][ps$scenario == s & ps$key == k]; if (length(v)) v[1] else "No" }
  mv <- fl |> mutate(fk = school_key(from_school), tk = school_key(to_school)) |> rowwise() |>
    mutate(from_t1 = st(scenario, fk, "title1_guide_now"), to_t1 = st(scenario, tk, "title1_guide_after")) |> ungroup() |>
    mutate(cat = case_when(from_t1 == "Yes" & to_t1 == "Yes" ~ "tt", from_t1 == "Yes" ~ "tn", to_t1 == "Yes" ~ "nt", TRUE ~ NA_character_)) |>
    filter(!is.na(cat)) |>
    transmute(scenario, cat, students, item = sprintf("%s → %s", short_school(from_school), short_school(to_school)))
  stay <- ps |> filter(!is.na(title1_guide_after), title1_guide_after != "", title1_guide_now != title1_guide_after) |>
    transmute(scenario, cat = if_else(title1_guide_after == "No", "lose", "gain"), students = students_now - students_out,
              item = short_school(school))
  bind_rows(mv, stay)
}
fig_plan_title1 <- function(ps, fl) {
  L <- pc_lab()
  g <- t1_groups(ps, fl)
  d <- g |> group_by(scenario, cat) |> arrange(desc(students), .by_group = TRUE) |>
    summarise(n = sum(students), items = paste(sprintf("%s: %s", item, fmt_n(students)), collapse = "<br>"), .groups = "drop") |>
    complete(scenario, cat = names(L$t1_cat), fill = list(n = 0, items = "–")) |>
    mutate(lab = factor(wrap_label(L$t1_cat[cat], 30), rev(wrap_label(unname(L$t1_cat), 30))),
           tip = sprintf("<b>%s</b> (%s)<br>%s %s<br><br>%s", L$t1_cat[cat], unlist(L[scenario]), fmt_n(n), L$students, items))
  p <- plot_ly()
  for (s in c("b", "a")) {
    p <- add_bars(p, data = filter(d, scenario == s), x = ~n, y = ~lab, orientation = "h", name = L[[s]],
                  marker = list(color = PC_COL[[s]], line = list(color = "white", width = 1)),
                  text = ~fmt_n(n), textposition = "outside", textfont = list(color = PAL$ink2, size = 11), cliponaxis = FALSE,
                  hovertext = ~tip, hoverinfo = "text", hoverlabel = list(align = "left"))
  }
  viz_layout(p, xtitle = L$enrolled_today) |> layout(barmode = "group", bargap = 0.3, xaxis = list(range = c(0, 1.25 * max(d$n)), nticks = 3, tickangle = 0, tickformat = "~s"),
                                                     legend = list(traceorder = "reversed"), margin = list(r = 30))
}

# 6. Map: one circle per K-8, middle and alternative school; area = students, colour = share from underserved
# racial groups, in three views (today, Scenario A, Scenario B) picked with radio buttons. A dark outline marks a
# share that moves 5+ points; a dashed gray ring marks a school that closes or whose program moves out.
# Design inspired by the scenario map on ppsdata.info (Alex Meub). Leaflet, not plotly: plotly's map circles
# can't draw outlines or dashed rings.
PC$en$map <- list(
  views = c(now = "Today", a = "Scenario A", b = "Scenario B"),
  bins = c("Under 20%", "20% to 34%", "35% to 49%", "50% to 64%", "65% or more"),
  color = "Share of students from underserved racial groups", size = "Circle size: students",
  outline = "Dark ring: share changes by 5 points or more", closed = "Dashed gray ring: school closes or its program moves",
  students = "Students", hu = "Underserved racial groups", today = "today", after = "after", points = "points",
  gone = "No students left in this building", t1 = "Title I school today", sun = "SUN Community School today"
)
PC$es$map <- list(
  views = c(now = "Hoy", a = "Escenario A", b = "Escenario B"),
  bins = c("Menos de 20%", "De 20% a 34%", "De 35% a 49%", "De 50% a 64%", "65% o más"),
  color = "Porcentaje de estudiantes de grupos raciales desatendidos", size = "Tamaño del círculo: estudiantes",
  outline = "Anillo oscuro: el porcentaje cambia 5 puntos o más", closed = "Anillo gris punteado: la escuela cierra o su programa se muda",
  students = "Estudiantes", hu = "Grupos raciales desatendidos", today = "hoy", after = "después", points = "puntos",
  gone = "No quedan estudiantes en este edificio", t1 = "Escuela de Título I hoy", sun = "Escuela Comunitaria SUN hoy"
)
MAP_RAMP <- c("#86b6ef", "#5598e7", "#2a78d6", "#1c5cab", "#0d366b")   # PAL blue steps 250-700, validated (--ordinal)
MAP_BREAKS <- c(-Inf, 0.20, 0.35, 0.50, 0.65, Inf)
MAP_SHIFT <- 0.05                                                     # outline when the share moves this much
map_radius <- function(n) 0.5 * sqrt(n)                               # px; area proportional to students (160 -> 6, 924 -> 15)

map_views <- function(ps, pts) {
  base <- ps |> filter(level != "High") |> inner_join(pts, by = "key")
  now <- base |> filter(scenario == "a") |>
    transmute(view = "now", key, school, lon, lat, title1_2026_27, sun_2026_27, role = NA_character_,
              n = students_now, hu = hu_now, n0 = students_now, hu0 = hu_now, gone = FALSE)
  after <- base |> transmute(view = scenario, key, school, lon, lat, title1_2026_27, sun_2026_27, role,
                             n = students_after, hu = hu_after, n0 = students_now, hu0 = hu_now, gone = students_after == 0)
  bind_rows(now, after) |>
    mutate(shift = !gone & view != "now" & abs(round(100 * hu) - round(100 * hu0)) >= 100 * MAP_SHIFT,   # on the whole points shown
           bin = cut(hu, MAP_BREAKS, labels = FALSE, right = FALSE))
}

fig_plan_map <- function(ps, pts) {
  L <- pc_lab(); M <- L$map
  d <- map_views(ps, pts)
  tip <- function(x) {
    head <- sprintf("<b>%s</b>", short_school(x$school))
    role <- ifelse(x$view == "now", "", sprintf("<br>%s", L$role[x$role]))
    dp <- round(100 * x$hu) - round(100 * x$hu0)   # change in whole points, as shown
    body <- ifelse(x$view == "now",
      sprintf("<br>%s: %s<br>%s: %s", M$students, fmt_n(x$n), M$hu, p1(x$hu)),
      ifelse(x$gone, sprintf("<br>%s %s: %s<br>%s", M$students, M$today, fmt_n(x$n0), M$gone),
        sprintf("<br>%s: %s %s → %s %s<br>%s: %s → %s (%s%.0f %s)", M$students, fmt_n(x$n0), M$today, fmt_n(x$n), M$after,
                M$hu, p1(x$hu0), p1(x$hu), ifelse(dp > 0, "+", ifelse(dp < 0, "−", "")), abs(dp), M$points)))
    flags <- paste0(ifelse(x$title1_2026_27, sprintf("<br>%s", M$t1), ""), ifelse(x$sun_2026_27, sprintf("<br>%s", M$sun), ""))
    lapply(paste0(head, role, body, flags), htmltools::HTML)
  }
  m <- leaflet::leaflet(options = leaflet::leafletOptions(scrollWheelZoom = FALSE, minZoom = 10, zoomSnap = 0.25)) |>
    leaflet::addProviderTiles(leaflet::providers$Esri.WorldGrayCanvas) |>   # light gray, no API key (CARTO now asks for one)
    leaflet::fitBounds(min(d$lon), min(d$lat), max(d$lon), max(d$lat), options = list(padding = c(12, 12)))
  for (v in c("now", "a", "b")) {
    g <- M$views[[v]]
    x <- d |> filter(view == v, !gone) |> arrange(desc(n))     # small circles drawn last, on top
    z <- d |> filter(view == v, gone)
    if (nrow(z)) m <- m |> leaflet::addCircleMarkers(data = z, lng = ~lon, lat = ~lat, radius = map_radius(z$n0), group = g,
      stroke = TRUE, color = PAL$muted, weight = 1.5, opacity = 1, dashArray = "3 3", fill = TRUE, fillColor = "white", fillOpacity = 0.01,
      label = tip(z), labelOptions = leaflet::labelOptions(direction = "auto", textsize = "13px"))
    h <- filter(x, shift)    # halo: an ink ring just outside the circle, with a white gap, so it shows on dark fills too
    if (nrow(h)) m <- m |> leaflet::addCircleMarkers(data = h, lng = ~lon, lat = ~lat, radius = map_radius(h$n) + 3, group = g,
      stroke = TRUE, color = PAL$ink, weight = 2, opacity = 1, fill = FALSE, label = tip(h),
      labelOptions = leaflet::labelOptions(direction = "auto", textsize = "13px"))
    m <- m |> leaflet::addCircleMarkers(data = x, lng = ~lon, lat = ~lat, radius = map_radius(x$n), group = g,
      stroke = TRUE, color = "white", weight = 1.5, opacity = 1,
      fillColor = MAP_RAMP[x$bin], fillOpacity = 0.9,
      label = tip(x), labelOptions = leaflet::labelOptions(direction = "auto", textsize = "13px"))
  }
  m |> leaflet::addLayersControl(baseGroups = unname(M$views), position = "topright",
                                 options = leaflet::layersControlOptions(collapsed = FALSE)) |>
    # Open on Scenario A (hideGroup() on base groups hides all three, so pick the radio button instead). On narrow
    # screens, shrink every circle by the same factor (never below 65%), so the dense inner east side stays readable.
    htmlwidgets::onRender("function(el) {
      var map = this, k = Math.max(0.65, Math.min(1, el.clientWidth / 700));
      function scale() { map.eachLayer(function(l) { if (l.setRadius && !l._scaled) { l._scaled = true; l.setRadius(l.getRadius() * k); } }); }
      map.on('baselayerchange', scale);
      var r = el.querySelectorAll('.leaflet-control-layers-base input'); if (r[1]) r[1].click();
      scale();
      document.querySelectorAll('.map-key .mk-size circle').forEach(function(c) { c.setAttribute('r', c.getAttribute('r') * k); });   // key matches the map
    }")
}

# Key shown above the map (HTML, so it never covers schools on a phone).
map_key <- function() {
  M <- pc_lab()$map
  sw <- function(col) sprintf('<svg width="14" height="14" aria-hidden="true"><circle cx="7" cy="7" r="6" fill="%s"/></svg>', col)
  size <- paste(vapply(c(250, 500, 900), function(n) { r <- map_radius(n)
    sprintf('<span class="mk-item"><svg class="mk-size" width="%.0f" height="%.0f" aria-hidden="true"><circle cx="%.1f" cy="%.1f" r="%.1f" fill="none" stroke="%s" stroke-width="1.2"/></svg> %s</span>',
            2 * r + 4, 2 * r + 4, r + 2, r + 2, r, PAL$ink2, fmt_n(n)) }, character(1)), collapse = " ")
  htmltools::HTML(sprintf(paste0(
    '<div class="map-key"><div><b>%s</b></div><div>%s</div><div><b>%s</b> %s</div>',
    '<div><span class="mk-item mk-wrap"><svg width="18" height="18" aria-hidden="true"><circle cx="9" cy="9" r="8" fill="none" stroke="%s" stroke-width="1.6"/><circle cx="9" cy="9" r="5.5" fill="%s"/></svg> %s</span></div>',
    '<div><span class="mk-item mk-wrap"><svg width="18" height="18" aria-hidden="true"><circle cx="9" cy="9" r="7" fill="none" stroke="%s" stroke-width="1.5" stroke-dasharray="3 3"/></svg> %s</span></div></div>'),
    M$color, paste(sprintf('<span class="mk-item">%s %s</span>', vapply(MAP_RAMP, sw, character(1)), M$bins), collapse = " "),
    M$size, size, PAL$ink, MAP_RAMP[3], M$outline, PAL$muted, M$closed))
}
