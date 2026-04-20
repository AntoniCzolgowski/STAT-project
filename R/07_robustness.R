# =============================================================================
# Phase 7 — Robustness / sensitivity analysis (§7, §11)
# =============================================================================
# Re-runs the primary spec under four sensitivities and compares family-level
# LMG against the Phase 5 reference. Each alternative is computed with a
# 500-rep bootstrap (vs Phase 5's 1000 for the headline).
#
# A. Reference  : log(P2+), full sample (n=573)                 -- from Phase 5
# B. P18-49     : log(P18_49), full sample                       -- NEW
# C. Pre-2025/26: log(P2+), exclude 2025/26 (n=452)              -- from Phase 5
# D. No-influence: log(P2+), drop Cook's D > 4/n rows (n≈537)    -- NEW
# E. +post_new_deal : log(P2+), full sample, adds post_new_deal  -- NEW
#
# Inputs:  data/processed/primary_model.rds
#          data/processed/model_data.rds
#          data/interim/phase5_lmg_results.rds  (for A, C)
# Outputs: data/interim/phase7_robustness.rds
#          outputs/tables/tbl_robustness_family.csv
#          outputs/figures/fig_robustness.png
# =============================================================================

set.seed(4010)

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readr); library(tibble); library(stringr)
  library(ggplot2); library(here); library(relaimpo); library(boot)
})

theme_set(theme_minimal(base_size = 10))

# -----------------------------------------------------------------------------
# 1. Load primary model + rebuild complete-case frame
# -----------------------------------------------------------------------------
m_primary <- readRDS(here("data", "processed", "primary_model.rds"))
d <- readRDS(here("data", "processed", "model_data.rds"))

required <- c(
  "p2_plus", "starting5_followers_total",
  "team_handle_followers_home", "team_handle_followers_away",
  "market_hh_combined",
  "home_last5_win_pct", "away_last5_win_pct", "on_fire_either",
  "combined_season_win_pct", "playoff_stakes", "network",
  "time_slot", "is_holiday", "is_weekend"
)
d_full <- d |> drop_na(all_of(required))
stopifnot(nrow(d_full) == nobs(m_primary))

# Pre-existing results from Phase 5
p5 <- readRDS(here("data", "interim", "phase5_lmg_results.rds"))

# -----------------------------------------------------------------------------
# 2. Shared spec: formula + family grouping + LMG helpers
# -----------------------------------------------------------------------------
primary_rhs <- paste(deparse(formula(m_primary)[[3]]), collapse = " ")

families <- list(
  `Star power`  = c("log1p(starting5_followers_total)",
                    "log1p(team_handle_followers_home)",
                    "log1p(team_handle_followers_away)"),
  `Market size` = "log(market_hh_combined)",
  `Team form`   = c("home_last5_win_pct", "away_last5_win_pct",
                    "on_fire_either"),
  `Matchup`     = c("combined_season_win_pct", "playoff_stakes"),
  `Network`     = "network",
  `Timing`      = c("time_slot", "is_holiday", "is_weekend")
)

# relaimpo silently drops groupnames for single-variable groups
family_label_fix <- c(
  "log(market_hh_combined)" = "Market size",
  "network"                 = "Network",
  "post_new_deal"           = "post_new_deal"  # for sensitivity E
)

run_family_lmg <- function(m, label, extra_groups = NULL, nboot = 500) {
  grp <- if (is.null(extra_groups)) families else c(families, extra_groups)
  cat(sprintf("\n--- %s (n=%d, boot=%d) ---\n", label, nobs(m), nboot))
  ri <- calc.relimp(m, type = "lmg", groups = grp,
                    groupnames = names(grp), rela = FALSE)
  set.seed(4010)
  bo <- boot.relimp(m, b = nboot, type = "lmg", groups = grp,
                    groupnames = names(grp), rela = FALSE,
                    fixed = FALSE, diff = FALSE)
  ev <- booteval.relimp(bo, level = 0.95)
  list(point = ri, eval = ev, label = label, n = nobs(m),
       r_squared = summary(m)$r.squared)
}

pull_family <- function(lmg) {
  nms <- names(lmg$point@lmg)
  nms <- ifelse(nms %in% names(family_label_fix),
                family_label_fix[nms], nms)
  tibble(family     = nms,
         lmg_share  = as.numeric(lmg$point@lmg),
         ci_lo      = as.numeric(lmg$eval@lmg.lower),
         ci_up      = as.numeric(lmg$eval@lmg.upper),
         sensitivity = lmg$label,
         n          = lmg$n,
         r_squared  = lmg$r_squared)
}

# -----------------------------------------------------------------------------
# 3. Sensitivity B — alternative target P18-49
# -----------------------------------------------------------------------------
form_p18 <- as.formula(paste("log(p18_49) ~", primary_rhs))
m_B <- lm(form_p18, data = d_full)
lmg_B <- run_family_lmg(m_B, "B: log(P18-49)",  nboot = 500)

# -----------------------------------------------------------------------------
# 4. Sensitivity D — drop top-10 Cook's D influential rows
# -----------------------------------------------------------------------------
# The 4/n threshold (36 rows) creates a rank-deficient design for relaimpo's
# covariance check (sparse factor cells: NBC=12, Prime=25 shrink further).
# Dropping only the top-10 most-influential points answers the same
# "what if extreme games are removed" question while keeping conditioning OK.
cooks <- cooks.distance(m_primary)
top10_idx <- order(cooks, decreasing = TRUE)[1:10]
keep <- !(seq_along(cooks) %in% top10_idx)
cat(sprintf("\nDropping top-10 Cook's D rows | keep %d of %d | threshold = %.4f\n",
            sum(keep), length(keep), min(cooks[top10_idx])))
d_D <- d_full[keep, ] |> mutate(across(where(is.factor), droplevels))
m_D <- update(m_primary, data = d_D)
lmg_D <- run_family_lmg(m_D, "D: drop top-10 Cook's D", nboot = 500)

# -----------------------------------------------------------------------------
# 5. Sensitivity E — add post_new_deal as explicit main effect
# -----------------------------------------------------------------------------
form_E <- as.formula(paste("log(p2_plus) ~", primary_rhs, "+ post_new_deal"))
m_E <- lm(form_E, data = d_full)
# post_new_deal becomes its own family so it doesn't get lumped with anything
lmg_E <- run_family_lmg(m_E, "E: + post_new_deal",
                        extra_groups = list(`post_new_deal` = "post_new_deal"),
                        nboot = 500)

# -----------------------------------------------------------------------------
# 6. Assemble unified family-level comparison table
# -----------------------------------------------------------------------------
# A: reference (full-sample) and C: pre-2025/26 — pull from Phase 5 bundle
pull_from_p5 <- function(lmg, sens_label) {
  tibble(
    family      = {
      nms <- names(lmg$point@lmg)
      ifelse(nms %in% names(family_label_fix),
             family_label_fix[nms], nms)
    },
    lmg_share   = as.numeric(lmg$point@lmg),
    ci_lo       = as.numeric(lmg$eval@lmg.lower),
    ci_up       = as.numeric(lmg$eval@lmg.upper),
    sensitivity = sens_label,
    n           = lmg$point@nobs,
    r_squared   = lmg$point@R2
  )
}

tbl_A <- pull_from_p5(p5$lmg_full_family, "A: reference (log P2+)")
tbl_C <- pull_from_p5(p5$lmg_pre_family,  "C: pre-2025/26")
tbl_B <- pull_family(lmg_B)
tbl_D <- pull_family(lmg_D)
tbl_E <- pull_family(lmg_E)

family_comp <- bind_rows(tbl_A, tbl_B, tbl_C, tbl_D, tbl_E) |>
  mutate(sensitivity = factor(sensitivity, levels = c(
    "A: reference (log P2+)",
    "B: log(P18-49)",
    "C: pre-2025/26",
    "D: drop top-10 Cook's D",
    "E: + post_new_deal"
  )))

cat("\n== Family-level LMG across sensitivities ==\n")
print(family_comp |>
        mutate(across(c(lmg_share, ci_lo, ci_up, r_squared),
                      \(x) round(x, 4))) |>
        arrange(sensitivity, desc(lmg_share)),
      n = Inf)

write_csv(family_comp, here("outputs", "tables", "tbl_robustness_family.csv"))

# -----------------------------------------------------------------------------
# 7. Comparison figure — family LMG across sensitivities
# -----------------------------------------------------------------------------
family_order <- family_comp |>
  filter(sensitivity == "A: reference (log P2+)") |>
  arrange(lmg_share) |> pull(family)

fig_robust <- family_comp |>
  mutate(family = factor(family, levels = family_order)) |>
  ggplot(aes(x = lmg_share, y = family, fill = sensitivity)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.72,
           color = "white", linewidth = 0.15) +
  geom_errorbarh(aes(xmin = ci_lo, xmax = ci_up),
                 position = position_dodge(width = 0.8),
                 height = 0.25, color = "black", linewidth = 0.35) +
  scale_fill_brewer(palette = "Set2", name = "Sensitivity") +
  scale_x_continuous(labels = scales::percent_format(accuracy = 1),
                     expand = expansion(mult = c(0, 0.05))) +
  labs(title    = "Family-level LMG across robustness checks",
       subtitle = "Bars = point estimate; whiskers = 95% bootstrap CI (1000 reps for A/C, 500 for B/D/E)",
       x = expression("share of model " * R^2), y = NULL) +
  theme(legend.position = "bottom",
        legend.direction = "vertical",
        plot.title.position = "plot")

ggsave(here("outputs", "figures", "fig_robustness.png"),
       fig_robust, width = 9, height = 6.5, dpi = 150)

# -----------------------------------------------------------------------------
# 8. Save bundle
# -----------------------------------------------------------------------------
saveRDS(list(
  lmg_B = lmg_B, lmg_D = lmg_D, lmg_E = lmg_E,
  family_comp = family_comp,
  r_squared = c(A = p5$r2_full,
                B = summary(m_B)$r.squared,
                C = p5$r2_pre,
                D = summary(m_D)$r.squared,
                E = summary(m_E)$r.squared),
  n = c(A = p5$n_full,
        B = nobs(m_B),
        C = p5$n_pre,
        D = nobs(m_D),
        E = nobs(m_E)),
  # key coefficient from E (the post_new_deal effect of interest)
  post_new_deal_beta = coef(m_E)["post_new_deal"],
  post_new_deal_ci = confint(m_E)["post_new_deal", ]
), here("data", "interim", "phase7_robustness.rds"))

cat("\nWrote:\n")
cat("  outputs/tables/tbl_robustness_family.csv\n")
cat("  outputs/figures/fig_robustness.png\n")
cat("  data/interim/phase7_robustness.rds\n")
