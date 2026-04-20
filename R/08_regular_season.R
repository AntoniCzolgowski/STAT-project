# =============================================================================
# Phase 8 — Regular-season-only decomposition + season-timing feature
# =============================================================================
# Re-runs the family-level LMG on regular-season games only, to answer the
# domain question: within the regular season (where ratings are flatter),
# what still drives variation? Adds `weeks_until_regular_end` as its own
# "Season timing" family in F2.
#
# A  (reference) : primary spec, full sample (n=573)        -- from Phase 5
# F1             : primary spec MINUS playoff_stakes, regular-season only
# F2             : F1 + weeks_until_regular_end (Season timing family)
#
# Inputs:  data/processed/primary_model.rds
#          data/processed/model_data.rds
#          data/interim/phase5_lmg_results.rds  (for A)
# Outputs: data/interim/phase8_regular_season.rds
#          outputs/tables/tbl_regular_season_family.csv
#          outputs/figures/fig_regular_season.png
# =============================================================================

set.seed(4010)

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readr); library(tibble); library(stringr)
  library(ggplot2); library(here); library(relaimpo); library(boot)
})

theme_set(theme_minimal(base_size = 10))

# -----------------------------------------------------------------------------
# 1. Load primary model + regular-season frame
# -----------------------------------------------------------------------------
m_primary <- readRDS(here("data", "processed", "primary_model.rds"))
d         <- readRDS(here("data", "processed", "model_data.rds"))
p5        <- readRDS(here("data", "interim", "phase5_lmg_results.rds"))

required <- c(
  "p2_plus", "starting5_followers_total",
  "team_handle_followers_home", "team_handle_followers_away",
  "market_hh_combined",
  "home_last5_win_pct", "away_last5_win_pct", "on_fire_either",
  "combined_season_win_pct", "playoff_stakes", "network",
  "time_slot", "is_holiday", "is_weekend",
  "game_date", "season"
)

# Engineer weeks_until_regular_end BEFORE drop_na, using full regular-season
# dates to get an honest per-season anchor (so `max(game_date)` reflects the
# true last regular-season game, not just complete-case rows).
season_end <- d |>
  filter(playoff_stakes == "regular") |>
  group_by(season) |>
  summarise(reg_end = max(game_date), .groups = "drop")

cat("Regular-season end anchors:\n")
print(season_end)

d <- d |>
  left_join(season_end, by = "season") |>
  mutate(weeks_until_regular_end = as.numeric(reg_end - game_date) / 7)

d_reg <- d |>
  filter(playoff_stakes == "regular") |>
  drop_na(all_of(c(required, "weeks_until_regular_end"))) |>
  mutate(across(where(is.factor), droplevels))

cat(sprintf("\nRegular-season complete-case n = %d\n", nrow(d_reg)))
stopifnot(all(as.character(d_reg$playoff_stakes) == "regular"))

cat("\nweeks_until_regular_end range by season:\n")
print(d_reg |> group_by(season) |>
        summarise(min = min(weeks_until_regular_end),
                  max = max(weeks_until_regular_end),
                  n = n(), .groups = "drop"))

# -----------------------------------------------------------------------------
# 2. Build F1 and F2 formulas (drop playoff_stakes; optionally add timing)
# -----------------------------------------------------------------------------
primary_rhs <- paste(deparse(formula(m_primary)[[3]]), collapse = " ")
# Strip " + playoff_stakes" (either order); primary_rhs is a single string.
f1_rhs <- gsub("\\s*\\+\\s*playoff_stakes", "", primary_rhs)
cat("\nF1 RHS:\n"); cat(f1_rhs, "\n")

form_F1 <- as.formula(paste("log(p2_plus) ~", f1_rhs))
form_F2 <- as.formula(paste("log(p2_plus) ~", f1_rhs, "+ weeks_until_regular_end"))

m_F1 <- lm(form_F1, data = d_reg)
m_F2 <- lm(form_F2, data = d_reg)

stopifnot(nrow(d_reg) == nobs(m_F1), nrow(d_reg) == nobs(m_F2))
cat(sprintf("\nR^2:  F1 = %.4f   F2 = %.4f   (A reference = %.4f)\n",
            summary(m_F1)$r.squared, summary(m_F2)$r.squared, p5$r2_full))

# -----------------------------------------------------------------------------
# 3. Family groupings
# -----------------------------------------------------------------------------
# F1: Matchup reduces to a single variable (combined_season_win_pct).
families_F1 <- list(
  `Star power`  = c("log1p(starting5_followers_total)",
                    "log1p(team_handle_followers_home)",
                    "log1p(team_handle_followers_away)"),
  `Market size` = "log(market_hh_combined)",
  `Team form`   = c("home_last5_win_pct", "away_last5_win_pct",
                    "on_fire_either"),
  `Matchup`     = "combined_season_win_pct",
  `Network`     = "network",
  `Timing`      = c("time_slot", "is_holiday", "is_weekend")
)
families_F2 <- c(families_F1,
                 list(`Season timing` = "weeks_until_regular_end"))

# relaimpo silently drops groupnames for single-variable groups
family_label_fix <- c(
  "log(market_hh_combined)"  = "Market size",
  "network"                  = "Network",
  "combined_season_win_pct"  = "Matchup",
  "weeks_until_regular_end"  = "Season timing"
)

run_family_lmg <- function(m, label, groups, nboot = 500) {
  cat(sprintf("\n--- %s (n=%d, boot=%d) ---\n", label, nobs(m), nboot))
  ri <- calc.relimp(m, type = "lmg", groups = groups,
                    groupnames = names(groups), rela = FALSE)
  set.seed(4010)
  bo <- boot.relimp(m, b = nboot, type = "lmg", groups = groups,
                    groupnames = names(groups), rela = FALSE,
                    fixed = FALSE, diff = FALSE)
  ev <- booteval.relimp(bo, level = 0.95)
  list(point = ri, boot = bo, eval = ev, label = label, n = nobs(m),
       r_squared = summary(m)$r.squared)
}

pull_family <- function(lmg, sens_label) {
  nms <- names(lmg$point@lmg)
  nms <- ifelse(nms %in% names(family_label_fix),
                family_label_fix[nms], nms)
  tibble(family      = nms,
         lmg_share   = as.numeric(lmg$point@lmg),
         ci_lo       = as.numeric(lmg$eval@lmg.lower),
         ci_up       = as.numeric(lmg$eval@lmg.upper),
         sensitivity = sens_label,
         n           = lmg$n,
         r_squared   = lmg$r_squared)
}

pull_from_p5 <- function(lmg, sens_label) {
  nms <- names(lmg$point@lmg)
  nms <- ifelse(nms %in% names(family_label_fix),
                family_label_fix[nms], nms)
  tibble(family      = nms,
         lmg_share   = as.numeric(lmg$point@lmg),
         ci_lo       = as.numeric(lmg$eval@lmg.lower),
         ci_up       = as.numeric(lmg$eval@lmg.upper),
         sensitivity = sens_label,
         n           = lmg$point@nobs,
         r_squared   = lmg$point@R2)
}

# -----------------------------------------------------------------------------
# 4. Fit LMGs
# -----------------------------------------------------------------------------
lmg_F1 <- run_family_lmg(m_F1, "F1: regular only",            families_F1, 500)
lmg_F2 <- run_family_lmg(m_F2, "F2: regular + season timing", families_F2, 500)

tbl_A  <- pull_from_p5(p5$lmg_full_family, "A: reference (full sample)")
tbl_F1 <- pull_family(lmg_F1, "F1: regular only")
tbl_F2 <- pull_family(lmg_F2, "F2: regular + season timing")

# R^2 partition sanity check
stopifnot(abs(sum(tbl_F1$lmg_share) - summary(m_F1)$r.squared) < 1e-6)
stopifnot(abs(sum(tbl_F2$lmg_share) - summary(m_F2)$r.squared) < 1e-6)

family_comp <- bind_rows(tbl_A, tbl_F1, tbl_F2) |>
  mutate(sensitivity = factor(sensitivity, levels = c(
    "A: reference (full sample)",
    "F1: regular only",
    "F2: regular + season timing"
  )))

cat("\n== Family-level LMG: A vs F1 vs F2 ==\n")
print(family_comp |>
        mutate(across(c(lmg_share, ci_lo, ci_up, r_squared),
                      \(x) round(x, 4))) |>
        arrange(sensitivity, desc(lmg_share)), n = Inf)

# Print the season-timing coefficient for the writeup
st_row <- summary(m_F2)$coefficients["weeks_until_regular_end", ]
st_ci  <- confint(m_F2)["weeks_until_regular_end", ]
cat(sprintf("\nweeks_until_regular_end: beta = %.4f, SE = %.4f, 95%% CI = (%.4f, %.4f)\n",
            st_row["Estimate"], st_row["Std. Error"], st_ci[1], st_ci[2]))

write_csv(family_comp, here("outputs", "tables", "tbl_regular_season_family.csv"))

# -----------------------------------------------------------------------------
# 5. Figure — dodged family LMG across A / F1 / F2
# -----------------------------------------------------------------------------
family_order <- family_comp |>
  filter(sensitivity == "A: reference (full sample)") |>
  arrange(lmg_share) |> pull(family)
# Season timing only appears in F2; append at top so it has a slot
family_order <- c(setdiff(family_order, "Season timing"),
                  "Season timing")
family_order <- unique(c(family_order,
                         setdiff(unique(family_comp$family), family_order)))

fig_reg <- family_comp |>
  mutate(family = factor(family, levels = family_order)) |>
  ggplot(aes(x = lmg_share, y = family, fill = sensitivity)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.72,
           color = "white", linewidth = 0.15) +
  geom_errorbarh(aes(xmin = ci_lo, xmax = ci_up),
                 position = position_dodge(width = 0.8),
                 height = 0.25, color = "black", linewidth = 0.35) +
  scale_fill_brewer(palette = "Set1", name = "Specification") +
  scale_x_continuous(labels = scales::percent_format(accuracy = 1),
                     expand = expansion(mult = c(0, 0.05))) +
  labs(title    = "Family-level LMG: full sample vs regular-season only",
       subtitle = sprintf("A: full (n=573, R^2=%.3f)  |  F1: regular (n=%d, R^2=%.3f)  |  F2: regular + season timing (R^2=%.3f)",
                          p5$r2_full, nobs(m_F1),
                          summary(m_F1)$r.squared, summary(m_F2)$r.squared),
       x = expression("share of model " * R^2), y = NULL) +
  theme(legend.position = "bottom",
        legend.direction = "vertical",
        plot.title.position = "plot")

ggsave(here("outputs", "figures", "fig_regular_season.png"),
       fig_reg, width = 9, height = 6.5, dpi = 150)

# -----------------------------------------------------------------------------
# 6. Save bundle
# -----------------------------------------------------------------------------
saveRDS(list(
  lmg_F1 = lmg_F1, lmg_F2 = lmg_F2,
  family_comp = family_comp,
  r_squared = c(A = p5$r2_full,
                F1 = summary(m_F1)$r.squared,
                F2 = summary(m_F2)$r.squared),
  n = c(A = p5$n_full, F1 = nobs(m_F1), F2 = nobs(m_F2)),
  season_timing_beta = coef(m_F2)["weeks_until_regular_end"],
  season_timing_ci   = confint(m_F2)["weeks_until_regular_end", ],
  season_end_anchors = season_end
), here("data", "interim", "phase8_regular_season.rds"))

cat("\nWrote:\n")
cat("  outputs/tables/tbl_regular_season_family.csv\n")
cat("  outputs/figures/fig_regular_season.png\n")
cat("  data/interim/phase8_regular_season.rds\n")
