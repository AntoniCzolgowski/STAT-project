# =============================================================================
# Phase 5 — Variance decomposition (LMG) + bootstrap CIs  (§9)
# =============================================================================
# Run LMG variance decomposition on the primary model from Phase 4, at both
# term level and family level, with 1000-rep bootstrap CIs. Do the same on
# the pre-2025/26 subsample to pre-empt the NBC/post-new-deal confound.
# Produces the paper's headline Figure 2 (family LMG with CIs, two samples).
#
# Inputs:  data/processed/primary_model.rds
#          data/processed/model_data.rds
# Outputs: data/interim/phase5_lmg_results.rds
#          outputs/tables/tbl_lmg_family.csv
#          outputs/tables/tbl_lmg_terms.csv
#          outputs/figures/fig_lmg_family.png  (headline Figure 2)
#          outputs/figures/fig_lmg_terms.png   (appendix)
# =============================================================================

set.seed(4010)

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readr); library(stringr); library(tibble)
  library(ggplot2); library(patchwork); library(here)
  library(relaimpo); library(boot)
})

theme_set(theme_minimal(base_size = 10))

# -----------------------------------------------------------------------------
# 1. Load primary model + reconstruct both samples
# -----------------------------------------------------------------------------
m_full <- readRDS(here("data", "processed", "primary_model.rds"))
d      <- readRDS(here("data", "processed", "model_data.rds"))

# Reconstruct the Phase 4 complete-case frame (rownames of model.frame are
# df_model-relative, not d-relative, so we can't index d directly).
required <- c(
  "p2_plus",
  "starting5_followers_total",
  "team_handle_followers_home", "team_handle_followers_away",
  "market_hh_combined",
  "home_last5_win_pct", "away_last5_win_pct", "on_fire_either",
  "combined_season_win_pct", "playoff_stakes", "network",
  "time_slot", "is_holiday", "is_weekend"
)
d_full <- d |> drop_na(all_of(required))
stopifnot(nrow(d_full) == nobs(m_full))

d_pre <- d_full |>
  filter(season != "2025/2026") |>
  mutate(across(where(is.factor), droplevels))

cat("full sample n =", nrow(d_full),
    " | pre-2025/26 n =", nrow(d_pre), "\n")

m_pre <- update(m_full, data = d_pre)
cat("R^2 full =", round(summary(m_full)$r.squared, 4),
    " | R^2 pre =", round(summary(m_pre)$r.squared, 4), "\n")

# -----------------------------------------------------------------------------
# 2. Family grouping (names as they appear in the formula RHS)
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# 3. LMG: family-level point estimates + bootstrap CIs
# -----------------------------------------------------------------------------
run_family_lmg <- function(m, label, nboot = 1000) {
  cat(sprintf("\n--- family-level LMG (%s, boot=%d) ---\n", label, nboot))
  ri <- calc.relimp(m, type = "lmg",
                    groups     = families,
                    groupnames = names(families),
                    rela = FALSE)
  set.seed(4010)
  bo <- boot.relimp(m, b = nboot, type = "lmg",
                    groups     = families,
                    groupnames = names(families),
                    rela = FALSE, fixed = FALSE, diff = FALSE)
  ev <- booteval.relimp(bo, level = 0.95)
  list(point = ri, boot = bo, eval = ev, label = label)
}

lbl_full <- sprintf("full (n=%d)",        nobs(m_full))
lbl_pre  <- sprintf("pre-2025/26 (n=%d)", nobs(m_pre))

lmg_full <- run_family_lmg(m_full, lbl_full, nboot = 1000)
lmg_pre  <- run_family_lmg(m_pre,  lbl_pre,  nboot = 1000)

# Extract family table (point + CIs)
# relaimpo silently drops groupnames for single-element groups and returns
# the raw formula token instead. Map them back to the human labels.
family_label_fix <- c(
  "log(market_hh_combined)" = "Market size",
  "network"                 = "Network"
)

pull_family <- function(lmg) {
  est <- as.numeric(lmg$point@lmg)
  nms <- names(lmg$point@lmg)
  ci_lo <- as.numeric(lmg$eval@lmg.lower)
  ci_up <- as.numeric(lmg$eval@lmg.upper)
  nms <- ifelse(nms %in% names(family_label_fix),
                family_label_fix[nms], nms)
  tibble(family   = nms,
         r2_share = est,
         ci_lo    = ci_lo,
         ci_up    = ci_up,
         sample   = lmg$label)
}

family_tbl <- bind_rows(pull_family(lmg_full), pull_family(lmg_pre))
cat("\n== Family-level LMG table ==\n")
print(family_tbl |> mutate(across(where(is.numeric), \(x) round(x, 4))))

write_csv(family_tbl, here("outputs", "tables", "tbl_lmg_family.csv"))

# -----------------------------------------------------------------------------
# 4. Figure 2 — family-level LMG, dual-sample, with bootstrap CIs
# -----------------------------------------------------------------------------
family_order <- family_tbl |>
  filter(sample == lbl_full) |>
  arrange(r2_share) |>
  pull(family)

family_tbl_p <- family_tbl |>
  mutate(family = factor(family, levels = family_order),
         sample = factor(sample, levels = c(lbl_full, lbl_pre)))

fill_pal <- setNames(c("steelblue", "firebrick"), c(lbl_full, lbl_pre))

fig_family <- ggplot(family_tbl_p,
                     aes(x = r2_share, y = family, fill = sample)) +
  geom_col(position = position_dodge(width = 0.75), width = 0.7,
           color = "white", linewidth = 0.2) +
  geom_errorbarh(aes(xmin = ci_lo, xmax = ci_up),
                 position = position_dodge(width = 0.75),
                 height = 0.25, color = "black", linewidth = 0.4) +
  scale_fill_manual(values = fill_pal, name = "Sample") +
  scale_x_continuous(labels = scales::percent_format(accuracy = 1),
                     expand = expansion(mult = c(0, 0.05))) +
  labs(title    = "Family-level variance decomposition of log(P2+)",
       subtitle = "LMG share with 95% bootstrap CI (1000 reps). Sum over families = model R^2.",
       x = expression("share of model " * R^2), y = NULL) +
  theme(legend.position = "bottom",
        plot.title.position = "plot")

ggsave(here("outputs", "figures", "fig_lmg_family.png"),
       fig_family, width = 9, height = 5, dpi = 150)

# -----------------------------------------------------------------------------
# 5. Term-level LMG (appendix)
# -----------------------------------------------------------------------------
cat("\n--- term-level LMG (no grouping) ---\n")
term_full <- calc.relimp(m_full, type = "lmg", rela = FALSE)
term_pre  <- calc.relimp(m_pre,  type = "lmg", rela = FALSE)

term_tbl <- bind_rows(
  tibble(term = names(term_full@lmg),
         r2_share = as.numeric(term_full@lmg),
         sample = lbl_full),
  tibble(term = names(term_pre@lmg),
         r2_share = as.numeric(term_pre@lmg),
         sample = lbl_pre)
)

print(term_tbl |> arrange(sample, desc(r2_share)) |>
        mutate(r2_share = round(r2_share, 4)), n = Inf)
write_csv(term_tbl, here("outputs", "tables", "tbl_lmg_terms.csv"))

# Term-level figure (appendix)
term_order <- term_tbl |>
  filter(sample == lbl_full) |>
  arrange(r2_share) |> pull(term)

term_tbl_p <- term_tbl |>
  mutate(term = factor(term, levels = term_order),
         sample = factor(sample, levels = c(lbl_full, lbl_pre)))

fig_terms <- ggplot(term_tbl_p, aes(x = r2_share, y = term, fill = sample)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7,
           color = "white", linewidth = 0.2) +
  scale_fill_manual(values = fill_pal, name = "Sample") +
  scale_x_continuous(labels = scales::percent_format(accuracy = 1),
                     expand = expansion(mult = c(0, 0.05))) +
  labs(title = "Term-level LMG shares (no bootstrap)",
       x = expression("share of model " * R^2), y = NULL) +
  theme(legend.position = "bottom")

ggsave(here("outputs", "figures", "fig_lmg_terms.png"),
       fig_terms, width = 9, height = 7, dpi = 150)

# -----------------------------------------------------------------------------
# 6. Save results bundle
# -----------------------------------------------------------------------------
saveRDS(list(
  lmg_full_family = lmg_full,
  lmg_pre_family  = lmg_pre,
  term_full       = term_full,
  term_pre        = term_pre,
  family_tbl      = family_tbl,
  term_tbl        = term_tbl,
  r2_full         = summary(m_full)$r.squared,
  r2_pre          = summary(m_pre)$r.squared,
  n_full          = nobs(m_full),
  n_pre           = nobs(m_pre)
), here("data", "interim", "phase5_lmg_results.rds"))

cat("\nWrote:\n")
cat("  outputs/tables/tbl_lmg_family.csv\n")
cat("  outputs/tables/tbl_lmg_terms.csv\n")
cat("  outputs/figures/fig_lmg_family.png   (headline Figure 2)\n")
cat("  outputs/figures/fig_lmg_terms.png\n")
cat("  data/interim/phase5_lmg_results.rds\n")
