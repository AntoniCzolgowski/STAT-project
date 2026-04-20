# Phase 0 — hoopR diagnostics

## Purpose

Verify that the three raw sources can be cleaned, linked to each other via
`hoopR`, and survive the §4 pre-modeling sanity checks before any feature
engineering or modeling begins.

## Inputs / Outputs

**Inputs**
- `data/raw/nba_national_ratings.csv` (986 rows × 11 cols)
- `data/raw/nba_team_athlete_followership.xlsx`, sheet `Accounts`, header at
  row index 25 (753 rows × 70 cols after skip)
- `hoopR::load_nba_team_box(seasons = 2024:2026)` — 7,548 rows over 3,774 games
- `hoopR::load_nba_player_box(seasons = 2024:2026)` — 99,797 rows

**Outputs**
- `R/utils.R` — team canonicalizer + EPISODE parser (used by every later phase)
- `R/02_hoopr_diagnostics.R` — the script that produced this report
- `R/phase0_resolve.R` — diagnostic script for the 6 items human-flagged
  on the first pass (not part of the production pipeline)
- `R/phase0_hoopr_gap_check.R` — diagnostic script verifying hoopR coverage
  on the suspect-dates range (diagnostic only)
- `data/interim/phase0_ratings_cleaned.rds` — deduped ratings with
  `home_team` / `away_team` / `hoopr_game_id` / `matched_to_hoopr` attached
- `data/interim/phase0_diag_summary.rds` — the numbers in this writeup
- `data/interim/phase0_unmatched.csv` — 17 unmatched rows (late-Mar / early-Apr
  2025, documented as an apparent hoopR data gap, not a parser issue)
- `data/interim/phase0_resolve.rds` — outputs of the resolution script

## Key results

### §4.1 ratings cleanup pipeline

| Step                                               | Rows | Δ    |
|----------------------------------------------------|-----:|-----:|
| start                                              |  986 |   —  |
| drop `NETWORK == "NBA-TV"`                         |  700 | −286 |
| collapse `NETWORK == "ESPNU"` → `ESPN`             |  700 |    0 |
| drop `SEASON TYPE == "ALL STAR WEEKEND"`           |  692 |  −8  |
| drop `SEASON TYPE == "FINALS"` (dedup w/ POST SEASON) | 680 | −12 |
| drop `EPISODE == "VARIOUS TEAMS AND TIMES"`        |  663 | −17  |
| drop rows w/ unparseable matchup                   |  663 |   0  |
| collapse duplicate (date, home, away) rows         |  640 | −23  |
| drop `DURATION < 60 min`                           |  639 |  −1  |

**Final n = 639.** 11 below the §4.1 target range of 650–900; human decision
was to accept this — the drops are well-understood (23 simulcast rollups,
17 unmatched hoopR-gap rows absorbed into the group structure). ESPNU is
collapsed into ESPN pre-dedup so the one `ESPN + ESPNU` group is treated as
a single-network game and no longer dropped as a rollup.

### §4.2 EPISODE parsing

Three separator formats observed (not one): `" AT "` (regular season),
`" VS "` / `" VS. "` (NBA Cup / In-Season Tournament), `"/"` (playoff
shorthand). Team tokens appear as nicknames (`LAKERS`), cities (`DALLAS`),
full names (`LOS ANGELES LAKERS`), and with metadata suffixes
(`-ST` simulcast, ` GM4` game-number, ` +(ESPN+)` streaming tag).

Parser after fixes:

| Status        | n   |
|---------------|----:|
| ok            | 663 |
| unknown_team  |   0 |
| unparseable   |   0 |

The previously unparseable row `LOS ANGELES/MINNESOTA` (2025-10-29) was
resolved to Lakers @ Minnesota (verified against hoopR — exactly one
candidate game involving Minnesota and either LA team within ±3 days; none
involving the Clippers). Mapping `LOS ANGELES` → Lakers is therefore correct
in this corpus (Clippers are always written `LA CLIPPERS` / `CLIPPERS`).

### §4.1b rollup dedup

23 games had multiple per-network rows for the same `(game_date, home, away)`.
Kept the row with the maximum `P2+` in each group (assumed simulcast total).
After the ESPNU→ESPN collapse, what was previously an `ESPN + ESPNU` dup
pair is now an `ESPN + ESPN` dup pair and still handled identically.

| networks in group | n groups |
|-------------------|---------:|
| TNT + TRUTV       | 16       |
| ESPN + ESPN2      |  5       |
| ESPN + ESPN       |  1       |
| ABC + ESPN        |  1       |

Duplicate network combinations align cleanly with known simulcast pairs, so
the heuristic is plausible.

### §4.3 hoopR coverage

| Match stage                           | n   |
|---------------------------------------|----:|
| Exact (date, home, away)              | 617 |
| Swapped home/away, same date          |   4 |
| Fuzzy ±3 days                         |   0 |
| Fuzzy ±3 days, swapped                |   1 |
| **Total matched**                     | **622 / 639 (97.34 %)** |
| Unmatched                             |  17 |

Threshold passed: target ≥ 95 %; halt threshold < 90 %.

### §4.3b starter availability

622 / 622 matched games have ≥ 5 `starter == TRUE` rows on both teams in the
hoopR player box. **No imputation needed at this stage.**

### §4.4 followership

| Check                                      | Observed | Expected | Status |
|--------------------------------------------|---------:|---------:|:-------|
| `Account Type == "Team"` rows              | 30       | 30       | ✓      |
| Distinct team names                        | 30       | 30       | ✓      |
| Athlete rows (raw)                         | 703      | 703      | ✓      |
| Unique `Account Name` (post-dedup)         | 571      | 571      | ✓      |
| Athletes on > 1 team-row (trades or listings) | 117   | —        | —      |
| Of those, with inconsistent non-NA Totals  |   0      |  0       | ✓      |

Resolved via the `"N/A"`-string → `NA` coercion described in §Decisions:
the lone "inconsistent" flag on the prior run was Brandon Miller, who had
two Charlotte Hornets rows with `22271` and the literal string `"N/A"`.
After coercion + per-player max, he (and every other traded / duplicately-
listed athlete) collapses to exactly one follower value.

### Unmatched ratings rows — hoopR data gap in late March / early April 2025

All 17 unmatched rows fall between 2025-03-25 and 2025-04-13 in `2024/2025`
(15 regular season, 2 post season). All parse cleanly, canonicalize to known
teams, and use the slash-format — but 15 of 17 correspond to *dates on which
hoopR has zero games for either team*, and a quick cross-reference against
hoopR's per-day game counts confirms multi-day stretches in that window
where no games were ingested at all (e.g., no games on 2025-03-23 through
2025-03-26, 2025-03-28, 2025-03-30, 2025-03-31). The Warriors' full
season-2025 game list in hoopR stops at 2025-05-14 and has the same
late-March gaps.

Conclusion: this is not a parser / matching bug — it is an apparent
upstream hoopR ingestion gap in the 2024-25 regular season. For Phase 1
these 17 rows remain in `phase0_ratings_cleaned.rds` with
`matched_to_hoopr == FALSE` and `hoopr_game_id == NA`; they will be excluded
from any analysis that joins on `hoopr_game_id`.

### Slash-format home/away convention

Of 466 slash-format matched rows (regular + post season), the first team
before `/` equals hoopR's **away** team in 461 cases (98.9 %) and hoopR's
home team in 5. The assumption "first token = away team" is therefore
reliable; the swap-match stage recovers the other ~1 %.

## Decisions made in this phase

- **Added ` VS ` / ` VS. ` as a third EPISODE separator**; only `AT` and `/` were in the spec.
- **Stripped broadcast metadata from team tokens** (`-ST`, ` GM\d+`, ` +(ESPN+)`) before canonicalization.
- **Mapped bare `NEW YORK` → New York Knicks**; Brooklyn never appears as `NEW YORK` in this corpus.
- **Mapped bare `LOS ANGELES` → Los Angeles Lakers** (post-resolution): verified against hoopR for the single `LOS ANGELES/MINNESOTA` row; Clippers never appear as bare `LOS ANGELES` in this corpus.
- **Collapsed `ESPNU` → `ESPN`** at ingest (single ESPNU row; same network family per §6.5).
- **Rollup dedup rule**: keep max-`P2+` row within each `(date, home, away)` group.
- **Widened hoopR fuzzy match window from ±1 to ±3 days** after ±1 recovered zero rows.
- **Followership `N/A` handling**: coerce the literal string `"N/A"` to real `NA`, then take per-player max `Total Followership Count (Totals)`. This collapses the one known duplicate listing (Brandon Miller) cleanly.
- **Accepted 17 unmatched rows** as an upstream hoopR data gap rather than a pipeline bug; they remain in the cleaned dataset with `matched_to_hoopr == FALSE`.

## Assumptions relied on

- In slash-format EPISODE, the first team is away and the second is home — empirically confirmed at 98.9 %.
- Nielsen-side duplicates with different networks are simulcast rollups, and the max `P2+` is the true combined total.
- hoopR `team_display_name` matches the canonical map exactly (verified for all 30 teams).
- `starter == TRUE` in hoopR player box reliably flags the actual starting five.
- For athletes on multiple team rows, the non-missing `Total Followership Count (Totals)` values agree across rows (verified post-coercion: 0 remaining inconsistencies).

## Alternatives considered but not chosen

- *Use PROGRAM text to detect rollup rows* — too heterogeneous (no consistent "rollup" marker); max-P2+ heuristic was cleaner and matched observed simulcast pairs.
- *Drop Toronto Raptors* — not needed at Phase 0; DMA handling is a Phase 2 concern.
- *Halt on the 11-row shortfall vs target range* — the halt condition in §4.3 is on hoopR match rate, not final row count; row count is a soft target, and the gap is fully explained.
- *Manual backfill of the 17 late-March / April 2025 games from the NBA schedule* — deferred: the games exist (they were played), but without hoopR box-score rows for them the starter-presence feature would be missing anyway. If Phase 2 needs them, they can be merged from an alternate source (stats.nba.com).
- *Per-player `mean`/`latest-team` rule for inconsistent Totals* — unnecessary after the `N/A`-coercion fix eliminated every remaining inconsistency.

## Risks / things a human should double-check

1. **17 unmatched rows correspond to an apparent hoopR gap in the 2024-25 regular season (2025-03-25 to 2025-04-13).** Accepted for Phase 0. If Phase 1 / 2 needs these games, they'll have to be backfilled from an alternate source; the ratings rows themselves are clean.
2. **`LOS ANGELES` → Lakers mapping is corpus-specific** — safe today (Clippers always written "LA CLIPPERS"), but add a guard if the input file ever changes.
3. **Slash-format swap rate is 1.1 %** — small but non-zero; the matching stage handles it, but Phase 1 should always trust hoopR's `team_home_away` over the ratings parser's orientation.
4. **`ESPNU` collapse is irreversible in the cleaned RDS** — if network-level modeling ever needs the distinction, re-derive from the raw file.

## Code quality self-assessment

The canonicalizer and parser live in `R/utils.R` and are vectorized + tested
implicitly by the diagnostics run. The diagnostics script is deterministic
(`set.seed(4010)`), idempotent, and writes all decision-relevant numbers to
an RDS the writeup pulls from. Remaining uncertainty: the fuzzy-match block
is slightly over-engineered for the gain it produced (5 extra matches from
swap/fuzzy combined); fine to leave, but a simpler set-based sig match
would be equivalent. Not worth refactoring before Phase 1.

## --- HUMAN COLLABORATION LOG ---

### Human inputs / decisions that shaped this phase

- "Execute Phase 0 only per Section 17. Stop after producing writeups/02_hoopr_diagnostics.md" → scoped the work to diagnostics + writeup; no cleaning / modeling started.
- "Create a trial R file first that I will execute to check if its working" → confirmed the VSCode R toolchain before installing heavy packages.
- "All writeups, plans, contexts, code, comments — EVERYTHING in English" → all artifacts (this writeup, R comments, filenames) written in English even when chat is Polish.
- Second-pass resolutions on 6 flagged items (below).

### Human decisions on the 6 flagged items (second pass)

1. **17 unmatched rows** → "try to check by hand". Verified they are a hoopR data gap (15 / 17 fall on dates with zero hoopR games involving either team). Kept in dataset with `matched_to_hoopr == FALSE`.
2. **ESPNU (1 row)** → "it's ESPN". Collapsed at ingest.
3. **Final n = 638 vs target 650–900** → "it's fine". Shortfall documented, not flagged.
4. **Traded player with inconsistent Totals** → "explain and propose the best solution". Root cause: Brandon Miller has two *Charlotte Hornets* rows (not a trade — a duplicate listing), one with `22271`, one with the literal string `"N/A"`. Solution: coerce `"N/A"` → `NA`, take per-player max. Result: 0 inconsistencies remain, unique athletes = 571 exactly.
5. **`LOS ANGELES/MINNESOTA`** → "check online and map". hoopR confirms Lakers @ Minnesota on 2025-10-29; Clippers never played Minnesota within ±3 days. Added `LOS ANGELES` → Lakers to the canonical map.
6. **Slash-format convention** → "check in hoopR". Confirmed: first token = away in 461 / 466 matched rows (98.9 %). Parser assumption correct.

### Human questions answered in-chat

- Q: Is the setup good? — A: Yes; R 4.5.2 + REditorSupport.r + `languageserver` all wired; only `janitor` and `hoopR` left to install.

### Where the human did NOT intervene

- Choice of separator patterns (`AT` / `VS` / `/`) and the token-metadata strip rules.
- The rollup dedup heuristic (max `P2+` within `(date, home, away)`).
- Mapping `NEW YORK` → Knicks.
- Widening the fuzzy hoopR match from ±1 to ±3 days.
- Folder layout under `R/`, `data/interim/`, `writeups/` per §14.1.
- The `"N/A"`-string coercion rule for follower counts (proposed as the best fix and accepted implicitly).
