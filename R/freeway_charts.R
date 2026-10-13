# Freeway section of the Equity page (#sec-freeway), built from data/freeway_*.csv (data-raw/freeway_equity.R).
# Needs R/plan_charts.R (pc_lab(), short_school(), ROLES labels). Labels switch to Spanish with options(site.lang = "es").

FW <- list(
  en = list(axis = "Meters, log scale", from = "Now at", to = "Would go to",
            zone = "Within 150 m:<br>most traffic<br>pollution (EPA)", m = "m", ab = "A and B", a = "A only",
            students = "students today", scen = "Scenario", part = c(whole = "whole school", `6-8` = "grades 6-8", Spanish = "Spanish immersion",
            Mandarin = "Mandarin immersion", neighborhood = "neighborhood program")),
  es = list(axis = "Metros, escala log.", from = "Ahora en", to = "Iría a",
            zone = "A menos de 150 m:<br>más contaminación<br>del tráfico (EPA)", m = "m", ab = "A y B", a = "Solo A",
            students = "estudiantes hoy", scen = "Escenario", part = c(whole = "toda la escuela", `6-8` = "grados 6.º a 8.º", Spanish = "inmersión en español",
            Mandarin = "inmersión en mandarín", neighborhood = "programa del vecindario"))
)
fw_lab <- function() if (exists("SITE_ES") && isTRUE(SITE_ES)) FW$es else FW$en

# Moves that start or end within 600 m of a freeway: a segment from the current school to the new one.
fw_moves <- function(fl) {
  fl |> filter(!is.na(to_m), from_m <= 600 | to_m <= 600) |>
    group_by(from_school, part, to_school, students, from_m, to_m) |>
    summarise(scen = paste(sort(unique(scenario)), collapse = ""), .groups = "drop") |>
    arrange(desc(to_m))
}
fig_freeway_moves <- function(fl) {
  L <- fw_lab()
  d <- fw_moves(fl) |>
    mutate(what = coalesce(unname(L$part[part]), part),
           lab = sprintf("%s → %s", short_school(from_school), short_school(to_school)),
           lab = factor(lab, unique(lab)),
           closer = to_m < from_m,
           tip = sprintf("<b>%s → %s</b><br>%s, %s %s<br>%s: %s<br>%s m → %s m", short_school(from_school), short_school(to_school),
                         what, fmt_n(students), L$students, L$scen, unlist(L[scen]), fmt_n(from_m), fmt_n(to_m)))
  p <- plot_ly(d, y = ~lab) |>
    add_segments(x = ~from_m, xend = ~to_m, yend = ~lab, line = list(color = PAL$grid, width = 3), hoverinfo = "skip", showlegend = FALSE) |>
    add_markers(x = ~from_m, name = L$from, marker = list(color = "white", size = 10, line = list(color = PAL$ink2, width = 2)),
                text = ~tip, hoverinfo = "text") |>
    add_markers(x = ~to_m, name = L$to, marker = list(color = PAL$light[["orange"]], size = 11, symbol = "diamond", line = list(color = "white", width = 1)),
                text = ~tip, hoverinfo = "text")
  viz_layout(p, xtitle = L$axis) |>
    layout(xaxis = list(type = "log", range = log10(c(7, 6000)), tickvals = c(10, 100, 1000), ticktext = c("10", "100", "1,000"), tickangle = 0),
           shapes = list(list(type = "rect", xref = "x", yref = "paper", x0 = 7, x1 = 150, y0 = 0, y1 = 1,
                              fillcolor = "rgba(235,104,52,0.08)", line = list(width = 0), layer = "below")))
}
