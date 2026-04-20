# =============================================================================
# Phase 9 — Paper-ready outputs (Section 12 of project context)
# =============================================================================
# Converts the numeric artifacts from Phases 4-8 into polished tables and
# figures for the paper, each in both CSV (machine-readable) and LaTeX
# (paper-embeddable) form where appropriate.
#
# Produces:
#   Table 1  — descriptive stats (tbl1_descriptive_stats.{csv,tex})
#   Table 2  — regression coefficients with HC3 CIs (tbl2_regression_coefficients.{csv,tex})
#   Table 3  — robustness family-LMG comparison (tbl3_robustness.{csv,tex})
#   Table 4  — regular-season-only family-LMG (tbl4_regular_season.{csv,tex})
#   Fig 1    — model diagnostics (copy of fig_diagnostics.png)
#   Fig 2    — headline family-LMG (copy of fig_lmg_family.png)
#   Fig 3    — variable-level LMG (copy of fig_lmg_terms.png)
#   Fig 4    — followers vs log(P2+) scatter (copy of eda_scatter_followers.png)
#   Fig 5    — regular-season LMG (copy of fig_regular_season.png)
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readr); library(tibble); library(stringr)
  library(here); library(xtable)
})

out_tbl <- here("outputs", "tables")
out_fig <- here("outputs", "figures")

# -----------------------------------------------------------------------------
# Helper — write xtable as plain .tex (no document wrapper)
# -----------------------------------------------------------------------------
write_latex <- function(tbl, path, caption, label,
                        align = NULL, digits = NULL) {
  xt <- xtable(tbl, caption = caption, label = label,
               align = align, digits = digits)
  print(xt, file = path,
        include.rownames = FALSE,
        booktabs = TRUE,
        caption.placement = "top",
        sanitize.text.function = identity,
        sanitize.colnames.function = identity,
        NA.string = "--")
}

# -----------------------------------------------------------------------------
# Table 1 — Descriptive statistics
# -----------------------------------------------------------------------------
d <- readRDS(here("data", "processed", "model_data.rds"))

desc_vars <- c(
  p2_plus                    = "P2+ rating (000s)",
  p18_49                     = "P18-49 rating (000s)",
  starting5_followers_total  = "Starting-5 IG followers (both teams, sum)",
  team_handle_followers_home = "Home team-handle followers",
  team_handle_followers_away = "Away team-handle followers",
  market_hh_combined         = "Combined DMA TV households (home+away)",
  home_last5_win_pct         = "Home team last-5 win pct",
  away_last5_win_pct         = "Away team last-5 win pct",
  combined_season_win_pct    = "Combined season win pct"
)

fmt_num <- function(x, digits = 2) {
  ifelse(abs(x) >= 1e6, formatC(x, format = "e", digits = 2),
         formatC(x, format = "f", digits = digits, big.mark = ","))
}

tbl1 <- tibble(
  variable = names(desc_vars),
  label    = unname(desc_vars)
) |>
  rowwise() |>
  mutate(
    x = list(d[[variable]]),
    n      = sum(!is.na(unlist(x))),
    n_na   = sum(is.na(unlist(x))),
    mean   = mean(unlist(x), na.rm = TRUE),
    sd     = sd(unlist(x),   na.rm = TRUE),
    median = median(unlist(x), na.rm = TRUE),
    min    = min(unlist(x),  na.rm = TRUE),
    max    = max(unlist(x),  na.rm = TRUE)
  ) |>
  ungroup() |>
  select(-variable, -x) |>
  rename(Variable = label)

# Categorical summary rows
cat_summary <- function(col, label) {
  tb <- table(d[[col]], useNA = "ifany")
  paste0(label, ": ",
         paste(sprintf("%s=%d", names(tb), as.integer(tb)), collapse = "; "))
}
cat_rows <- tibble(
  Variable = c(cat_summary("network",        "Network"),
               cat_summary("time_slot",      "Tipoff slot"),
               cat_summary("playoff_stakes", "Playoff stakes")),
  n = NA_integer_, n_na = NA_integer_,
  mean = NA_real_, sd = NA_real_, median = NA_real_, min = NA_real_, max = NA_real_
)

tbl1_out <- bind_rows(
  tbl1 |> mutate(across(c(mean, sd, median, min, max), fmt_num)),
  cat_rows |> mutate(across(c(mean, sd, median, min, max), as.character))
) |>
  mutate(n    = ifelse(is.na(n),    "",    as.character(n)),
         n_na = ifelse(is.na(n_na), "",    as.character(n_na)))

write_csv(tbl1_out, file.path(out_tbl, "tbl1_descriptive_stats.csv"))
write_latex(tbl1_out,
            file.path(out_tbl, "tbl1_descriptive_stats.tex"),
            caption = "Descriptive statistics (n = 639 games, 2023/24--2025/26 nationally televised). Continuous variables: mean, SD, median, min, max. Categorical variables: frequency counts. Missingness (n\\_na) reflects pre-complete-case counts.",
            label = "tab:descriptive",
            align = c("l", "l", "r", "r", "r", "r", "r", "r", "r"))

cat("Table 1 written (", nrow(tbl1_out), "rows)\n")

# -----------------------------------------------------------------------------
# Table 2 — Regression coefficients with HC3 CIs
# -----------------------------------------------------------------------------
coefs <- read_csv(file.path(out_tbl, "tbl_regression_coefs.csv"),
                  show_col_types = FALSE) |>
  filter(se_type == "HC3_robust")

term_label <- c(
  "(Intercept)"                         = "Intercept",
  "log1p(starting5_followers_total)"    = "log1p(Starting-5 followers, total)",
  "log1p(team_handle_followers_home)"   = "log1p(Home team-handle followers)",
  "log1p(team_handle_followers_away)"   = "log1p(Away team-handle followers)",
  "log(market_hh_combined)"             = "log(Combined DMA households)",
  "home_last5_win_pct"                  = "Home last-5 win pct",
  "away_last5_win_pct"                  = "Away last-5 win pct",
  "on_fire_either"                      = "On-fire indicator (either team)",
  "combined_season_win_pct"             = "Combined season win pct",
  "playoff_stakesround1"                = "Playoff: Round 1 (vs regular)",
  "playoff_stakesround2"                = "Playoff: Round 2",
  "playoff_stakesconf_finals"           = "Playoff: Conference finals",
  "playoff_stakesfinals"                = "Playoff: Finals",
  "networkESPN"                         = "Network: ESPN (vs ABC)",
  "networkNBC"                          = "Network: NBC",
  "networkPRIME VIDEO"                  = "Network: Prime Video",
  "networkTNT"                          = "Network: TNT",
  "networkTNT+TRUTV"                    = "Network: TNT+TruTV",
  "time_slotprimetime"                  = "Tipoff: Primetime (vs early)",
  "time_slotlate"                       = "Tipoff: Late",
  "is_holiday"                          = "Holiday game",
  "is_weekend"                          = "Weekend game"
)

tbl2_out <- coefs |>
  mutate(Term   = ifelse(term %in% names(term_label), term_label[term], term),
         beta   = sprintf("%+.3f", estimate),
         se     = sprintf("%.3f", std.error),
         ci     = sprintf("(%+.3f, %+.3f)", conf.low, conf.high),
         pval   = ifelse(p.value < 0.001, "$<$0.001",
                         sprintf("%.3f", p.value))) |>
  select(Term, `$\\hat{\\beta}$` = beta, `HC3 SE` = se,
         `95\\% HC3 CI` = ci, `$p$` = pval)

write_csv(coefs |>
            mutate(term = ifelse(term %in% names(term_label), term_label[term], term)) |>
            select(term, estimate, std.error, conf.low, conf.high, p.value),
          file.path(out_tbl, "tbl2_regression_coefficients.csv"))

write_latex(tbl2_out,
            file.path(out_tbl, "tbl2_regression_coefficients.tex"),
            caption = "Primary regression coefficients with HC3 heteroscedasticity-consistent standard errors and 95\\% CIs. Dependent variable: $\\log(P2+)$. $n=573$, $R^2 = 0.866$. Reference levels: ABC (network), early (tipoff slot), regular (playoff stakes).",
            label = "tab:regression",
            align = c("l", "l", "r", "r", "r", "r"))

cat("Table 2 written (", nrow(tbl2_out), "rows, HC3 only)\n")

# -----------------------------------------------------------------------------
# Table 3 — Robustness comparison (family LMG across sensitivities)
# -----------------------------------------------------------------------------
rob <- read_csv(file.path(out_tbl, "tbl_robustness_family.csv"),
                show_col_types = FALSE)

fam_order <- c("Matchup", "Network", "Timing", "Star power",
               "Team form", "Market size", "post_new_deal")

tbl3_long <- rob |>
  mutate(
    cell = sprintf("%.1f\\%% (%.1f, %.1f)",
                   100 * lmg_share, 100 * ci_lo, 100 * ci_up)
  ) |>
  select(Family = family, sensitivity, cell)

tbl3_wide <- tbl3_long |>
  pivot_wider(names_from = sensitivity, values_from = cell) |>
  mutate(Family = factor(Family, levels = fam_order)) |>
  arrange(Family) |>
  mutate(Family = as.character(Family))

write_csv(tbl3_wide, file.path(out_tbl, "tbl3_robustness.csv"))

write_latex(tbl3_wide,
            file.path(out_tbl, "tbl3_robustness.tex"),
            caption = "Family-level LMG shares (\\% of model $R^2$) with 95\\% bootstrap CIs across robustness specifications. A: reference, $\\log(P2+)$, full sample ($n=573$, 1000 reps). B: $\\log(P18\\text{-}49)$ target, 500 reps. C: pre-2025/26 subsample ($n=452$), 1000 reps. D: drop top-10 Cook's D ($n=563$), 500 reps. E: add \\texttt{post\\_new\\_deal} main effect, 500 reps.",
            label = "tab:robustness",
            align = c("l", "l", rep("r", ncol(tbl3_wide) - 1)))

cat("Table 3 written (", nrow(tbl3_wide), "rows)\n")

# -----------------------------------------------------------------------------
# Table 4 — Regular-season-only family LMG (bonus analysis)
# -----------------------------------------------------------------------------
reg <- read_csv(file.path(out_tbl, "tbl_regular_season_family.csv"),
                show_col_types = FALSE)

fam_order_reg <- c("Matchup", "Network", "Timing", "Star power",
                   "Team form", "Market size", "Season timing")

tbl4_long <- reg |>
  mutate(
    cell = sprintf("%.1f\\%% (%.1f, %.1f)",
                   100 * lmg_share, 100 * ci_lo, 100 * ci_up)
  ) |>
  select(Family = family, sensitivity, cell)

tbl4_wide <- tbl4_long |>
  pivot_wider(names_from = sensitivity, values_from = cell) |>
  mutate(Family = factor(Family, levels = fam_order_reg)) |>
  arrange(Family) |>
  mutate(Family = as.character(Family))

write_csv(tbl4_wide, file.path(out_tbl, "tbl4_regular_season.csv"))

write_latex(tbl4_wide,
            file.path(out_tbl, "tbl4_regular_season.tex"),
            caption = "Family-level LMG shares (\\% of $R^2$) restricted to regular-season games ($n=422$). A: full-sample reference. F1: regular-season only, primary formula minus \\texttt{playoff\\_stakes} ($R^2=0.658$). F2: F1 plus \\texttt{weeks\\_until\\_regular\\_end} as a distinct ``Season timing'' family ($R^2=0.662$).",
            label = "tab:regular_season",
            align = c("l", "l", rep("r", ncol(tbl4_wide) - 1)))

cat("Table 4 written (", nrow(tbl4_wide), "rows)\n")

# -----------------------------------------------------------------------------
# Figures — copy to paper-ready filenames
# -----------------------------------------------------------------------------
copies <- tribble(
  ~from,                          ~to,
  "fig_diagnostics.png",          "fig1_diagnostics.png",
  "fig_lmg_family.png",           "fig2_family_lmg.png",
  "fig_lmg_terms.png",            "fig3_variable_lmg.png",
  "eda_scatter_followers.png",    "fig4_scatter_followers.png",
  "fig_regular_season.png",       "fig5_regular_season.png"
)

for (i in seq_len(nrow(copies))) {
  src <- file.path(out_fig, copies$from[i])
  dst <- file.path(out_fig, copies$to[i])
  if (file.exists(src)) {
    file.copy(src, dst, overwrite = TRUE)
    cat(sprintf("Copied %s -> %s\n", copies$from[i], copies$to[i]))
  } else {
    warning("missing source figure: ", copies$from[i])
  }
}

cat("\nAll paper outputs written to outputs/tables and outputs/figures.\n")
