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
      xaxis = modifyList(axis, list(title = list(text = xtitle), automargin = TRUE)),
      yaxis = modifyList(axis, list(title = list(text = ytitle), automargin = TRUE)),
      showlegend = legend, legend = list(orientation = "h", x = 0, xanchor = "left", y = 1.02, yanchor = "bottom", font = list(color = PAL$ink2)),
      hoverlabel = list(bgcolor = "white", bordercolor = PAL$grid, font = list(color = PAL$ink)),
      margin = list(l = 10, r = 10, t = 10, b = 10), ...
    ) |>
    config(displayModeBar = FALSE)
}

# Break a long category label onto two lines (at " (" or the last space before `width` characters), so
# horizontal charts keep room for the data on a phone.
wrap_label <- function(x, width = 24) {
  vapply(x, function(s) {
    if (nchar(s) <= width) return(s)
    if (grepl(" \\(", s)) return(sub(" \\(", "<br>(", s))
    sp <- gregexpr(" ", s)[[1]]; sp <- sp[sp <= width]
    if (!length(sp) || sp[1] < 0) return(s)
    paste0(substr(s, 1, max(sp) - 1), "<br>", substr(s, max(sp) + 1, nchar(s)))
  }, character(1), USE.NAMES = FALSE)
}
