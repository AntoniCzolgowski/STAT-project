# NBA National TV Ratings — Project Context for Claude Code

> **Audience**: Claude Code (in VS Code) executing the analysis pipeline in R.
> **Prior collaborator**: Claude Opus 4.7 (web chat) — framed the project and produced this handoff doc.
> **Human**: will evaluate every decision. This doc, plus the 8 intermediate MD writeups you produce, become the raw material for the final 5–8 page paper.

---

## 1. Project overview

- **Course**: University of Colorado Boulder, STAT 4010/5010
- **Project option**: #2 — "Use and evaluate AI for data science tools"
- **Thesis of the assignment**: AI performs the analysis; human critically evaluates it
- **Deliverables**:
  - Full R analysis pipeline (this project)
  - 8 intermediate MD writeups (one per phase — see §14)
  - Final combined PDF report + 5–8 page paper + 5-min video presentation
- **AI evaluation is mandatory** — per the syllabus, the human must critique: model appropriateness, assumption identification, code correctness, interpretation quality, conclusion strength. Every MD writeup must be structured to make these evaluations easy (see §14 template).

---

## 2. Research question

**"What drives NBA national television ratings?"**

- Direction chosen: **E — horse-race / driver decomposition**
- Approach: fit one unified log-linear GLM of `P2+` on 6 families of predictors, then decompose R² across families using **LMG (Lindeman-Merenda-Gold / Shapley)** variance decomposition with bootstrap CIs
- Headline deliverable: a ranked chart of driver-family importance with uncertainty bounds
- Why this direction: broad, rigorous, hits every course tool (regression, GLM framing, ANOVA-style decomposition, bootstrap, diagnostics), supports clean "what matters most" narrative, scoped for 5–8 pages

### The 6 driver families

| # | Family | What it captures |
|---|--------|------------------|
| 1 | Star power | Social followers on the floor (starting 5, injury-adjusted) + team-handle followers |
| 2 | Market size | Combined TV household reach of the two teams' DMAs |
| 3 | Team form | Recent performance (last-5, on-fire flag, season W%) |
| 4 | Matchup quality | Combined season W%, playoff stakes |
| 5 | Network / distribution | Which network; mainstream-broadcast status; pre/post new media deal |
| 6 | Timing | Day of week, time slot, holidays, weekend |

---

## 3. Data inventory

### Provided (in `/mnt/project/` or comparable)

| File | Content | Shape | Notes |
|---|---|---|---|
| `nba_national_ratings.csv` | Nielsen national telecast ratings | 986 rows × 11 cols | Key cols: SEASON, SEASON TYPE, NETWORK, PROGRAM, EPISODE, DATE, TELECAST TIME, DURATION (MINS), P2+, P18-49. P2+/P18-49 in thousands. |
| `dmas.csv` | Designated Market Area demographics | 210 DMAs | Key col: `Total TVHHs`. Other cols can be summed into demo segments. Messy header — real headers are on row 7 (0-indexed). Population as of Jan 2026. |
| `nba_team_athlete_followership.xlsx` | Talkwalker SCR report: follower + engagement by account | 753 rows (sheet: `Accounts`) | Real header at row index 25. Account Type: Athlete (703), Team (30), Community (20 — drop). Traded players appear once per team; same totals — use `Total Followership Count (Totals)`. Report window: Apr 25 2025 – Apr 17 2026. |

### To fetch (via R package `hoopR`)

- Full schedules + final scores for seasons 2023/24, 2024/25, 2025/26
- Player-level box scores (to identify starters + minutes played per game)
- Team game logs (to compute running W-L records)

`hoopR` is the R wrapper for sportsdataverse/ESPN + NBA Stats endpoints. No API key required. Typical functions: `load_nba_team_box()`, `load_nba_player_box()`, `nba_schedule()`.

### Known data caveats (must acknowledge in writeups)

1. **Follower snapshot is end-of-period**, not historical. Applying ~Apr 2026 follower counts to Oct 2023 games introduces measurement error. Mitigated by: (a) relative ordering of "who's a star" is stable year-to-year; (b) acknowledging the caveat explicitly; (c) robustness check excluding 2025/26.
2. **2025/26 is incomplete** — regular season through Apr 12, 2026; no playoffs yet.
3. **FINALS double-count**: all 12 FINALS rows appear again as POST SEASON rows. Dedup before modeling.
4. **Roll-up rows**: some telecasts are simulcast combined-audience rows (e.g., "ABC w/ ESPN rollup"). When a rollup exists for a game, it IS the canonical total — use it in place of individual-channel rows.
5. **NBA-TV excluded** (286 rows). Reason: cable specialty channel requiring specific subscription; audience is pre-selected superfans; games selected for NBA-TV are systematically the non-marquee leftovers. Mixing with ABC/NBC/Prime/ESPN would confound network effects with consumption-context differences. Research question is about mainstream national broadcasts.

---

## 4. Phase 0 — Pre-modeling diagnostics (STOP AND REPORT)

Before feature engineering or modeling, execute these checks and write `02_hoopr_diagnostics.md`. If any fail hard, halt and ask the human.

### 4.1 Ratings data cleanup (confirm counts at each step)

| Step | Expected effect |
|---|---|
| Start | 986 rows |
| Drop NBA-TV | ≈700 rows |
| Drop All-Star Weekend rows (SEASON TYPE == `ALL STAR WEEKEND`) | ≈692 rows |
| Drop FINALS season-type rows (dedup with POST SEASON) | ≈680 rows |
| For each game, when a rollup row exists use it and drop the per-network row(s) for that game | depends; log count |
| Filter DURATION ≥ 60 min | drops short/fragment telecasts |
| **Final count target**: 650–900 observations | Flag if outside this range |

### 4.2 Matchup parsing from EPISODE

- `EPISODE` is usually `"AWAY AT HOME"` (e.g., `"MAVERICKS AT CELTICS"`, `"NY KNICKS AT 76'ERS"`).
- Some All-Star rows are non-standard (already dropped above).
- Build a canonical team-name lookup mapping all variants ("76'ERS" → "Philadelphia 76ers", "NY KNICKS" → "New York Knicks", "LA CLIPPERS" → "Los Angeles Clippers", etc.) that matches:
  - `hoopR` team names
  - `nba_team_athlete_followership.xlsx` `Team Name` column
  - Team → DMA lookup (hand-coded, §6.2)
- **Any EPISODE that can't be parsed into (away, home) pair → log it, drop it, flag the drop rate**

### 4.3 hoopR coverage check

- For each cleaned ratings row, attempt to match to a `hoopR` game record using `(game_date, home_team, away_team)`
- Tolerate ±1 day on date (late tip-offs can cross midnight)
- **Target match rate: ≥ 95%**. If < 90%, halt and escalate.
- For matched games, confirm: box score exists, ≥ 5 starters on each team
- Produce: an unmatched-games table for inspection

### 4.4 Social follower file cleanup

- Drop Account Type == `Community` (20 rows)
- Confirm all 30 NBA teams have exactly one `Team` row — flag any missing
- Aggregate athletes: for each player, `Total Followership Count (Totals)` is identical across their team rows (it's a player-level metric). Use `distinct(Account Name, Total Followership Count (Totals))` — 571 unique athletes expected.
- Build `player_name → total_followers` dict (sum of FB+IG+X+YT already in `Totals` column per SCR)
- Build `team_name → team_handle_followers` dict

### 4.5 Stop and report

Write `02_hoopr_diagnostics.md`. If all green, proceed. Otherwise escalate before any further work.

---

## 5. Phase 1 — Data cleaning rules (produce `01_data_cleanup.md`)

Apply the dedup pipeline from §4.1 in R using `dplyr`. Each step gets a tidy before/after row count in the MD writeup. No silent drops — every row removed gets a reason tag.

### Canonical row-level schema after Phase 1

| Column | Type | Source |
|---|---|---|
| `game_id` | string | derived: `yyyy-mm-dd_AWAY_HOME` |
| `game_date` | date | DATE |
| `home_team`, `away_team` | string (canonical) | parsed from EPISODE |
| `season` | factor | SEASON |
| `season_type` | factor | `REGULAR SEASON` / `POST SEASON` |
| `network` | factor | NETWORK (or concatenation for rollups, e.g., `"ABC+ESPN"`) |
| `duration_min` | int | DURATION (MINS) |
| `telecast_time` | time | TELECAST TIME |
| `p2_plus` | int | P2+ |
| `p18_49` | int | P18-49 |

---

## 6. Phase 2 — Feature engineering (produce `03_feature_engineering.md`)

Every variable below must be documented in `03_feature_engineering.md` with: formula, source, intended family, assumptions.

### 6.1 Star power

- `starting5_followers_home` = Σ total followers of the 5 actual starters on the home team for that game (source: hoopR player box score, filtered to starter flag AND minutes > 0)
- `starting5_followers_away` = same for away team
- `starting5_followers_total` = sum of the two
- `team_handle_followers_home`, `team_handle_followers_away` (from SCR file)
- If a starter can't be matched to the follower file (e.g., rookie not in the snapshot), assign the team's median player followership as imputation. Log the imputation rate — if > 10%, escalate.

### 6.2 Market size — team → DMA lookup (hand-code this table)

Map each of the 30 NBA teams to its primary DMA code, then join to `dmas.csv` for `Total TVHHs`. Canonical mapping (verify in `03_feature_engineering.md`):

| Team | DMA |
|---|---|
| Atlanta Hawks | Atlanta |
| Boston Celtics | Boston (Manchester) |
| Brooklyn Nets | New York |
| Charlotte Hornets | Charlotte |
| Chicago Bulls | Chicago |
| Cleveland Cavaliers | Cleveland-Akron (Canton) |
| Dallas Mavericks | Dallas-Ft. Worth |
| Denver Nuggets | Denver |
| Detroit Pistons | Detroit |
| Golden State Warriors | San Francisco-Oakland-San Jose |
| Houston Rockets | Houston |
| Indiana Pacers | Indianapolis |
| LA Clippers | Los Angeles |
| Los Angeles Lakers | Los Angeles |
| Memphis Grizzlies | Memphis |
| Miami Heat | Miami-Ft. Lauderdale |
| Milwaukee Bucks | Milwaukee |
| Minnesota Timberwolves | Minneapolis-St. Paul |
| New Orleans Pelicans | New Orleans |
| New York Knicks | New York |
| Oklahoma City Thunder | Oklahoma City |
| Orlando Magic | Orlando-Daytona Beach-Melbourne |
| Philadelphia 76ers | Philadelphia |
| Phoenix Suns | Phoenix |
| Portland Trail Blazers | Portland, OR |
| Sacramento Kings | Sacramento-Stockton-Modesto |
| San Antonio Spurs | San Antonio |
| Toronto Raptors | Toronto (or use "national Canada" proxy — flag for human review) |
| Utah Jazz | Salt Lake City |
| Washington Wizards | Washington, DC (Hagerstown) |

**Toronto handling**: the DMA file is US-only. Use one of: (a) NY DMA as a placeholder (bad), (b) an externally-sourced Toronto TVHH number, (c) exclude Toronto games, (d) create a `team_is_canadian` flag. **Recommendation**: create the flag, impute Toronto with the mean of the 29 US team DMAs, document clearly.

Variables:
- `market_hh_home` = home team DMA `Total TVHHs`
- `market_hh_away` = away team DMA `Total TVHHs`
- `market_hh_combined` = sum (primary feature)

### 6.3 Team form

For each game `g` and team `t`, compute from hoopR game logs **using only games strictly before `g`**:

- `season_win_pct_t` = W/(W+L) season-to-date (NA for first game of season)
- `last5_win_pct_t` = wins in the team's previous 5 games / 5 (NA if fewer than 5 prior games)
- `won_last_t` = binary, 1 if won previous game
- `on_fire_t` = binary, 1 if `last5_win_pct_t ≥ 0.6 AND won_last_t == 1`
- `on_fire_either` = 1 if either team is on fire

### 6.4 Matchup quality

- `combined_season_win_pct` = mean of home and away season W%
- `playoff_stakes` = factor: `regular`, `play_in`, `round1`, `round2`, `conf_finals`, `finals` (derive from SEASON TYPE + PROGRAM text patterns)

### 6.5 Network & distribution

- `network` = factor: `ABC`, `ESPN`, `ESPN2`, `TRUTV`, `TNT`, `NBC`, `PRIME_VIDEO`, plus combined rollup levels like `ABC+ESPN`. If any rollup level has <10 observations, collapse to the primary network.
- `is_broadcast` = 1 if network includes `ABC` or `NBC` (over-the-air)
- `post_new_deal` = 1 if season == `2025/2026`

### 6.6 Timing

- `day_of_week` = factor (Mon–Sun)
- `time_slot` = factor: `early` (<18:00), `primetime` (18:00–22:00), `late` (≥22:00), derived from TELECAST TIME in ET
- `is_holiday` = 1 for Christmas, Thanksgiving, MLK Day, New Year's Day (hand-coded dates for the 3 seasons)
- `is_weekend` = 1 if day_of_week in (Sat, Sun)

---

## 7. Phase 3 — Exploratory data analysis (produce `04_eda.md`)

Keep it short — the paper doesn't need pages of EDA. Minimum:

- Summary table: mean/SD/median/range for every numeric feature and target
- Histogram of `P2+` and `log(P2+)` — show why log is the right scale
- Boxplot of `log(P2+)` by network (to check network-effect plausibility)
- Scatter of `log(P2+)` vs. `log(starting5_followers_total)` — preview of main relationship
- Correlation heatmap among continuous predictors — flag multicollinearity risks
- Missing-data summary across all engineered features

---

## 8. Phase 4 — Primary model (produce `05_model_fitting.md`)

### 8.1 Specification

```r
primary_model <- lm(
  log(p2_plus) ~ 
    # Star power
    log1p(starting5_followers_total) +
    log1p(team_handle_followers_home) +
    log1p(team_handle_followers_away) +
    
    # Market size
    log(market_hh_combined) +
    
    # Team form
    home_last5_win_pct + 
    away_last5_win_pct +
    on_fire_either +
    
    # Matchup
    combined_season_win_pct +
    playoff_stakes +
    
    # Network
    network +
    
    # Timing
    time_slot +
    is_holiday +
    is_weekend,
  data = df_model
)
```

### 8.2 Assumptions being made (document all)

1. Errors approximately Gaussian on log scale
2. Linearity of log-transformed response in (transformed) predictors
3. Homoscedastic residuals
4. Observations are independent (each game once, after dedup)
5. No severe multicollinearity
6. `log1p(followers)` is a reasonable functional form (handles zero-follower edge cases and compresses the fat right tail)

### 8.3 Report in `05_model_fitting.md`

- Full coefficient table with 95% CIs (use `confint()` or `broom::tidy(conf.int=TRUE)`)
- R², adjusted R²
- Overall F-statistic

---

## 9. Phase 5 — Variance decomposition (produce `06_decomposition.md`)

### 9.1 Primary: LMG via `relaimpo`

```r
library(relaimpo)
lmg <- calc.relimp(primary_model, type = "lmg", rela = FALSE)
lmg_boot <- boot.relimp(primary_model, b = 1000, type = "lmg", 
                        rank = TRUE, diff = TRUE, rela = FALSE)
lmg_ci <- booteval.relimp(lmg_boot, level = 0.95)
```

Then group predictor-level LMG weights into the 6 families and sum within family. Bootstrap CIs propagate by resampling (do the grouping inside the bootstrap loop, not after).

### 9.2 Sanity check: hierarchical partitioning

```r
library(hier.part)
hp <- hier.part(log(df_model$p2_plus), X_matrix, family = "gaussian", gof = "Rsqu")
```

Report:
- Unique vs. joint contribution per variable
- Whether family ranking agrees with LMG
- Specifically interesting: how much of star power's importance is unique vs. shared with market size (there's a big-market-teams-have-bigger-stars confound — this quantifies it)

### 9.3 Outputs

- **Figure 2 (headline)**: horizontal bar chart of 6 families by % of R² explained, with bootstrap 95% CI whiskers
- **Figure 3 (supporting)**: variable-level LMG importance (top 10 predictors)
- **Table in `06_decomposition.md`**: full LMG decomposition with CIs for every predictor and family

---

## 10. Phase 6 — Model diagnostics (produce part of `05_model_fitting.md`)

Run every diagnostic. For each, report the test/plot, assumption being tested, result, decision.

| Check | Tool | Pass criterion | If fails |
|---|---|---|---|
| Residual linearity | `plot(model, which=1)` | No systematic pattern | Consider polynomial or interaction terms |
| Normality of residuals | `plot(model, which=2)` (Q-Q plot) | Roughly linear | Visual only; n=700 makes formal tests reject trivially |
| Homoscedasticity | `plot(model, which=3)` + `lmtest::bptest()` | BP p > 0.05 preferred but not required | Use robust SEs (`sandwich::vcovHC`) — report them alongside |
| Influence | `plot(model, which=4,5)`, Cook's D | No point with D > 4/n | Fit with and without flagged points; report delta |
| Multicollinearity | `car::vif()` | GVIF^(1/(2×df)) < 2.5 ideal, < 5 acceptable | Drop or combine redundant predictors — document |

If homoscedasticity fails, we still report LMG from OLS, but cite robust SEs for the coefficient table. LMG is a variance-decomposition of R² and is not invalidated by heteroscedasticity.

---

## 11. Phase 7 — Robustness checks (produce `07_robustness.md`)

Exactly two. Each a single paragraph plus one small table.

### 11.1 Alternative target: `log(P18-49)`

- Re-fit primary model swapping `log(p2_plus) → log(p18_49)`
- Re-run LMG decomposition
- Compare family rankings side by side
- Expected finding: star power ranks higher in the demo audience; matchup stakes may rank lower
- If rankings substantially flip, that IS a finding — discuss

### 11.2 Exclude 2025/26 season

- Re-fit on seasons 2023/24 + 2024/25 only
- Re-run LMG decomposition
- Confirms the new-media-deal regime change isn't distorting the family importance ordering
- If pre-new-deal results agree with full-sample results: good, sample pooling is justified

---

## 12. Phase 8 — Outputs for paper

Save to `outputs/figures/` and `outputs/tables/`. All tables as both `.csv` and LaTeX (`kableExtra::kable()` or `xtable`) for easy paper embedding.

| # | Artifact | File |
|---|---|---|
| Table 1 | Descriptive stats for all variables | `tbl1_descriptive_stats.*` |
| Table 2 | Full regression coefficients with 95% CIs | `tbl2_regression_coefficients.*` |
| Table 3 | Robustness comparison (primary vs. P18-49 vs. pre-new-deal) | `tbl3_robustness.*` |
| Figure 1 | Model diagnostics panel (residuals, Q-Q, scale-loc, Cook's) | `fig1_diagnostics.png` |
| Figure 2 | **Headline**: family-level LMG with bootstrap CIs | `fig2_family_lmg.png` |
| Figure 3 | Variable-level LMG (top 10) | `fig3_variable_lmg.png` |
| Figure 4 (optional) | EDA scatter: `log(P2+)` vs. `log(starting5_followers)` | `fig4_scatter_followers.png` |

---

## 13. Human evaluation hooks (required by project rubric)

Every intermediate MD writeup must include these 5 sections at the end — they're what the human evaluator critiques:

1. **Decisions made in this phase** — list, bullet form
2. **Assumptions relied on** — explicit
3. **Alternatives considered but not chosen** — and why not
4. **Risks / things a human should double-check**
5. **Code quality self-assessment** — did the code do what the prose claims? Any places I'm uncertain?

This maps to the syllabus' required evaluations:
- (a) Models appropriate to the problem? — §5 of writeup
- (b) Assumptions properly identified? — §2
- (c) Generated code correct? — §5
- (d) Interpretations appropriate? — flagged in §4
- (e) Conclusions strong? — covered in `08_conclusions.md`

---

## 14. File structure & writeup protocol

### 14.1 R project layout

```
project_root/
  00_PROJECT_CONTEXT.md          # this document
  R/
    01_data_cleanup.R
    02_hoopr_diagnostics.R
    03_feature_engineering.R
    04_eda.R
    05_model_fitting.R
    06_decomposition.R
    07_robustness.R
    utils.R                      # helpers: team-name normalizer, DMA join, etc.
  writeups/
    01_data_cleanup.md
    02_hoopr_diagnostics.md
    03_feature_engineering.md
    04_eda.md
    05_model_fitting.md
    06_decomposition.md
    07_robustness.md
    08_conclusions.md
  data/
    raw/                         # provided files, untouched
    interim/                     # cleaned/engineered (gitignored)
    processed/                   # final modeling dataframe (one .rds)
  outputs/
    figures/
    tables/
  renv.lock                      # pinned package versions
  .gitignore                     # ignores data/interim, data/processed, .Rhistory
```

### 14.2 MD writeup template (use for all 8)

```markdown
# Phase N — [Name]

## Purpose
One-paragraph scope.

## Inputs
- Files / objects consumed

## Steps
Numbered, concise. Each step links to the relevant R function/line.

## Outputs
- Files / objects produced

## Key numbers / results
Tables or figures inline.

## --- HUMAN EVALUATION SECTIONS ---

### Decisions made in this phase
- ...

### Assumptions relied on
- ...

### Alternatives considered but not chosen
- ... and why

### Risks / things a human should double-check
- ...

### Code quality self-assessment
- What worked, what was uncertain, any smells
```

### 14.3 Final combination step

After all 8 phase writeups are complete, produce:
- `FINAL_REPORT.md` — concatenation of `00_PROJECT_CONTEXT.md` + the 8 writeups, with a short meta-preamble
- Convert to PDF via `rmarkdown::render()` or `pandoc`. Keep PDF in `outputs/`.

---

## 15. Technical standards

### 15.1 R packages

Pin with `renv`. Primary packages:

- Data: `tidyverse`, `lubridate`, `janitor`, `readxl`
- NBA: `hoopR`
- Modeling: `broom`, `car`, `lmtest`, `sandwich`
- Decomposition: `relaimpo`, `hier.part`
- Tables: `gt` or `kableExtra`, `xtable`
- Plots: `ggplot2`, `patchwork`
- Reporting: `rmarkdown`, `knitr`

### 15.2 Reproducibility

- Set `set.seed(4010)` at the top of every script that involves randomness (bootstrap, CV)
- All file paths relative to project root — use `here::here()`
- Session info saved: `sessionInfo()` written to `outputs/session_info.txt` at end of pipeline

### 15.3 Style

- `tidyverse` style (`styler` + `lintr`)
- Prefer pipes (`|>` or `%>%`) for readability
- Every function: roxygen-style docstring with `@param` and `@return`
- No `setwd()`, no `install.packages()` inside scripts (use `renv::restore()`)

### 15.4 Output size discipline

- Paper is 5–8 pages — do not generate 40-page appendices
- Each phase writeup: target 1–2 pages when rendered
- Headline chart (Figure 2) is the one figure that must be perfect

---

## 16. Summary of decisions already locked (do not revisit without human)

| Decision | Value | Rationale |
|---|---|---|
| Research direction | E — driver decomposition | Novel, rigorous, fits 5–8 pages, uses all course tools |
| Target | `log(P2+)` primary; `log(P18-49)` robustness | Log handles right skew; P2+ is the total-audience measure |
| Unit of analysis | One game (deduped) | Avoids double-counting from rollups and FINALS/POST SEASON overlap |
| NBA-TV | Excluded | Cable specialty channel, superfan audience, confounds network effect |
| All-Star Weekend | Excluded | Non-standard events, no starting 5 / form |
| Duration filter | ≥ 60 min | Removes highlight/fragment telecasts |
| Decomposition method | LMG primary, hier.part sanity check | LMG = ANOVA-correct for correlated regressors; hier.part adds unique-vs-shared color |
| Bootstrap | B = 1000, percentile CIs | Standard in `relaimpo` |
| Data source for form/lineups | `hoopR` (with coverage diagnostics first) | Single R package, no auth, fast bulk loads |
| Toronto Raptors DMA | Flag + impute with US-team mean | DMA file is US-only; flagging is more honest than dropping |
| Robustness checks | Exactly 2: P18-49 target, pre-new-deal subsample | Paper-length discipline |

---

## 17. First instruction for Claude Code

1. Read this entire document
2. Create the R project skeleton per §14.1
3. Install packages via `renv`
4. Execute **Phase 0 diagnostics only**
5. Write `02_hoopr_diagnostics.md`
6. **STOP**. Show the human the diagnostic report. Do not proceed to cleaning/feature engineering/modeling until the human explicitly approves.

This checkpoint is the first place the human exercises oversight. Don't skip it.
