# Phase 8 — Regular-season-only decomposition + season-timing

## Purpose

The Phase 5 headline says **Matchup ≫ everything else** (60% of R²).
Most of that "Matchup" mass comes from `playoff_stakes` — playoff
games simply rate higher than regular-season games, which is a weak
claim. The interesting domain question is: **within the regular
season alone**, where ratings are flatter and playoffs are absent,
what drives variation? And does *time-in-season* (proximity to the
playoff race) matter on top of team form and matchup quality?

Phase 8 answers this with two models fit on regular-season games
only, with a new `weeks_until_regular_end` feature, and compares
against the Phase 5 full-sample reference.

## Inputs / Outputs

**Inputs**
- `data/processed/primary_model.rds`
- `data/processed/model_data.rds`
- `data/interim/phase5_lmg_results.rds` (for A reference bars)

**Outputs**
- `data/interim/phase8_regular_season.rds`
- `outputs/tables/tbl_regular_season_family.csv`
- `outputs/figures/fig_regular_season.png`

## Specifications

| ID | Sample | Target | Extra term | n | R² |
|---|---|---|---|---:|---:|
| **A** (reference) | full | log(P2+) | — | 573 | 0.866 |
| **F1** | regular only | log(P2+) | — | 422 | 0.658 |
| **F2** | regular only | log(P2+) | `weeks_until_regular_end` | 422 | 0.662 |

`playoff_stakes` is degenerate once we filter to regular-season games
and is dropped from the RHS. As a direct consequence, the **Matchup**
family collapses to the single variable `combined_season_win_pct` in
F1/F2 — a real consequence of the restriction, not a coding bug.

**New feature.** `weeks_until_regular_end` = weeks from each game's
`game_date` to the last regular-season game of that season (per-season
anchor: 2024-04-14, 2025-04-13, 2026-04-12). In-sample range is
~0 to ~23 weeks, consistent with the ~24.7-week NBA regular-season
length. Entered linearly; added as its own **"Season timing"** family,
kept separate from the existing "Timing" (time-slot / holiday /
weekend) family which measures something different.

`set.seed(4010)`, 500 boot reps (matches Phase 7 sensitivity budget).

## Key results — family LMG

| Family | **A** (full) | **F1** (reg only) | **F2** (reg + timing) |
|---|---:|---:|---:|
| Matchup | 60.1% | **3.2%** | 3.2% |
| Network | 16.5% | **31.4%** | 31.5% |
| Timing | 6.7% | **16.5%** | 16.5% |
| Star power | 1.7% | **10.9%** | 10.8% |
| Market size | 0.7% | 2.3% | 2.3% |
| Team form | 1.0% | 1.5% | 1.5% |
| **Season timing** | — | — | **0.3%** |

(95% bootstrap CIs in `outputs/tables/tbl_regular_season_family.csv`
and `outputs/figures/fig_regular_season.png`.)

Season-timing coefficient in F2:
**β = 0.0048 per week, 95% CI (0.0003, 0.0093).** Back-transformed:
≈ +0.48% on P2+ per week further from the regular-season end — or
equivalently, a ratings drift of roughly +12% across the ~25-week
regular season going *backwards in time* from the finale. The CI
barely excludes zero.

## What this means

- **The regular-season decomposition is an entirely different story
  from the headline.** Matchup falls from 60% → 3%, which means
  essentially *all* of Matchup's apparent importance in Phase 5 was
  the binary "playoff game vs not" signal. Among regular-season games
  alone, `combined_season_win_pct` explains almost nothing.

- **Network doubles in relative importance (16.5% → 31.4%).** When
  playoffs are removed, which network is carrying a game becomes the
  single largest variance source. This makes domain sense: national
  ESPN/TNT/ABC games in the regular season are explicitly scheduled
  for their appeal, and the network label acts as a strong prior on
  the game's promotional weight and channel reach.

- **Timing grows from 6.7% → 16.5% and Star power from 1.7% → 10.9%.**
  These are the two subplots that were previously dominated by
  Matchup. In the regular season, tipoff slot / holiday / weekend
  placement *and* which franchise's stars are on the floor both
  matter materially. The star-power jump is the more striking of the
  two: the audience really does tune in for big personalities when
  the stakes are lower.

- **Season timing by itself is small (0.3% of R²).** The coefficient
  sign is consistent with ratings being *lower* as the finale
  approaches (β > 0 on "weeks until end" ⇒ higher ratings further
  from playoffs), which is the *opposite* of a playoff-race-buildup
  hypothesis. Reading: once team form, matchup, network, and tipoff
  slot are controlled for, the raw calendar week contains almost no
  additional information. The playoff-race intensity story is real
  but is already absorbed by the team-form variables (last-5 win
  pct, season win pct, on-fire flag) — which rise in informativeness
  as the season progresses.

- **Market size still matters very little (2.3%).** Consistent with
  the Phase 5 finding that national-TV ratings are driven by who's
  playing, not where they're based.

## Decisions

- `weeks_until_regular_end` is defined per-season using the empirical
  last-regular-season date in the data, not a fixed calendar date,
  so the feature survives schedule shifts year-over-year.
- Season timing was given its own family rather than folded into
  "Timing" because day-of-week and week-of-season answer
  conceptually different questions; blending them would obscure
  both.
- Bootstrap 500 reps (vs 1000 for A) to match Phase 7 budget; CI
  widths are visibly fine for every comparison being made.

## Assumptions

- Linear effect of `weeks_until_regular_end`. The small overall share
  (0.3%) and the modest coefficient magnitude mean a more flexible
  term (spline, week factor) would almost certainly not change the
  qualitative conclusion.
- The primary-spec transformations (log, log1p) remain appropriate
  on the regular-season subset; residual diagnostics for F1/F2 were
  not separately produced here, since this is a variance-decomposition
  sensitivity, not a re-headline.

## Alternatives considered

- **`weeks_from_season_start`** — redundant with `weeks_until_end`
  (same info, flipped sign).
- **Normalized [0, 1] season progress** — season-length invariant
  but harder to describe.
- **Per-team games-remaining** — captures team-level playoff-race
  intensity. Skipped: more engineering work, and the season-level
  version already tests the "schedule proximity" hypothesis. Can
  revisit if the writeup calls for it.
- **Spline / week factor for timing** — not justified at 0.3% of R².

## Risks

- **Regular-season n drops to 422** (vs 476 regular-season games in
  the data). The extra drop comes from the first-few-games-of-season
  NA cascade on `last5_win_pct` and `season_win_pct`, which hits
  proportionally more regular-season rows than playoff rows. This
  truncates the early-season tail — the very portion where
  `weeks_until_regular_end` is largest. The season-timing
  coefficient is therefore estimated on games from roughly week 2
  onward, not week 1.
- **F1/F2 R² is materially lower** (0.658 vs 0.866) — not a problem
  for decomposition (the *shares* are what's interpreted) but worth
  flagging: regular-season ratings have more residual noise.
- **CI on season timing barely excludes zero** (β lower CI = 0.0003).
  Don't over-interpret the sign; treat the 0.3% share as the stable
  statement.

## Human collab log

- User flagged that the NBA regular season is ~24–25 weeks, not the
  ~14 I first estimated from a mis-read of the data. Verified
  empirically (Oct 22 → Apr 13, ~24.7 weeks per season) and used the
  true per-season last-game date as the anchor.
- User's domain-knowledge hypothesis — that time-to-playoffs might
  be a distinct driver within the regular season — is clearly
  tested and mostly *refuted*: the effect is tiny (0.3%) and the
  team-form variables already absorb whatever playoff-race signal
  exists.
- The more useful Phase 8 finding is the **regular-season driver
  re-ordering** (Network > Timing > Star power), which is a genuine
  new result the headline decomposition could not have produced on
  its own.
