# Race and ethnicity figures for Equity §3 (fig-race-groups, fig-race-split, fig-black-displaced,
# fig-race-schools). One function per figure; labels switch to Spanish when the page sets
# options(site.lang = "es") (SITE_ES, from R/site_data.R), so English and Spanish pages run the same code.
#
# Encoding is the same in every figure (validated PAL slots 1-3 plus marker shape as a second cue, since
# aqua is below 3:1 contrast): blue circle = immersion program moves, orange diamond = closures,
# aqua square = César Chávez neighborhood program, hollow gray ring = comparison / today.

RC <- list(
  en = list(
    race = c(latino = "Latino", black = "Black", asian = "Asian", white = "White",
             asian_white = "Multiracial: Asian and White", other_multi = "Multiracial: other",
             native_american = "Native American", pacific_islander = "Pacific Islander"),
    mov = "Students in immersion programs that move", clr = "Students at closing schools",
    hub = "César Chávez neighborhood program", k8 = "All PPS elementary and middle schools",
    share = "Share of students", of = "of", students = "students",
    imm = "Immersion program", nb = "Neighborhood program, same building",
    black_share = "Black students", latino_share = "Latino students",
    black_n = "Black students (number)",
    now = "No changes", after_lose = "Scenario A: school loses an immersion program",
    after_recv = "Scenario A: school receives an immersion program",
    ur = "Underserved racial groups (PPS projection)",
    closes = "closes", prog_fmt = "%s (%s)", grades_fmt = "%s (%s, grades 6-8)", hub_row = "César Chávez neighborhood program",
    cause = c("Immersion program moves" = "Immersion program moves",
              "School closures (non-immersion students)" = "School closures",
              "Neighborhood program moved out of an immersion hub" = "César Chávez neighborhood program moved out")
  ),
  es = list(
    race = c(latino = "Latinos", black = "Afrodescendientes", asian = "Asiáticos", white = "Blancos",
             asian_white = "Multirraciales: asiáticos y blancos", other_multi = "Multirraciales: otros",
             native_american = "Nativos americanos", pacific_islander = "De las islas del Pacífico"),
    mov = "Estudiantes de programas de inmersión que se trasladan", clr = "Estudiantes de escuelas que cierran",
    hub = "Programa del vecindario de César Chávez", k8 = "Todas las primarias e intermedias de PPS",
    share = "Porcentaje de estudiantes", of = "de", students = "estudiantes",
    imm = "Programa de inmersión", nb = "Programa del vecindario, mismo edificio",
    black_share = "Afrodescendientes", latino_share = "Latinos",
    black_n = "Estudiantes afrodescendientes",
    now = "Sin cambios", after_lose = "Escenario A: la escuela pierde un programa de inmersión",
    after_recv = "Escenario A: la escuela recibe un programa de inmersión",
    ur = "Grupos raciales desatendidos (proyección de PPS)",
    closes = "cierra", prog_fmt = "%s (%s)", grades_fmt = "%s (%s, 6.º a 8.º)", hub_row = "César Chávez: programa del vecindario",
    cause = c("Immersion program moves" = "Traslados de programas de inmersión",
              "School closures (non-immersion students)" = "Cierres de escuelas",
              "Neighborhood program moved out of an immersion hub" = "Salida del programa del vecindario de César Chávez")
  )
)
rc_lab <- function() if (exists("SITE_ES") && isTRUE(SITE_ES)) RC$es else RC$en
RC_COL <- c(mov = PAL$light[["blue"]], clr = PAL$light[["orange"]], hub = PAL$light[["aqua"]])
RC_SYM <- c(mov = "circle", clr = "diamond", hub = "square")
pct1 <- function(x) sprintf("%.1f%%", 100 * x)
wl <- function(x) wrap_label(x, 32)   # legend entries and axis titles: two lines on phones
lang_case <- function(x) if (exists("SITE_ES") && isTRUE(SITE_ES)) tolower(lang_name(x)) else x
lang_name <- function(x) if (exists("SITE_ES") && isTRUE(SITE_ES) && exists("tr_lang")) tr_lang(x) else x

# 1. Dot plot: race/ethnicity of each displaced group vs all PPS elementary and middle schools (Scenario A).
fig_race_groups <- function(rg) {
  L <- rc_lab()
  grp_key <- c("Immersion program moves" = "mov", "School closures (non-immersion students)" = "clr",
               "Neighborhood program moved out of an immersion hub" = "hub", "All PPS elementary and middle schools" = "k8")
  d <- rg |> filter(group %in% names(grp_key), scenario %in% c("a", "all")) |>
    mutate(k = grp_key[group]) |>
    select(k, students, all_of(paste0(names(L$race), "_pct")), all_of(paste0(names(L$race), "_n"))) |>
    tidyr::pivot_longer(-c(k, students), names_to = c("race", ".value"), names_pattern = "(.*)_(pct|n)$") |>
    mutate(race_lab = L$race[race], name = unlist(L[k]),
           tip = sprintf("<b>%s</b><br>%s: %s (%s %s %s %s)", race_lab, name, pct1(pct), fmt_n(round(n)), L$of, fmt_n(round(students)), L$students))
  lev <- wrap_label(rev(unname(L$race)), 22)
  d$y <- factor(wrap_label(d$race_lab, 22), lev)
  rng <- d |> group_by(y) |> summarise(lo = min(pct), hi = max(pct))
  p <- plot_ly() |>
    add_segments(data = rng, x = ~lo, xend = ~hi, y = ~y, yend = ~y, line = list(color = PAL$grid, width = 2), hoverinfo = "skip", showlegend = FALSE) |>
    add_markers(data = filter(d, k == "k8"), x = ~pct, y = ~y, name = wl(L$k8), text = ~tip, hoverinfo = "text",
                marker = list(color = "white", size = 10, line = list(color = PAL$muted, width = 2)))
  for (k in c("mov", "clr", "hub")) {
    p <- add_markers(p, data = filter(d, k == !!k), x = ~pct, y = ~y, name = wl(unlist(L[k])), text = ~tip, hoverinfo = "text",
                     marker = list(color = RC_COL[[k]], symbol = RC_SYM[[k]], size = 10, line = list(color = "white", width = 1.5)))
  }
  viz_layout(p, xtitle = wl(L$share)) |> layout(xaxis = list(tickformat = ".0%", rangemode = "tozero"))
}

# 2. Dumbbells: each moving program vs the neighborhood program in the same building, Black and Latino shares.
fig_race_split <- function(rp) {
  L <- rc_lab()
  d <- rp |> filter(!is.na(nb_black_pct)) |> arrange(nb_black_pct - black_pct) |>
    mutate(lab = sprintf("%s (%s%s)", from_school, lang_case(language), case_when(kind == "grades" ~ ", K-8", band == "6-8" ~ ", 6-8", TRUE ~ "")))
  d$y <- factor(wrap_label(d$lab, 22), unique(wrap_label(d$lab, 22)))
  panel <- function(a, b, title, legend) {
    tip_a <- sprintf("<b>%s</b><br>%s: %s", d$lab, L$imm, pct1(d[[a]]))
    tip_b <- sprintf("<b>%s</b><br>%s: %s", d$lab, L$nb, pct1(d[[b]]))
    plot_ly(d, y = ~y) |>
      add_segments(x = d[[a]], xend = d[[b]], yend = ~y, line = list(color = PAL$grid, width = 2), hoverinfo = "skip", showlegend = FALSE) |>
      add_markers(x = d[[b]], name = L$nb, text = tip_b, hoverinfo = "text", showlegend = legend, legendgroup = "nb",
                  marker = list(color = "white", size = 10, line = list(color = PAL$muted, width = 2))) |>
      add_markers(x = d[[a]], name = L$imm, text = tip_a, hoverinfo = "text", showlegend = legend, legendgroup = "imm",
                  marker = list(color = RC_COL[["mov"]], symbol = "circle", size = 10, line = list(color = "white", width = 1.5))) |>
      layout(xaxis = list(tickformat = ".0%", rangemode = "tozero"))
  }
  s <- subplot(panel("black_pct", "nb_black_pct", L$black_share, TRUE), panel("latino_pct", "nb_latino_pct", L$latino_share, FALSE),
               shareY = TRUE, titleX = FALSE, margin = 0.04)
  ax <- list(gridcolor = PAL$grid, zerolinecolor = PAL$grid, linecolor = PAL$grid, tickformat = ".0%", rangemode = "tozero",
             tickfont = list(color = PAL$ink2, size = 12), title = list(font = list(color = PAL$ink2, size = 13)))
  hdr <- function(x, txt) list(text = paste0("<b>", txt, "</b>"), x = x, xref = "paper", xanchor = "center", y = 1, yref = "paper", yanchor = "bottom",
                               showarrow = FALSE, font = list(color = PAL$ink2, size = 13))
  viz_layout(s) |> layout(xaxis = modifyList(ax, list(dtick = 0.2, tickangle = 0)), xaxis2 = modifyList(ax, list(dtick = 0.4, tickangle = 0)),
                          annotations = list(hdr(0.24, L$black_share), hdr(0.76, L$latino_share)),
                          legend = list(y = 1.08))
}

# 3. Bars: Black students who would have to change schools, by school or program and cause (Scenario A).
fig_black_displaced <- function(black) {
  L <- rc_lab()
  key <- c("Immersion program moves" = "mov", "School closures (non-immersion students)" = "clr", "Neighborhood program moved out of an immersion hub" = "hub")
  d <- black |> filter(scenario == "a") |> mutate(k = key[cause], n = round(black_n)) |> filter(n >= 1) |> arrange(n)
  d$lab <- with(d, case_when(
    kind == "closes" ~ sprintf("%s (%s)", school, L$closes),
    kind == "neighborhood program" ~ L$hub_row,
    kind == "grades 6-8" ~ sprintf(L$grades_fmt, school, lang_case(language)),
    TRUE ~ sprintf(L$prog_fmt, school, lang_case(language))))
  d$y <- factor(wrap_label(d$lab, 26), unique(wrap_label(d$lab, 26)))
  p <- plot_ly()
  for (k in c("clr", "mov", "hub")) {
    dk <- filter(d, k == !!k)
    p <- add_bars(p, data = dk, x = ~n, y = ~y, orientation = "h", name = wl(L$cause[[names(key)[key == k]]]),
                  marker = list(color = RC_COL[[k]], line = list(color = "white", width = 1)),
                  text = ~n, textposition = "outside", textfont = list(color = PAL$ink2, size = 11), cliponaxis = FALSE,
                  hovertext = ~sprintf("<b>%s</b><br>%s %s (%s %s %s %s)", lab, n, tolower(L$race[["black"]]), pct1(black_pct), L$of, fmt_n(round(students)), L$students),
                  hoverinfo = "text")
  }
  viz_layout(p, xtitle = wl(L$black_n)) |> layout(barmode = "overlay", bargap = 0.35, xaxis = list(rangemode = "tozero"))
}

# 4. Before/after rows (like fig-home): PPS's projected share from underserved racial groups, no changes vs Scenario A.
fig_race_schools <- function(rs) {
  L <- rc_lab()
  nm <- c("Dr. Martin Luther King Jr." = "MLK Jr.", "Cesar Chavez" = "César Chávez", "Boise-Eliot-Humboldt" = "Boise-Eliot/Humboldt")
  d <- rs |> filter(scenario == "a", !closes) |>
    mutate(school = ifelse(school %in% names(nm), nm[school], school), k = if_else(role == "Loses an immersion program", "mov", "hub")) |>
    arrange(desc(k), change)
  d$y <- factor(d$school, rev(d$school))
  p <- plot_ly(d, y = ~y) |>
    add_segments(x = ~now, xend = ~after, yend = ~y, line = list(color = PAL$grid, width = 2), hoverinfo = "skip", showlegend = FALSE) |>
    add_markers(x = ~now, name = wl(L$now), text = ~sprintf("<b>%s</b><br>%s: %s", school, L$now, pct1(now)), hoverinfo = "text",
                marker = list(color = "white", size = 10, line = list(color = PAL$muted, width = 2)))
  for (k in c("mov", "hub")) {
    p <- add_markers(p, data = filter(d, k == !!k), x = ~after, name = wl(if (k == "mov") L$after_lose else L$after_recv),
                     text = ~sprintf("<b>%s</b><br>%s %s → %s (%+.0f)", school, L$now, pct1(now), pct1(after), 100 * change), hoverinfo = "text",
                     marker = list(color = RC_COL[[k]], symbol = RC_SYM[[k]], size = 10, line = list(color = "white", width = 1.5)))
  }
  viz_layout(p, xtitle = wl(L$ur)) |> layout(xaxis = list(tickformat = ".0%", rangemode = "tozero"))
}
