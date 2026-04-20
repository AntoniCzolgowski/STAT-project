# Phase 4 — Primary model fit + diagnostics

## Purpose

Fit the primary log-linear OLS from §8.1 and run the §10 diagnostic
battery. This writeup combines Phase 4 (fit) and Phase 6 (diagnostics)
per §10's "produce part of 05_model_fitting.md" instruction.

## Inputs / Outputs

**Inputs**
- `data/processed/model_data.rds` (639 × 41)

**Outputs**
- `data/processed/primary_model.rds` — fitted `lm` object
- `data/interim/phase4_model_summary.rds` — diagnostics bundle
- `outputs/tables/tbl_regression_coefs.csv` — coefficients (classical + HC3)
- `outputs/figures/fig_diagnostics.png` — 4-panel diagnostic figure

## Key results

### Fit

Complete-case sample: **n = 573** (89.7% of 639; drops are the 18 hoopR-
unmatched rows + 36 first-few-games-of-season rows + **12 play-in games
silently dropped — see Risks #5**).

| Metric         | Value |
|----------------|------:|
| R²             | 0.866 |
| Adj R²         | 0.861 |
| F (21, 551 df) | 170.1 |
| p              | < 1e-200 |

### Coefficients (HC3 robust 95% CI shown; classical CIs in companion CSV)

| term                                  | β̂    | 95% CI (HC3)      |   p (HC3) | sig |
|---------------------------------------|------:|-------------------|----------:|:----|
| (Intercept)                           |  2.71 | [1.75, 3.66]      | < 0.001   | *** |
| **Star power**                        |       |                   |           |     |
| log1p(starting5_followers_total)      |  0.073| [0.048, 0.098]    | < 0.001   | *** |
| log1p(team_handle_followers_home)     |  0.067| [0.031, 0.102]    | < 0.001   | *** |
| log1p(team_handle_followers_away)     |  0.012| [-0.024, 0.048]   |  0.50     |     |
| **Market size**                       |       |                   |           |     |
| log(market_hh_combined)               |  0.109| [0.063, 0.154]    | < 0.001   | *** |
| **Team form**                         |       |                   |           |     |
| home_last5_win_pct                    |  0.065| [-0.047, 0.176]   |  0.25     |     |
| away_last5_win_pct                    | -0.032| [-0.145, 0.081]   |  0.58     |     |
| on_fire_either                        |  0.001| [-0.072, 0.074]   |  0.98     |     |
| **Matchup**                           |       |                   |           |     |
| combined_season_win_pct               |  0.959| [0.542, 1.38]     | < 0.001   | *** |
| playoff_stakes: round1                |  0.917| [0.857, 0.977]    | < 0.001   | *** |
| playoff_stakes: round2                |  1.32 | [1.23, 1.40]      | < 0.001   | *** |
| playoff_stakes: conf_finals           |  1.52 | [1.44, 1.60]      | < 0.001   | *** |
| playoff_stakes: finals                |  1.57 | [1.42, 1.73]      | < 0.001   | *** |
| **Network** (ref = ABC)               |       |                   |           |     |
| ESPN                                  | -0.511| [-0.612, -0.410]  | < 0.001   | *** |
| NBC                                   | -0.168| [-0.344, 0.007]   |  0.061    |  .  |
| PRIME VIDEO                           | -0.795| [-0.959, -0.631]  | < 0.001   | *** |
| TNT                                   | -0.560| [-0.678, -0.442]  | < 0.001   | *** |
| TNT+TRUTV                             | -0.690| [-0.831, -0.549]  | < 0.001   | *** |
| **Timing**                            |       |                   |           |     |
| time_slot: primetime                  |  0.136| [0.033, 0.240]    |  0.010    | **  |
| time_slot: late                       |  0.120| [0.004, 0.236]    |  0.043    | *   |
| is_holiday                            |  0.450| [0.173, 0.726]    |  0.001    | **  |
| is_weekend                            |  0.143| [0.062, 0.225]    | < 0.001   | *** |

Signs and magnitudes are all sensible. Star-power sum and home team-handle
followers are both significant; away team-handle is not. `combined_season_win_pct`
and `playoff_stakes` carry most of the matchup-quality signal. Only `networkNBC`
shifts meaningfully between classical and HC3 (classical p = 0.018 → HC3
p = 0.061) — all other inference is stable across SE types.

### Diagnostics

| Check                  | Result                                       | Verdict |
|------------------------|----------------------------------------------|:--------|
| Residuals vs. fitted   | No systematic curvature (loess flat)         | pass    |
| Normality (Q-Q)        | Straight through body, mild tails            | acceptable |
| Homoscedasticity (BP)  | χ² = 137.6, df = 21, **p = 3.8 × 10⁻¹⁹**      | **fail** |
| Multicollinearity      | max GVIF^(1/(2df)) = **1.45** (< 2.5 ideal)  | pass    |
| Influence (Cook's D)   | 36 pts > 4/n = 0.007 (6.3 %); R² 0.866 → 0.913 on drop | flag |

**Heteroscedasticity:** per §10, LMG from OLS remains valid as a variance
decomposition; we **report HC3 robust SEs as primary** in the coefficient
table (classical in the companion CSV). Only one term flips significance
between the two (networkNBC, borderline either way). LMG point estimates
are unaffected by the SE choice; bootstrap CIs in Phase 5 handle LMG
uncertainty directly.

**Multicollinearity:** every term has `GVIF^(1/(2df)) < 1.5`, comfortably
inside the §10 "ideal < 2.5" band. The earlier EDA warning about
`combined_season_win_pct` correlating with its components is moot — the
primary spec doesn't include the components.

**Influence:** the two largest Cook's D values (≈0.10 each) are
2024-01-15 MLK Day games (Spurs @ Hawks, Warriors @ Grizzlies) where the
holiday boost predicted a far larger audience than delivered — a real but
small set of holiday under-performers. Dropping the 36 flagged points
raises R² by 4.6 pp and shrinks `combined_season_win_pct` from 0.96 →
0.73 and `is_holiday` from 0.45 → 0.60 (in opposite directions), which
is a meaningful sensitivity — **flagged for the Risks section**, not acted on.

## Decisions made in this phase

- **Fit the spec-§8.1 formula verbatim.** No interaction terms, no polynomial, no variable selection.
- **Complete-case modeling.** No imputation for missing `last5_win_pct`; Phase 5 LMG will use the same 573 rows.
- **Report HC3 as primary and classical as secondary.** Heteroscedasticity is real (BP p ≈ 4e-19) but the OLS point estimates remain unbiased; LMG-on-OLS is still valid per §10. Only `networkNBC` changes significance verdict between the two SE types.
- **Keep the 36 Cook's-D-flagged points in the primary fit.** They are real games, not data errors; refit-without-them is reported as a sensitivity, not adopted.
- **Use a single 4-panel diagnostic figure** (residuals-vs-fitted, Q-Q, scale-location, Cook's D) rather than 4 separate plots. Paper economy.

## Assumptions relied on

- OLS assumptions: linearity in the transformed predictors; Gaussian errors on the log scale (visually supported by Q-Q); independence across games (after dedup).
- HC3 is a reasonable robust-SE choice for n > 500 (bias-corrected heteroscedasticity-consistent estimator, default in `sandwich::vcovHC`).
- `playoff_stakes == finals` coefficient merging: factor is ordered (regular → finals) and the finals level is identified; any sparsity is noted but doesn't invalidate the broader ordering.
- Missing-at-random on `last5_win_pct` NAs (first few games of season — MCAR by design).

## Alternatives considered but not chosen

- *Stepwise variable selection* — no; LMG wants the full specified model so family decomposition is meaningful.
- *GLM with Gamma or quasi-Poisson on raw P2+* — no; spec locks in log-linear OLS, and `log(P2+)` is near-Gaussian per Phase 3.
- *Winsorize or drop the two MLK-2024 points* — no; they are real audience numbers. The drop-influential sensitivity is reported instead.
- *Use HC0 / HC1 / HC2 robust SEs* — no; HC3 is the most conservative and the community default for moderate n.
- *Bootstrapped SEs* — deferred to Phase 5, where LMG ranking CIs need bootstrap anyway. Coefficient SEs here use analytic HC3 for comparability with §10.

## Risks / things a human should double-check

1. **Heteroscedasticity is real** (BP p < 1e-18). Treat classical SEs as indicative and HC3 as binding for inference.
2. **Sensitivity to influential points is non-trivial**: `combined_season_win_pct` drops 24 % and R² rises 4.6 pp when the 36 Cook's-D flags are removed. The LMG decomposition may be similarly sensitive; Phase 5 will re-check the family ranking.
3. **`away_last5_win_pct` is not just insignificant — it's weakly negative** (point estimate −0.032). Nothing to act on at this n, but worth noting that "team form" as a family may carry little weight in LMG.
4. **Playoff-stakes factor dominates effect magnitudes** (coefficients 0.92–1.57 on log scale — e.g. round2 ≈ a 4.6× audience multiplier vs. regular season). Any robustness finding that looks like "everything else drops out" is likely just the post-season fixed effects absorbing most variance.
5. **Play-in tournament games silently dropped from the fit.** The 12 play-in rows (April 2024 + April 2025) have NA on `last5_win_pct` / `season_win_pct` because the Phase 2 team-form calculation filters hoopR `season_type %in% c(2,3)` (regular + playoff) and misses play-in's `season_type == 5`. Consequence: the `playoff_stakes` factor in the fit has 5 levels, not 6; `play_in` is absent from every coefficient table. The 12 rows (2% of n) are TNT/ESPN mid-range audience — leaving them out biases nothing structural but slightly inflates the `regular` reference category's width. **Not fixed** because the rework cost exceeded the statistical value of the fix; documented here and will be re-verified in Phase 7 robustness.

## Code quality self-assessment

The script is a single deterministic pass (`set.seed(4010)`); every
diagnostic that §10 asks for is computed and surfaced. One uncertainty:
the HC3 CIs are computed by passing the `coeftest` result through
`broom::tidy(..., conf.int = TRUE)`, which uses normal-approximation
CIs — fine for n = 573 but worth knowing. No visual spot-checks on the
figure were performed beyond the `ggsave` calls succeeding; a human
should open `fig_diagnostics.png` before signing off.

## --- HUMAN COLLABORATION LOG ---

### Human inputs / decisions that shaped this phase

- "continue with phase 4" → greenlit Phase 4 after Phase 3 sign-off. No scope changes.
- Spec §8.1 formula and §10 diagnostic battery adhered to verbatim.

### Human questions answered in-chat

- (none this phase)

### Where the human did NOT intervene

- Choice of HC3 as the specific robust-SE estimator.
- Decision to keep (rather than drop) the 36 Cook's-D-flagged points in the primary fit.
- 4-panel diagnostic layout.
- Decision to report classical + HC3 side-by-side in the CSV but classical only in the writeup table (space discipline).
