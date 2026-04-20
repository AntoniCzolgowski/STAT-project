# =============================================================================
# Phase 4 — Primary model fit + Phase 6 diagnostics (§8, §10)
# =============================================================================
# Fits the primary log-linear OLS specified in §8.1 and runs the diagnostic
# battery from §10. Outputs feed the combined 05_model_fitting.md writeup.
#
# Inputs:  data/processed/model_data.rds
# Outputs: data/processed/primary_model.rds
#          data/interim/phase4_model_summary.rds
#          outputs/tables/tbl_regression_coefs.csv
#          outputs/figures/fig_diagnostics.png
# =============================================================================

set.seed(4010)

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readr); library(stringr)
  library(ggplot2); library(patchwork); library(here)
  library(broom); library(car); library(lmtest); library(sandwich)
})

theme_set(theme_minimal(base_size = 10))

d <- readRDS(here("data", "processed", "model_data.rds"))
cat("input rows:", nrow(d), "\n")

# -----------------------------------------------------------------------------
# 1. Prepare modeling dataframe — complete cases for the primary spec.
# -----------------------------------------------------------------------------
required <- c(
  "p2_plus",
  "starting5_followers_total",
  "team_handle_followers_home", "team_handle_followers_away",
  "market_hh_combined",
  "home_last5_win_pct", "away_last5_win_pct", "on_fire_either",
  "combined_season_win_pct", "playoff_stakes", "network",
  "time_slot", "is_holiday", "is_weekend"
)

df_model <- d |>
  select(game_id, game_date, season, season_type, home_team, away_team,
         all_of(required), p18_49) |>
  drop_na(all_of(required))

cat(sprintf("complete-case n for primary model: %d (%.1f%% of 639)\n",
            nrow(df_model), 100 * nrow(df_model) / 639))

# -----------------------------------------------------------------------------
# 2. Fit primary model (§8.1)
# -----------------------------------------------------------------------------
primary_model <- lm(
  log(p2_plus) ~
    log1p(starting5_followers_total) +
    log1p(team_handle_followers_home) +
    log1p(team_handle_followers_away) +
    log(market_hh_combined) +
    home_last5_win_pct +
    away_last5_win_pct +
    on_fire_either +
    combined_season_win_pct +
    playoff_stakes +
    network +
    time_slot +
    is_holiday +
    is_weekend,
  data = df_model
)

sm <- summary(primary_model)
cat(sprintf("\nR^2 = %.4f | adj R^2 = %.4f | F = %.2f on (%d, %d) df | p = %g\n",
            sm$r.squared, sm$adj.r.squared,
            sm$fstatistic[1], sm$fstatistic[2], sm$fstatistic[3],
            pf(sm$fstatistic[1], sm$fstatistic[2], sm$fstatistic[3],
               lower.tail = FALSE)))

# -----------------------------------------------------------------------------
# 3. Coefficient table with 95% CIs (classical + HC3 robust for comparison)
# -----------------------------------------------------------------------------
tidy_classical <- broom::tidy(primary_model, conf.int = TRUE, conf.level = 0.95) |>
  mutate(se_type = "classical")

vcov_hc3 <- sandwich::vcovHC(primary_model, type = "HC3")
tidy_robust <- broom::tidy(
  lmtest::coeftest(primary_model, vcov. = vcov_hc3),
  conf.int = TRUE, conf.level = 0.95
) |>
  mutate(se_type = "HC3_robust")

coef_tbl <- bind_rows(tidy_classical, tidy_robust) |>
  select(term, estimate, std.error, statistic, p.value,
         conf.low, conf.high, se_type)

write_csv(coef_tbl, here("outputs", "tables", "tbl_regression_coefs.csv"))

cat("\n== Coefficient table (classical SEs) ==\n")
print(tidy_classical |>
        mutate(across(where(is.numeric), \(x) signif(x, 3))),
      n = Inf)

# -----------------------------------------------------------------------------
# 4. Diagnostics (§10)
# -----------------------------------------------------------------------------
cat("\n== Diagnostics ==\n")

# 4a. Breusch-Pagan (homoscedasticity)
bp <- lmtest::bptest(primary_model)
cat(sprintf("Breusch-Pagan: BP = %.2f, df = %d, p = %.4g\n",
            bp$statistic, bp$parameter, bp$p.value))

# 4b. VIF (multicollinearity). `car::vif()` returns GVIF for factors; use
#     the GVIF^(1/(2*df)) column as the comparable metric (§10 threshold: < 2.5 ideal, < 5 acceptable).
vifs <- car::vif(primary_model)
if (is.matrix(vifs)) {
  vif_tbl <- tibble(term   = rownames(vifs),
                    gvif   = vifs[, "GVIF"],
                    df     = vifs[, "Df"],
                    gvif_adj = vifs[, "GVIF^(1/(2*Df))"])
} else {
  vif_tbl <- tibble(term = names(vifs), gvif = vifs,
                    df = 1, gvif_adj = sqrt(vifs))
}
vif_tbl <- vif_tbl |> arrange(desc(gvif_adj))
cat("VIFs (GVIF^(1/(2df)) column is the comparable metric):\n")
print(vif_tbl, n = Inf)

max_vif_adj <- max(vif_tbl$gvif_adj)
cat(sprintf("max GVIF^(1/(2df)) = %.2f (ideal < 2.5, acceptable < 5)\n",
            max_vif_adj))

# 4c. Cook's D — flag points with D > 4/n
n <- nrow(df_model)
cooks <- cooks.distance(primary_model)
cook_threshold <- 4 / n
n_influential <- sum(cooks > cook_threshold, na.rm = TRUE)
cat(sprintf("Cook's D > 4/n = %.4f: %d points (of %d)\n",
            cook_threshold, n_influential, n))

top_influential <- tibble(row = seq_along(cooks), cooks = cooks) |>
  arrange(desc(cooks)) |>
  slice_head(n = 10) |>
  mutate(game_id = df_model$game_id[row],
         home    = df_model$home_team[row],
         away    = df_model$away_team[row],
         log_p2  = log(df_model$p2_plus[row]))

cat("\nTop 10 Cook's D points:\n")
print(top_influential)

# 4d. Refit without influential points; report coefficient deltas
df_drop <- df_model[cooks <= cook_threshold & !is.na(cooks), ]
model_drop <- update(primary_model, data = df_drop)
cat(sprintf("\nRefit dropping %d influential points | new n = %d | ",
            n - nrow(df_drop), nrow(df_drop)))
cat(sprintf("R^2 = %.4f (full: %.4f)\n",
            summary(model_drop)$r.squared, sm$r.squared))

coef_delta <- tibble(
  term = names(coef(primary_model)),
  full = coef(primary_model),
  drop = coef(model_drop)[names(coef(primary_model))]
) |>
  mutate(abs_delta = abs(full - drop),
         rel_delta = abs_delta / pmax(abs(full), 1e-8)) |>
  arrange(desc(abs_delta))

cat("Top 5 coefficient changes (full vs. drop-influential):\n")
print(coef_delta |> slice_head(n = 5) |>
        mutate(across(where(is.numeric), \(x) signif(x, 3))))

# -----------------------------------------------------------------------------
# 5. Diagnostic panel figure
# -----------------------------------------------------------------------------
aug <- broom::augment(primary_model)

p_resid <- ggplot(aug, aes(.fitted, .resid)) +
  geom_point(alpha = 0.4, size = 0.8) +
  geom_hline(yintercept = 0, linetype = 2) +
  geom_smooth(se = FALSE, color = "firebrick", linewidth = 0.6) +
  labs(title = "Residuals vs fitted", x = "fitted log(P2+)", y = "residual")

p_qq <- ggplot(aug, aes(sample = .std.resid)) +
  stat_qq(alpha = 0.5, size = 0.8) + stat_qq_line(color = "firebrick") +
  labs(title = "Normal Q-Q", x = "theoretical", y = "std. residual")

p_scale <- ggplot(aug, aes(.fitted, sqrt(abs(.std.resid)))) +
  geom_point(alpha = 0.4, size = 0.8) +
  geom_smooth(se = FALSE, color = "firebrick", linewidth = 0.6) +
  labs(title = "Scale-location",
       x = "fitted log(P2+)", y = expression(sqrt("|std. residual|")))

p_cook <- ggplot(aug, aes(seq_len(nrow(aug)), .cooksd)) +
  geom_col(width = 0.6, fill = "steelblue") +
  geom_hline(yintercept = cook_threshold, linetype = 2, color = "firebrick") +
  labs(title = sprintf("Cook's D (threshold 4/n = %.3f)", cook_threshold),
       x = "observation index", y = "Cook's D")

diag_panel <- (p_resid | p_qq) / (p_scale | p_cook) +
  plot_annotation(title = "Primary model diagnostics")
ggsave(here("outputs", "figures", "fig_diagnostics.png"),
       diag_panel, width = 10, height = 7.5, dpi = 150)

# -----------------------------------------------------------------------------
# 6. Save model + summary
# -----------------------------------------------------------------------------
saveRDS(primary_model,
        here("data", "processed", "primary_model.rds"))

model_summary <- list(
  n                 = nrow(df_model),
  r_squared         = sm$r.squared,
  adj_r_squared     = sm$adj.r.squared,
  f_stat            = sm$fstatistic,
  tidy_classical    = tidy_classical,
  tidy_robust       = tidy_robust,
  bp_test           = bp,
  vif_table         = vif_tbl,
  max_vif_adj       = max_vif_adj,
  cook_threshold    = cook_threshold,
  n_influential     = n_influential,
  top_influential   = top_influential,
  coef_delta_drop   = coef_delta,
  r2_after_drop     = summary(model_drop)$r.squared
)
saveRDS(model_summary,
        here("data", "interim", "phase4_model_summary.rds"))

cat("\nWrote:\n")
cat("  data/processed/primary_model.rds\n")
cat("  data/interim/phase4_model_summary.rds\n")
cat("  outputs/tables/tbl_regression_coefs.csv\n")
cat("  outputs/figures/fig_diagnostics.png\n")
