# Phase 3 — Exploratory data analysis

## Purpose

Sanity-check the modeling table: distribution of the target, one-screen
picture of predictor behavior, correlation structure, and missingness.
Kept deliberately short per §7 — the paper doesn't need pages of EDA.

## Inputs / Outputs

**Inputs**
- `data/processed/model_data.rds` (639 rows × 41 cols, from Phase 2)

**Outputs**
- `outputs/tables/tbl_summary_stats.csv` — numeric summary table
- `outputs/figures/eda_p2plus_hist.png` — target histograms
- `outputs/figures/eda_logp2_by_network.png` — log(P2+) by network
- `outputs/figures/eda_scatter_followers.png` — log(P2+) vs log(starters)
- `outputs/figures/eda_corr_heatmap.png` — continuous-predictor correlations
- `outputs/figures/eda_missingness.png` — missing-data summary

## Key results

### Summary statistics (headline rows)

| variable                    |   n | mean     | median   | min      | max       |
|-----------------------------|----:|---------:|---------:|---------:|----------:|
| p2_plus (thousands)         | 639 |   2,470  |   1,640  |     345  |   18,100  |
| p18_49 (thousands)          | 639 |     997  |     643  |     132  |    7,480  |
| starting5_followers_total   | 621 |  69.4 M  |  34.2 M  |   3.2 M  |   377 M   |
| team_handle_followers_home  | 639 |  20.6 M  |  12.9 M  |   5.1 M  |    63.0 M |
| market_hh_combined          | 639 |   5.80 M |   4.85 M |   1.36 M |    15.7 M |
| home_season_win_pct         | 595 |    0.610 |    0.607 |    0.00  |     1.00  |
| combined_season_win_pct     | 594 |    0.608 |    0.612 |    0.29  |     1.00  |

Full table in `outputs/tables/tbl_summary_stats.csv`.

### Target shape

`p2_plus` spans 52× (345 k to 18.1 M viewers) with heavy right skew. The
log histogram is visibly symmetric and near-Gaussian — **confirms `log(P2+)`
as the correct scale** for the primary model.

### Network separation

Median `log(P2+)` ordering (low → high): `PRIME VIDEO`, `TNT`, `ESPN`,
`TNT+TRUTV`, `NBC`, `ABC`. The broadcast networks (ABC, NBC) sit on top as
expected. NBC's 18 rows are the new-media-deal 2025-26 games; their
position near the top is a preview of the `post_new_deal` effect, though
it's confounded with the Finals share on NBC — Phase 4/5 will disentangle.

### Follower ↔ audience relationship

Simple bivariate fit of `log(P2+)` ~ `log1p(starting5_followers_total)`
shows a visibly positive slope. This is the headline expectation being
tested: star power on the floor predicts audience.

### Correlation structure (continuous predictors, log-scaled where applicable)

Top five pairwise correlations (complete cases, n ≈ 574):

| v1                        | v2                        |   r   |
|---------------------------|---------------------------|------:|
| combined_season_win_pct   | home_season_win_pct       |  0.72 |
| combined_season_win_pct   | away_season_win_pct       |  0.71 |
| home_season_win_pct       | home_last5_win_pct        |  0.58 |
| away_season_win_pct       | away_last5_win_pct        |  ~0.57 |
| starting5_followers_total | team_handle_followers_home | moderate |

The ~0.72 correlations between `combined_season_win_pct` and its
components are structural (it's the mean of the two). The primary model
(§8.1) uses `combined_season_win_pct` only — not the components — so this
is not a modeling problem. VIF in Phase 6 will be the authoritative check.

### Missingness

Concentrated in two known buckets, nothing else:

- **18 rows** (2.8 %): hoopR-unmatched from Phase 1 → NA on all hoopR-
  derived features (starter followers, team form).
- **27 additional rows** (4.2 %): first 1–4 games of a team's season →
  NA on rolling form until the window is filled.

Every non-hoopR-dependent column has 0 NAs. Phase 4 will fit on complete
cases — effective n ≈ 574 for `last5`-dependent features, ≈ 595 for
season-W%-dependent features, 639 for network/timing-only models.

## Decisions made in this phase

- **Log-transform the target before modeling.** Histogram confirms Gaussian-like log scale; raw scale is severely right-skewed.
- **Use `log1p()` on follower counts** (followers have a zero lower bound for obscure-rookie cases in principle, and `log1p` handles 0 gracefully).
- **EDA uses complete cases only** for the correlation matrix; imputation is deferred to modeling where appropriate.
- **No formal outlier removal at EDA stage.** The top-audience observations (~18 M) are real (NBA Finals); they will be re-examined via Cook's D in Phase 6.
- **Kept the EDA to 5 figures.** The paper can accommodate 2–3 EDA visuals at most; producing more would be waste.

## Assumptions relied on

- Target distribution is well-approximated by a Gaussian on the log scale (GLM-OLS assumption, to be re-checked by Q-Q in Phase 6).
- Pairwise Pearson correlations are a good first-pass collinearity screen for continuous, log-scaled predictors (will be replaced by VIF later).
- Missingness in `last5_win_pct` / `season_win_pct` is informative only about season phase (first few games) — not about the target.

## Alternatives considered but not chosen

- *Stratified summaries by `season_type` or `network`* — deferred to the coefficient/LMG tables in Phases 4–5, where they'll be more interpretable.
- *Plot each of the 24 modeling columns individually* — not worth the paper real estate; the summary table covers it.
- *Use `GGally::ggpairs` for a scatter matrix* — too dense to be readable in a 5-page paper; the correlation heatmap is enough.
- *Formal normality tests on `log(P2+)`* — visual is sufficient at n = 639 and formal tests reject trivially at that sample size.

## Risks / things a human should double-check

1. **Network confound**: NBC (n=18) is 100 % 2025-26 and includes Finals games. The network coefficient in Phase 4 will absorb some `post_new_deal` effect; the variance decomposition in Phase 5 will show how much is unique to each.
2. **Structural correlation** between `combined_season_win_pct` and its components is a non-issue in the primary model (only `combined` is used), but if a human wants to swap in the components later, they'll need to drop `combined` or use VIF to pick.
3. **The 18 hoopR-unmatched rows** disappear from any model that uses starters/form. If LMG weights those families heavily, the effective-n shrinkage is worth noting explicitly in §5 of Phase 4.

## Code quality self-assessment

Short, linear, deterministic (`set.seed(4010)`). All figures go through
`ggsave` with fixed `dpi = 150` and specified widths so the paper has
consistent visual weight. Nothing numerical to validate beyond the
summary table, which was written alongside the figures.

## --- HUMAN COLLABORATION LOG ---

### Human inputs / decisions that shaped this phase

- "its fine - go for phase 3" → greenlit Phase 3 after Phase 2 sign-off. No scope changes.

### Human questions answered in-chat

- (none this phase)

### Where the human did NOT intervene

- Choice of the 5 figures (histograms, network boxplot, follower scatter, correlation heatmap, missingness bar).
- Decision to run the correlation matrix on complete cases rather than pairwise.
- Decision to skip per-predictor marginal histograms.
- Log-scale handling (log for target, log1p for followers) in EDA.
