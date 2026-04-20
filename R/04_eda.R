# =============================================================================
# Phase 3 — Exploratory Data Analysis
# =============================================================================
# Per 00_PROJECT_CONTEXT.md §7. Short by design: a summary table, a few
# targeted plots, a correlation heatmap, a missingness panel. No pages of
# marginal distributions.
#
# Inputs:  data/processed/model_data.rds
# Outputs: outputs/figures/*.png, outputs/tables/tbl_summary_stats.csv,
#          data/interim/phase3_eda_summary.rds
# =============================================================================

set.seed(4010)

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readr); library(stringr)
  library(ggplot2); library(patchwork); library(here)
})

theme_set(theme_minimal(base_size = 11))

fig_dir <- here("outputs", "figures")
tbl_dir <- here("outputs", "tables")
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(tbl_dir, showWarnings = FALSE, recursive = TRUE)

d <- readRDS(here("data", "processed", "model_data.rds"))
cat("rows:", nrow(d), " | cols:", ncol(d), "\n")

# -----------------------------------------------------------------------------
# 1. Summary table for numeric features + targets
# -----------------------------------------------------------------------------
num_cols <- c(
  "p2_plus", "p18_49",
  "starting5_followers_home", "starting5_followers_away",
  "starting5_followers_total",
  "team_handle_followers_home", "team_handle_followers_away",
  "market_hh_home", "market_hh_away", "market_hh_combined",
  "home_season_win_pct", "away_season_win_pct",
  "home_last5_win_pct", "away_last5_win_pct",
  "combined_season_win_pct"
)

summary_tbl <- d |>
  select(all_of(num_cols)) |>
  pivot_longer(everything(), names_to = "variable", values_to = "x") |>
  group_by(variable) |>
  summarise(n        = sum(!is.na(x)),
            n_na     = sum(is.na(x)),
            mean     = mean(x, na.rm = TRUE),
            sd       = sd(x, na.rm = TRUE),
            median   = median(x, na.rm = TRUE),
            min      = min(x, na.rm = TRUE),
            max      = max(x, na.rm = TRUE),
            .groups  = "drop") |>
  mutate(variable = factor(variable, levels = num_cols)) |>
  arrange(variable)

print(summary_tbl, n = Inf)
write_csv(summary_tbl, here(tbl_dir, "tbl_summary_stats.csv"))

# -----------------------------------------------------------------------------
# 2. Target: histograms of P2+ and log(P2+)
# -----------------------------------------------------------------------------
p_raw <- ggplot(d, aes(x = p2_plus / 1000)) +
  geom_histogram(bins = 40, fill = "steelblue", color = "white") +
  labs(title = "P2+ audience (thousands)",
       x = "P2+ (thousands of viewers)", y = "games")

p_log <- ggplot(d, aes(x = log(p2_plus))) +
  geom_histogram(bins = 40, fill = "steelblue", color = "white") +
  labs(title = "log(P2+)", x = "log(P2+)", y = "games")

ggsave(here(fig_dir, "eda_p2plus_hist.png"),
       p_raw + p_log, width = 10, height = 4, dpi = 150)

# -----------------------------------------------------------------------------
# 3. log(P2+) by network (boxplot)
# -----------------------------------------------------------------------------
net_order <- d |> group_by(network) |>
  summarise(m = median(log(p2_plus))) |> arrange(m) |> pull(network)

p_net <- d |>
  mutate(network = factor(network, levels = as.character(net_order))) |>
  ggplot(aes(x = network, y = log(p2_plus), fill = network)) +
  geom_boxplot(alpha = 0.7, outlier.size = 1) +
  geom_jitter(width = 0.15, alpha = 0.25, size = 0.6) +
  coord_flip() +
  guides(fill = "none") +
  labs(title = "log(P2+) by network",
       x = NULL, y = "log(P2+)")
ggsave(here(fig_dir, "eda_logp2_by_network.png"),
       p_net, width = 8, height = 4.5, dpi = 150)

# -----------------------------------------------------------------------------
# 4. Scatter: log(P2+) vs log(starting5_followers_total)
# -----------------------------------------------------------------------------
p_scatter <- d |>
  filter(!is.na(starting5_followers_total)) |>
  ggplot(aes(x = log1p(starting5_followers_total), y = log(p2_plus))) +
  geom_point(alpha = 0.35, size = 0.9, color = "steelblue") +
  geom_smooth(method = "lm", se = TRUE, color = "black") +
  labs(title = "log(P2+) vs log(starting-5 followers, home + away)",
       x = "log1p(starting5_followers_total)",
       y = "log(P2+)")
ggsave(here(fig_dir, "eda_scatter_followers.png"),
       p_scatter, width = 7, height = 5, dpi = 150)

# -----------------------------------------------------------------------------
# 5. Correlation heatmap among continuous predictors (complete cases)
# -----------------------------------------------------------------------------
cont_cols <- c(
  "starting5_followers_total",
  "team_handle_followers_home", "team_handle_followers_away",
  "market_hh_combined",
  "home_season_win_pct", "away_season_win_pct",
  "home_last5_win_pct", "away_last5_win_pct",
  "combined_season_win_pct"
)

X <- d |>
  select(all_of(cont_cols)) |>
  mutate(across(starts_with("starting5") |
                starts_with("team_handle") |
                starts_with("market_hh"), ~ log1p(.))) |>
  drop_na()

cor_mat <- cor(X)
cor_long <- as_tibble(cor_mat, rownames = "v1") |>
  pivot_longer(-v1, names_to = "v2", values_to = "r") |>
  mutate(v1 = factor(v1, levels = cont_cols),
         v2 = factor(v2, levels = rev(cont_cols)))

p_cor <- ggplot(cor_long, aes(v1, v2, fill = r)) +
  geom_tile(color = "white") +
  geom_text(aes(label = sprintf("%.2f", r)), size = 2.8) +
  scale_fill_gradient2(low = "firebrick", mid = "white", high = "steelblue",
                       midpoint = 0, limits = c(-1, 1)) +
  theme(axis.text.x = element_text(angle = 35, hjust = 1)) +
  labs(title = "Correlations among continuous predictors (log-scaled where applicable)",
       x = NULL, y = NULL)

ggsave(here(fig_dir, "eda_corr_heatmap.png"),
       p_cor, width = 8, height = 7, dpi = 150)

max_abs_cor <- cor_long |>
  filter(as.character(v1) != as.character(v2)) |>
  mutate(r_abs = abs(r)) |>
  arrange(desc(r_abs)) |>
  slice_head(n = 5)

cat("\nTop 5 |correlations| among continuous predictors:\n")
print(max_abs_cor)

# -----------------------------------------------------------------------------
# 6. Missingness summary (plot)
# -----------------------------------------------------------------------------
all_model_cols <- c(num_cols,
                    "playoff_stakes", "network", "is_broadcast",
                    "post_new_deal", "day_of_week", "time_slot",
                    "is_holiday", "is_weekend", "on_fire_either")

miss_tbl <- d |>
  summarise(across(all_of(all_model_cols), ~ sum(is.na(.)))) |>
  pivot_longer(everything(), names_to = "column", values_to = "n_missing") |>
  mutate(pct_missing = 100 * n_missing / nrow(d)) |>
  arrange(desc(n_missing))

p_miss <- miss_tbl |>
  mutate(column = factor(column, levels = rev(column))) |>
  ggplot(aes(x = column, y = pct_missing)) +
  geom_col(fill = "firebrick", alpha = 0.7) +
  geom_text(aes(label = ifelse(n_missing > 0,
                               sprintf("%d (%.1f%%)", n_missing, pct_missing),
                               "")),
            hjust = -0.1, size = 3) +
  coord_flip() +
  ylim(0, max(miss_tbl$pct_missing) * 1.25 + 0.5) +
  labs(title = "Missingness per modeling column",
       x = NULL, y = "% missing")

ggsave(here(fig_dir, "eda_missingness.png"),
       p_miss, width = 8, height = 6, dpi = 150)

# -----------------------------------------------------------------------------
# 7. Save summary object
# -----------------------------------------------------------------------------
eda_summary <- list(
  summary_tbl        = summary_tbl,
  top_correlations   = max_abs_cor,
  missingness        = miss_tbl,
  n_rows             = nrow(d),
  n_complete_cases   = sum(complete.cases(d |> select(all_of(num_cols))))
)
saveRDS(eda_summary, here("data", "interim", "phase3_eda_summary.rds"))

cat("\nWrote figures:\n")
cat("  outputs/figures/eda_p2plus_hist.png\n")
cat("  outputs/figures/eda_logp2_by_network.png\n")
cat("  outputs/figures/eda_scatter_followers.png\n")
cat("  outputs/figures/eda_corr_heatmap.png\n")
cat("  outputs/figures/eda_missingness.png\n")
cat("\nWrote tables:\n")
cat("  outputs/tables/tbl_summary_stats.csv\n")
cat("\nWrote summary object:\n")
cat("  data/interim/phase3_eda_summary.rds\n")
