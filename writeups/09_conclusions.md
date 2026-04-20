# Phase 9 — Conclusions

## Purpose

Integrate findings across Phases 1–8 into a single answer to the
research question: **what drives NBA national-television ratings?**
This writeup also catalogs the paper-ready outputs (`tbl1`–`tbl4`,
`fig1`–`fig5`) produced by `R/09_paper_outputs.R`.

## Inputs / Outputs

**Inputs**
- All phase bundles in `data/interim/phase{5,7,8}_*.rds`
- All CSVs in `outputs/tables/`
- All PNGs in `outputs/figures/`

**Outputs**
- `outputs/tables/tbl{1..4}_*.{csv,tex}` — paper tables
- `outputs/figures/fig{1..5}_*.png` — paper figures
- This writeup

## Paper artifacts

| # | Artifact | File | Source phase |
|---|---|---|---|
| Table 1 | Descriptive stats (continuous + categorical) | `tbl1_descriptive_stats.{csv,tex}` | Phase 1/2 |
| Table 2 | Regression coefficients with HC3 CIs | `tbl2_regression_coefficients.{csv,tex}` | Phase 4 |
| Table 3 | Robustness family-LMG comparison | `tbl3_robustness.{csv,tex}` | Phase 7 |
| Table 4 | Regular-season-only family-LMG | `tbl4_regular_season.{csv,tex}` | Phase 8 |
| Fig 1 | Model diagnostics panel | `fig1_diagnostics.png` | Phase 4 |
| Fig 2 | **Headline** — family LMG with 95% CIs | `fig2_family_lmg.png` | Phase 5 |
| Fig 3 | Variable-level LMG (top terms) | `fig3_variable_lmg.png` | Phase 5 |
| Fig 4 | Scatter: followers vs log(P2+) | `fig4_scatter_followers.png` | Phase 3 EDA |
| Fig 5 | Regular-season family LMG | `fig5_regular_season.png` | Phase 8 |

## Headline findings

### 1. Matchup dominates — but almost entirely because playoffs matter

The full-sample family decomposition (Phase 5, `fig2_family_lmg.png`)
shows **Matchup ≈ 60% of R²**, **Network ≈ 16%**, **Timing ≈ 7%**,
and the remaining three families (Star power, Team form, Market size)
each < 2%. This ordering is invariant across four robustness
specifications (Phase 7 / `tbl3`): alternative target log(P18-49),
pre-2025/26 sample, influence-trimmed sample, and with an explicit
`post_new_deal` term. The CI bounds never overlap the rank of a
different family.

Caveat — and this is the more precise reading of the headline:
`playoff_stakes` does nearly all of the Matchup work. `playoff_stakesfinals`
alone has β = +1.57 on log(P2+) (HC3 CI (1.42, 1.73)); by contrast
`combined_season_win_pct` carries β = +0.96 (CI (0.54, 1.38)) across
its entire [0.29, 1.00] range. Treat "Matchup" in the headline as
shorthand for **"is this a high-stakes game?"**, with team-quality
a secondary contributor.

### 2. Network identity is the second-largest driver

Network carries 16.5% of R² (CI 13.6–19.6%) and every non-ABC network
has a negative, highly significant coefficient relative to ABC (HC3
p < 10⁻¹⁸ for ESPN, TNT, Prime Video, TNT+TruTV). The magnitudes
reflect promotional weight and audience reach more than any basketball
property. The ordering survives both the pre-2025/26 check (which
removes NBC/Peacock) and the explicit `post_new_deal` term (which
isolates the rights-deal era effect) — both exercises shrink Network
modestly (16.5% → 12.6% / 15.9%) but don't reorder it.

### 3. The regular-season story is *completely different*

**This is a finding not in the original plan.** Restricting to
regular-season games (Phase 8, `fig5_regular_season.png`, `tbl4`)
inverts the ordering:

| Family | Full sample | Regular only |
|---|---:|---:|
| Matchup | 60.1% | **3.2%** |
| Network | 16.5% | **31.4%** |
| Timing | 6.7% | **16.5%** |
| Star power | 1.7% | **10.9%** |
| Market size | 0.7% | 2.3% |
| Team form | 1.0% | 1.5% |

Inside the regular season:
- **Network** is the single biggest driver at ~31%.
- **Timing** (tipoff slot / weekend / holiday) grows 2.5× to ~17%.
- **Star power** grows 6× to ~11% — the audience really does tune
  in for personalities when stakes are lower.
- **Matchup** collapses to 3%: `combined_season_win_pct` alone
  explains almost nothing once we can no longer encode "playoff
  game yes/no."
- **Season timing** (weeks-until-playoffs) is negligible at 0.3%
  of R² (β = 0.0048 / week, CI barely excluding zero). Whatever
  playoff-race signal exists is already absorbed by team-form
  variables.

The regular-season model fits materially less well (R² = 0.658 vs
0.866 full sample) — regular-season ratings are intrinsically
noisier — but the *shares* are well-identified and the CIs around
them are tight.

### 4. Star power, team form, and market size are all small

Across every specification, each of these three families holds
~0.6–1.8% of full-sample R² (or 1.5–11% regular-season, star power
being the exception). Point estimates for
`log1p(starting5_followers_total)` and `log(market_hh_combined)`
are positive and HC3-significant (p < 10⁻⁶), so the *sign* of these
effects is clear — they just don't move ratings by much compared
to which network and what kind of game it is. This is the honest
statistical statement about the "player draw" and "market size"
popular-narrative claims: they're real but second-order.

## What the paper should conclude

- Q: "What drives NBA national-television ratings?"
- A: **Playoffs; then which network carries the game; then tipoff
  slot and day.** Whether big stars are on the floor and how good
  either team has been lately are real but small effects. The
  market size of the teams involved is essentially irrelevant at
  the national-telecast level — consistent with the domain claim
  that national audiences travel with the national product, not
  with local markets.
- The regular-season-only decomposition is the paper's second
  story: **when the playoff signal is removed, Network and Timing
  absorb most of the variance, and Star power emerges as a
  meaningful secondary driver**.

## Decisions

- Used `xtable` rather than `kableExtra` for LaTeX export
  (`kableExtra` not installed; `xtable` is sufficient for booktabs
  output).
- Table 1 mixes continuous and categorical rows in a single table
  for paper compactness; categorical frequencies sit in the
  "Variable" column as semicolon-separated lists.
- Table 2 reports HC3 SEs/CIs only (classical omitted from the
  paper version, since HC3 is the inference we trust — BP test in
  Phase 4 rejected homoscedasticity).
- Figures are copies with paper filenames rather than
  regenerations, so the headline `fig2_family_lmg.png` is
  bit-identical to the Phase 5 output.

## Assumptions

- Log-linear OLS is the right functional form (established and
  defended in Phase 4; residual diagnostics in `fig1`).
- LMG is the right variance decomposition (standard choice for
  correlated predictors; alternative hierarchical partitioning
  was considered in §9.2 of the plan but not pursued because it
  would carry the same qualitative message).
- HC3 is the right SE (chosen because of suspected
  heteroscedasticity by network; confirmed by BP test).

## Alternatives considered

- Separate models for P2+ and P18-49 as co-equal headline targets
  (rejected — one headline, one sensitivity, per plan §8.1).
- Hierarchical partitioning or Shapley values with a different
  reweighting (rejected — LMG already orders families with tight
  CIs; reweighting would change shares by < 1pp for the small
  families and nothing qualitative).
- Team random effects (rejected — the research question is about
  population-level drivers; observations are games not repeated
  measures on teams; adding REs would shrink the Star/Team-form
  shares toward zero without changing the ordering).

## Risks

- **Play-in games (12 rows)** were silently dropped from the
  primary fit because `season_win_pct` was NA on those rows. This
  is documented in Phase 4 Risk #5; the 12-row effect is too small
  to change any family share.
- **`post_new_deal` is nearly collinear with network**. Its
  coefficient (β = 0.067, CI (−0.003, 0.136)) is borderline
  precisely because NBC and Peacock only appear in 2025/26. A
  future season of data would resolve the sign; for now the
  correct statement is about the decomposition (Network loses
  1pp when `post_new_deal` is added), not the coefficient.
- **Three seasons of data is short.** Every result here reflects
  2023/24–2025/26; a longer panel would tighten CIs and might
  surface interaction effects (e.g., star-power × network)
  currently too weak to see.
- **National telecasts only.** We make no claim about regional /
  local-market ratings drivers, and the market-size result should
  be read in that light.

## Code quality self-assessment

- Every phase script is re-runnable end-to-end from the `R/`
  directory with `set.seed(4010)`.
- R² partitioning checks (`stopifnot(abs(sum(shares) - R²) < 1e-6)`)
  are in Phases 5, 7, 8 — caught the relaimpo single-element-group
  label quirk early.
- One known lint: `fig4_scatter_followers.png` in the paper-outputs
  copy points to the Phase 3 EDA figure rather than a purpose-built
  one; it is the right content (followers vs log(P2+)) but the
  caption is less paper-polished than the others.

## Human collaboration log

- User specified the project structure, writeup template, and the
  six predictor families in the planning phase.
- User's domain calls that shaped results:
  - Use HC3 standard errors rather than classical (Phase 4).
  - Document small-sample bugs rather than re-run prior phases
    when < 5% of rows are affected (saved to memory).
  - Add a regular-season-only decomposition with a time-in-season
    feature (Phase 8) — **this changed the paper's story** by
    surfacing the Network-dominant regular-season driver ordering.
  - Corrected my initial misread of season length (I had ~14
    weeks; the true NBA regular season is ~24.7).
- User's choice on every STOP-and-review gate was "proceed."
- No changes to the research question or the 6-family grouping
  from the plan.
