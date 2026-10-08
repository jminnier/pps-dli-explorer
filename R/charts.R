# Chart helpers (plotly) following the dataviz reference: thin marks, recessive grid, hover on every
# mark, legend for >= 2 series, text in ink colours rather than series colours.
suppressPackageStartupMessages(library(plotly))

viz_layout <- function(p, xtitle = NULL, ytitle = NULL, legend = TRUE, ...) {
  axis <- list(gridcolor = PAL$grid, zerolinecolor = PAL$grid, linecolor = PAL$grid,
               tickfont = list(color = PAL$ink2, size = 12), title = list(font = list(color = PAL$ink2, size = 13)))
  p |>
    layout(
      font = list(family = "system-ui, -apple-system, Segoe UI, sans-serif", color = PAL$ink),
      paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
      xaxis = modifyList(axis, list(title = list(text = xtitle))),
      yaxis = modifyList(axis, list(title = list(text = ytitle))),
      showlegend = legend, legend = list(orientation = "h", x = 0, y = 1.12, font = list(color = PAL$ink2)),
      hoverlabel = list(bgcolor = "white", bordercolor = PAL$grid, font = list(color = PAL$ink)),
      margin = list(l = 10, r = 10, t = 40, b = 60), ...
    ) |>
    config(displayModeBar = FALSE)
}
