# Phase 2 — Feature engineering

## Purpose

Build the six predictor families defined in 00_PROJECT_CONTEXT.md §6 on top
of the Phase 1 canonical ratings table and emit the modeling dataframe.

## Inputs / Outputs

**Inputs**
- `data/interim/ratings_clean.rds` (639 rows from Phase 1)
- `data/raw/nba_team_athlete_followership.xlsx`
- `data/raw/dmas.csv`
- `hoopR::load_nba_team_box(seasons = 2024:2026)` (team form)
- `hoopR::load_nba_player_box(seasons = 2024:2026)` (starters)

**Outputs**
- `data/processed/model_data.rds` — 639 rows × 41 cols modeling table
- `data/interim/phase2_feature_summary.rds` — diagnostics + levels

## Key results

### §6.1 Star power

| Quantity                                     | Value  |
|----------------------------------------------|-------:|
| starter rows in hoopR 2024–26                | 37,740 |
| starter rows in games we model (621 × 2 × 5) |  6,210 |
| starter rows matched to follower file        |  5,715 |
| **starter imputation rate (in scope)**       | **7.95 %** |
| distinct unmatched in-scope starters         | 99     |

Normalization to resolve hoopR ↔ SCR name mismatches: strip trailing
`(NBA)` / `(Basketball)` / `(Thunder)` disambiguators → ASCII-fold
diacritics → collapse hyphens to spaces → drop `.` `'` → lowercase → strip
generational `Jr.` / `Sr.` / `II..IV` suffixes → squish. Remaining 99 names
are genuinely absent from the Apr-2026 SCR snapshot (retired, traded out of
NBA, undrafted call-ups mid-period); imputed with their team's median
player followers. 7.95 % is under the §6.1 10 % escalation threshold.

Team-handle followers joined directly from the 30 team rows in the SCR
file; only a single one-off remap (`"Los Angeles Clippers"` → `"LA Clippers"`)
was needed to match hoopR's canonical naming.

### §6.2 Market size

Hand-coded `team → DMA name` table joined to `data/raw/dmas.csv`
(`total_tvh_hs` column, header at row 7). All 29 US-team DMAs matched
exactly. Toronto Raptors imputed with the mean of the 29 US team DMAs
(`2,606,948` TVHHs) and flagged via `team_is_canadian`. One DMA-string
correction was required vs. spec §6.2 ("Boston (Manchester), MA-NH" →
"Boston, MA (Manchester, NH)" — the Nielsen ordering).

### §6.3 Team form (leakage-safe)

For each (team, season), games are sorted chronologically and stats are
computed from **strictly prior** games within the season:

- `season_win_pct` — cumulative W / games, lagged by 1
- `last5_win_pct` — mean of the previous 5 wins; NA for games with < 5 priors
- `won_last` — outcome of previous game
- `on_fire` = 1 iff `last5_win_pct ≥ 0.6` AND `won_last == 1`
- `on_fire_either` = either team `on_fire`

### §6.4 Matchup quality

- `combined_season_win_pct` = mean of home / away season W%
- `playoff_stakes` factor levels (regular-season → finals), parsed from
  `PROGRAM` + `EPISODE` text:

| stakes       | n   |
|--------------|----:|
| regular      | 476 |
| play_in      |  12 |
| round1       |  82 |
| round2       |  27 |
| conf_finals  |  30 |
| finals       |  12 |

### §6.5 Network / distribution

Rollup combos with < 10 rows collapsed to their primary network:
`ESPN+ESPN2` (6 rows) → `ESPN`. `TNT+TRUTV` kept as its own level (16 rows).
Final levels: `ABC` (102), `ESPN` (253), `NBC` (18), `PRIME VIDEO` (35),
`TNT` (215), `TNT+TRUTV` (16). `is_broadcast` = ABC or NBC.
`post_new_deal` = `season == "2025/2026"`.

### §6.6 Timing

- `day_of_week` (7-level factor, Mon → Sun)
- `time_slot`: `early` (< 18:00), `primetime` (18:00–22:00), `late` (≥ 22:00) from `telecast_time` (ET)
- `is_holiday` = 1 for Christmas / Thanksgiving / New Year's / MLK Day (12 hand-coded dates across the 3 seasons)
- `is_weekend` = day ∈ {Sat, Sun}

### Missingness summary (modeling columns)

| Column                         | n NA | % NA |
|--------------------------------|-----:|-----:|
| home_last5_win_pct             |   65 | 10.2 |
| away_last5_win_pct             |   64 | 10.0 |
| combined_season_win_pct        |   45 |  7.0 |
| home_season_win_pct            |   44 |  6.9 |
| away_season_win_pct            |   44 |  6.9 |
| starting5_followers_* (3 cols) |   18 |  2.8 |
| all other modeling columns     |    0 |  0.0 |

Two structural causes, and nothing else: 18 rows are the documented hoopR-
unmatched set from Phase 1 (carry NA on every hoopR-derived feature);
27 additional games are the first 1–4 games of a team's season, where the
leakage-safe rolling windows haven't spun up yet. Phase 4 will drop
incomplete cases before fitting.

## Decisions made in this phase

- **Imputation scope**: the §6.1 imputation rate is measured over starters in the 621 modeled games only — not the full 37 k starter-row hoopR universe (which is dominated by non-televised G-League call-ups). The spec's 10 % threshold is binding on the modeled subset.
- **Name normalization**: strip `(disambiguator)` / hyphens / `Jr./Sr./II–IV` suffixes / diacritics before name-based joining. Without this the imputation rate hit 18 %; with it, 7.95 %.
- **Toronto handling**: mean of 29 US DMA TVHHs (2.6 M) + `team_is_canadian` flag, per spec §6.2 recommendation.
- **Network `< 10 obs` rule**: collapsed `ESPN+ESPN2` → `ESPN`; kept `TNT+TRUTV` as its own level (16 rows, over threshold).
- **`playoff_stakes` parsing**: text-match on PROGRAM / EPISODE rather than hoopR round codes — the ratings file has what we need (`PLAY IN`, `CONF FINALS`, `NBA FINALS`, round numbers) and avoids another hoopR join.
- **Leakage safety for team form**: every rolling / cumulative statistic is strictly pre-game (`lag()` or explicit window-ending-at-i−1). No feature can see its own game's outcome.

## Assumptions relied on

- Apr-2026 SCR follower counts are a stable proxy for a player's "star power" across the 2023–2026 window. Known risk (§3 caveat 1) — revisited in Phase 7 robustness.
- Team-median player-followers is a defensible fallback for the 99 missing in-scope starters (≈ 8 % of modeled starter-rows). These are mostly role players, so the median is a reasonable central tendency.
- The hand-coded `team → DMA` map is correct (29 teams verified against Nielsen strings; Toronto excluded by construction).
- `starter == TRUE` in hoopR reliably flags the actual starting 5 (Phase 0 §4.3b — 622 / 622 games had ≥ 5 starters per team).
- Team `team_winner` in hoopR team-box is a reliable W/L flag for rolling form.
- Holidays that matter for NBA TV ratings are: Christmas, Thanksgiving, New Year's Day, MLK Day (league-published emphasis games). Other US federal holidays (Memorial, Labor, Independence) fall outside the NBA season.

## Alternatives considered but not chosen

- *Impute followers with the league-wide median instead of team median* — no; team-median preserves the team-level heterogeneity that underlies the star-power signal.
- *Fuzzy-match unmatched names with `stringdist`* — no; visual inspection of the 99 residual names shows they really aren't in the SCR snapshot, not that they're spelled differently. Fuzzy match would hallucinate pairings.
- *Hand-code the "actual" new-media-deal date* — no; `post_new_deal` keyed to `season == "2025/2026"` is the cleanest boundary for the spec's robustness-check purpose.
- *Encode `playoff_stakes` as an ordinal integer* — no; keeping it as a factor lets the model choose non-monotone coefficients (e.g., Finals may jump much higher than the linear trend predicts).
- *Pull DMA TVHHs for Toronto from an external source* — no; the spec explicitly prefers mean-imputation + flag for transparency.

## Risks / things a human should double-check

1. **7.95 % starter-follower imputation is under the §6.1 cap but not trivial.** 99 distinct starters (including Jrue Holiday, Brook Lopez, Zion Williamson, Donte DiVincenzo) are simply not in the Apr-2026 SCR snapshot — treat the star-power coefficient as attenuated. Phase 7's exclude-2025/26 robustness check is the natural place to probe this.
2. **Toronto imputation at the US mean** pulls the Raptors toward an average market; if the LMG decomposition assigns much of its weight to market size, re-check whether Toronto games are disproportionately influential.
3. **Leakage safety relies on game ordering by `game_date` then `game_id`.** Double-headers and schedule oddities could reorder within a day — unlikely to matter at 1-game granularity but worth a spot-check during diagnostics.
4. **`playoff_stakes` text parsing** may mislabel rare post-season rows if PROGRAM text omits the round keyword. The 12 `finals`, 30 `conf_finals`, 27 `round2`, 82 `round1` split looks reasonable, but the 82 `round1` includes anything "POST SEASON" without a clearer tag and may absorb ambiguous rows.

## Code quality self-assessment

Deterministic (`set.seed(4010)`), single-pass. The leakage-safe form block
uses an explicit loop inside `group_by(team, season)` because
`slider::slide_dbl` would add a dependency and the loop is clear. One
uncertainty: the team-median imputation for followers and the text-parse
for `playoff_stakes` are both heuristics — defensible but not formally
validated. Phases 3 (EDA) and 4 (diagnostics) will reveal if either is
distorting the signal.

## --- HUMAN COLLABORATION LOG ---

### Human inputs / decisions that shaped this phase

- "ok - start the feature engineering - phase 2 start" → greenlit Phase 2 after Phase 1 sign-off. No scope changes.
- Phase 0 / Phase 1 decisions carried forward: `LA Clippers` (not `Los Angeles Clippers`) as canonical, `"N/A"` follower string → real NA, 639 rows accepted, ESPNU collapsed.

### Human questions answered in-chat

- (none this phase)

### Where the human did NOT intervene

- Name-normalization specifics (suffix / hyphen / diacritic / parenthesis handling).
- Choice to measure the §6.1 imputation rate on the 621-game modeling subset rather than the 37 k-row hoopR universe.
- Decision to collapse only `ESPN+ESPN2` (and not `TNT+TRUTV`) per the < 10 obs rule.
- Text-parse rules for `playoff_stakes`.
- Holiday date list.
- Fallback ordering for starter-followers (exact → normalized key → team median).
- Boston DMA-string correction vs. spec §6.2.
