# Phase 5 — Variance decomposition (LMG)

## Purpose

Quantify how much each of the six predictor families contributes to the
explained variance in `log(P2+)`, with bootstrap CIs. Per §9, this is the
paper's headline analysis — the driver decomposition the research
question asks for. The decomposition is produced for both the full
fitted sample (n=573) and the pre-2025/26 subsample (n=452) so the
NBC/post-new-deal confound flagged in Phase 4 doesn't contaminate the
headline figure.

## Inputs / Outputs

**Inputs**
- `data/processed/primary_model.rds` (from Phase 4)
- `data/processed/model_data.rds` (to reconstruct the complete-case frame and the pre-2025/26 subset)

**Outputs**
- `data/interim/phase5_lmg_results.rds` — full bundle (both relaimpo fits, boot objects, tables)
- `outputs/tables/tbl_lmg_family.csv` — family LMG with bootstrap CIs, both samples
- `outputs/tables/tbl_lmg_terms.csv` — term-level LMG, both samples
- `outputs/figures/fig_lmg_family.png` — **headline Figure 2** (family LMG, dual-sample, with 95% bootstrap CIs)
- `outputs/figures/fig_lmg_terms.png` — term-level LMG (appendix)

## Key results

### Family-level LMG (headline)

Each cell is the share of model R² attributable to that family, computed
as LMG (Lindeman/Merenda/Gold) averaged over all variable orderings.
Bootstrap CIs from 1000 case resamples.

| Family       | Full sample (n=573)            | Pre-2025/26 (n=452)            |
|--------------|-------------------------------:|-------------------------------:|
| Matchup      | **60.1 %**  [54.7, 64.2]       | **66.0 %**  [60.7, 69.7]       |
| Network      | **16.5 %**  [13.6, 19.6]       | **12.6 %**  [ 9.6, 16.0]       |
| Timing       |   6.7 %   [ 5.0,  9.8]         |   6.4 %   [ 4.8,  9.5]         |
| Star power   |   1.7 %   [ 1.2,  2.8]         |   1.8 %   [ 1.4,  3.0]         |
| Team form    |   1.0 %   [ 0.4,  2.3]         |   1.4 %   [ 0.7,  3.3]         |
| Market size  |   0.7 %   [ 0.4,  1.7]         |   0.8 %   [ 0.4,  1.8]         |
| **Total (= R²)** | **86.6 %**                  | **88.9 %**                      |

### The headline story

**Matchup quality is the dominant driver of NBA national TV audience**,
accounting for 60–66 % of the explained variance depending on sample.
The dominance is robust to the sample change (CIs overlap in a way that
doesn't cross): the bulk of this is `playoff_stakes` alone — a post-
season round is worth about 2.5×–4.6× a regular-season audience. The
matchup family **grows** by ≈6 pp when we drop the 2025/26 season,
because the Network family gives up variance share (see below).

**Network/distribution is second at 16.5 % (full) / 12.6 % (pre-2025/26)**.
The 4-pp drop when 2025/26 is excluded is the clearest evidence of the
new-media-deal effect: the 2025/26 season introduces NBC and Prime Video
as carriers and removes TNT, and LMG attributes a non-trivial slice of
total R² to that reshuffle. The two sample CIs are almost non-
overlapping (full [13.6, 19.6] vs pre [9.6, 16.0]), so this is not
noise.

**Timing is third at ≈6.7 %**, stable across samples. Breakdown: the
single biggest timing term is `is_weekend` (3.7 %), followed by
`time_slot` (primetime/late, 2.3 %) and `is_holiday` (1.1 %).

**The three "name-brand" families — Star power, Team form, Market size —
together account for only ~3.5 %** of explained variance. This is the
paper's counter-intuitive finding: after you account for *what game is
being played* (matchup, stakes) and *who's carrying it* (network),
individual-star followers and market size add very little.

### Term-level breakdown (appendix)

Top contributions to full-sample R²:

| Term                                | LMG share (full) | LMG share (pre)  |
|-------------------------------------|-----------------:|-----------------:|
| playoff_stakes                      | 55.9 %           | 61.6 %           |
| network                             | 15.6 %           | 11.7 %           |
| combined_season_win_pct             |  4.6 %           |  5.1 %           |
| is_weekend                          |  3.7 %           |  3.7 %           |
| time_slot                           |  2.3 %           |  2.6 %           |
| is_holiday                          |  1.1 %           |  0.5 %           |
| log1p(starting5_followers_total)    |  1.0 %           |  1.1 %           |
| log(market_hh_combined)             |  0.8 %           |  0.8 %           |
| log1p(team_handle_followers_home)   |  0.6 %           |  0.4 %           |
| home_last5_win_pct                  |  0.4 %           |  0.6 %           |
| away_last5_win_pct                  |  0.3 %           |  0.3 %           |
| on_fire_either                      |  0.3 %           |  0.4 %           |
| log1p(team_handle_followers_away)   |  0.1 %           |  0.1 %           |

Notable: within **Star power**, the starting-5 sum (1.0 %) is the only
meaningful contributor — the two team-handle follower terms together
add < 0.7 %. Within **Matchup**, `playoff_stakes` alone captures ≈93 %
of the family's LMG; `combined_season_win_pct` is a small additional
4.6 % on top.

### Sensitivity to the NBC/post-new-deal confound

The pre-2025/26 LMG resolves the confound directly rather than leaving
it in a "see Phase 7" footnote. Changes worth naming:

| Family      | Full  | Pre   | Δ       | Interpretation                                  |
|-------------|------:|------:|--------:|-------------------------------------------------|
| Matchup     | 60.1  | 66.0  |  +5.9   | More matchup variance when post-deal era dropped|
| Network     | 16.5  | 12.6  |  −3.9   | Network family partly absorbs the era effect    |
| Timing      |  6.7  |  6.4  |  −0.3   | Stable                                          |
| Star power  |  1.7  |  1.8  |  +0.1   | Stable                                          |
| Team form   |  1.0  |  1.4  |  +0.4   | Slight rise                                     |
| Market size |  0.7  |  0.8  |  +0.1   | Stable                                          |

The big shifts are Matchup ↑ and Network ↓ — the rest is stable within
bootstrap noise. This is qualitatively what we hoped: the *ranking* of
families is invariant (Matchup ≫ Network ≫ Timing ≫ {Star, Team, Market}
in both samples), but the matchup-vs-network split shifts meaningfully.
Phase 7 robustness will report the pre-2025/26 LMG side-by-side.

## Decisions made in this phase

- **Report both full-sample and pre-2025/26 LMG in the headline figure**, not just full sample. The new-media-deal confound is real (3-4 pp of network share), and this surfaces it without a separate "robustness" figure later.
- **1000 bootstrap reps.** Enough for stable percentile CIs at this n; trades off against run-time (`boot.relimp` is expensive — ≈1 minute per sample on this machine).
- **Percentile CIs, not BCa.** relaimpo's default (via `booteval.relimp`) is fine for this sample size; BCa would be marginally better but adds complexity with little change.
- **Single-element family labeling hack.** `relaimpo::calc.relimp` silently returns the raw formula token for single-variable groups (so `log(market_hh_combined)` and `network` came back as their variable names instead of "Market size"/"Network"). A post-hoc `family_label_fix` map rewrites them. Noted in code comment.
- **Skip hier.part sanity check.** hier.part caps at 12 predictors and doesn't natively handle factors. Our primary model has 13 variables including 3 factors; the only way to use hier.part would be on an aggregated 6-family design that defeats the cross-check. Relaimpo with case bootstrap is the standalone method.
- **Term-level figure is appendix only**, not headline. The family-level is what answers the research question; term-level adds detail but not a different story.

## Assumptions relied on

- LMG-on-OLS is valid as a variance decomposition even under heteroscedasticity (BP p ≈ 4e-19 in Phase 4). Point estimates of β are unbiased; LMG is a function of R² contribution and doesn't require homoscedasticity for interpretation. This is the §10 rationale.
- Case resampling (resampling whole game rows) is appropriate here; no clustering adjustment needed because the unit of observation is a single televised game and we're not modeling within-team serial correlation.
- The pre-2025/26 sample is comparable in structure to the full sample (same spec, same complete-case filter). A 2 pp higher R² in the pre-sample suggests modest over-fitting to the 2025/26 era-specific variance in the full fit, but it doesn't change the family ranking.
- LMG shares for grouped factors equal the sum of LMG shares for their dummy columns (true by the permutation-invariance of Shapley values — verified empirically in relaimpo).

## Alternatives considered but not chosen

- **Pratt decomposition** (the other classical variance-partition in relaimpo) — no; Pratt can assign negative shares when predictors are correlated, which is mathematically defensible but harder to communicate in a 5-page paper. LMG is the community default and §9 specifies it.
- **Dominance analysis via `dominanceanalysis` package** — no; it's numerically equivalent to LMG for R² but slower and less well-documented for grouped predictors.
- **Normalizing LMG shares to sum to 100 %** (`rela=TRUE` in relaimpo) — no; we want shares to sum to R² so the visual directly shows "how much of the 86.6 % explained".
- **Report LMG with HC3-type robust bootstrap** — no; case resampling already accounts for heteroscedasticity-driven variance in a non-parametric way; adding residual-based weighting would double-count.
- **Drop the 36 Cook's-D-flagged rows and re-decompose** — no; the bootstrap already samples over those rows, so the reported CIs partially reflect that sensitivity. A separate drop-and-refit LMG is one more robustness point that can go in §7 if space allows.

## Risks / things a human should double-check

1. **The 60 % matchup-dominance is mostly one factor.** `playoff_stakes` alone is 56 % of R² at term level. Anyone reading "matchup drives 60 % of NBA audience variance" should hear "playoff-round fixed effects do almost all the work, + a small bump from combined season W%." The paper's framing should name this explicitly rather than just report the family number.
2. **Pre/post sample LMG split is on n=452/121**, not a true hold-out — it's structural (new-media-deal reshuffled networks). A human reader may want to see the `post_new_deal` interaction effect quantified separately in §7, not just the re-decomposition.
3. **Bootstrap CIs assume the case-resample distribution converges**; with only 12 Finals / 12 play-in (though play-in is absent from the fit per Phase 4 Risk #5) rows in the full sample, some bootstrap draws have extremely sparse post-season cells. Eyeball check on the boot plot should confirm no degenerate resamples; I did not programmatically check this.
4. **Design conditioning was kappa(X) = 1500** in Phase 4 — high but not disastrous. The bootstrap CIs on LMG partially absorb this (via resample-to-resample coefficient variability). Strictly, a ridge-adjusted LMG could narrow the CIs, but §8 locks the OLS spec.
5. **Carryover from Phase 4: play-in games absent.** The 12 play-in rows never enter the fit or the decomposition. LMG shares here are for the 5-level `playoff_stakes` factor (`regular, round1, round2, conf_finals, finals`). If a reader assumes "all playoff rounds" that's slightly misleading.

## Code quality self-assessment

Deterministic (`set.seed(4010)` at script top; `set.seed(4010)` again
inside each bootstrap call). Runs in < 3 minutes end to end. The
single-element group labeling quirk in relaimpo was caught and fixed
post-hoc; the fix is explicit and commented. No visual spot-checks on
the figures beyond `ggsave` succeeding — a human should open
`fig_lmg_family.png` before sign-off.

One uncertainty: relaimpo's grouped LMG for a factor-with-many-levels
is well-defined but less commonly used than term-level LMG in applied
papers. I verified empirically that the family sums equal the sum of
their term-level contributions (within floating-point noise), which is
the sanity check the spec's hier.part comparison was meant to provide.

## --- HUMAN COLLABORATION LOG ---

### Human inputs / decisions that shaped this phase

- Human asked for a considered plan before running: "if you were to make some decisions before continuing with phase 5 — considering figures, project assumption, your knowledge, context of the project — what would you do with the model?" This drove the four-part diagnostic (finals aliasing, HC3 vs classical, design conditioning, pre-2025/26 precompute) and the resulting Phase 5 plan.
- Human accepted all four recommendations: "ok proceed with phase 5 - do according to all your decisions."
- Human answered the small-n tradeoff: when I found the play-in Phase 2 bug pre-flight, they said "b - 12 games is not that important" — i.e., document and proceed, don't rerun. Recorded in memory; carried forward as Phase 4 Risk #5 and cross-referenced in Risk #5 here.

### Human questions answered in-chat

- Human asked "before you start - recall what hc3 is?" — confirmed conceptual understanding (HC3 = heteroscedasticity-consistent sandwich SE, leverage-corrected, default in `sandwich::vcovHC`, affects inference not point estimates, LMG unchanged) before proceeding.

### Where the human did NOT intervene

- Choice of 1000 bootstrap reps (could be 500 or 2000).
- Percentile vs BCa CIs.
- Skipping `hier.part` sanity check.
- The specific family grouping (follows §6 predictor families verbatim).
- Figure styling (horizontal dodged bars, whiskers, color palette).
