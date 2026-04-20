# Phase 1 — Data cleanup

## Purpose

Apply the cleaning rules validated in Phase 0 as a production pipeline and
emit the canonical one-row-per-game ratings table the rest of the analysis
will join on. No silent drops: every removed raw row is tagged with a reason.

## Inputs / Outputs

**Inputs**
- `data/raw/nba_national_ratings.csv` (986 rows)
- `hoopR::load_nba_team_box(seasons = 2024:2026)` (for `hoopr_game_id` attach)

**Outputs**
- `data/interim/ratings_clean.rds` — canonical modeling table (639 rows)
- `data/interim/phase1_drops.csv` — every dropped raw row + reason tag
- `data/interim/phase1_step_counts.csv` — before/after row counts per step

## Key results

### Step counts

| Step                       | Rows |  Δ   |
|----------------------------|-----:|-----:|
| start                      |  986 |   —  |
| drop NBA-TV                |  700 | −286 |
| collapse ESPNU → ESPN      |  700 |    0 |
| drop ALL STAR WEEKEND      |  692 |   −8 |
| drop FINALS (dup of POST)  |  680 |  −12 |
| drop VARIOUS TEAMS         |  663 |  −17 |
| drop unparseable EPISODE   |  663 |    0 |
| rollup dedup (max P2+)     |  640 |  −23 |
| duration ≥ 60 min          |  639 |   −1 |

**Final n = 639.** 11 below the §4.1 target range of 650–900 — accepted
in Phase 0 (gap is fully explained by rollup dedup + one short-duration
drop; no hidden filtering).

### Drop reasons

| Step | Reason | n |
|------|--------|---:|
| 01_nba_tv   | network == NBA-TV (spec: cable, excluded) | 286 |
| 07_rollup   | rollup dedup: lower-P2+ per-network row within group | 23 |
| 05_various  | episode == VARIOUS TEAMS AND TIMES | 17 |
| 04_finals   | season_type == FINALS (dup of POST SEASON) | 12 |
| 03_all_star | season_type == ALL STAR WEEKEND | 8 |
| 08_duration | duration_mins < 60 | 1 |

### hoopR game_id attach

Using exact + swap matching (fuzzy ±3d omitted here — it added a single
row in Phase 0; not worth the audit complexity in production):
**621 / 639 = 97.18 % matched**, above the 95 % target. The 18 unmatched
rows are the same 17 documented hoopR-gap rows from Phase 0 plus the
single fuzzy-±3d match we chose not to carry across.

### Canonical schema emitted

| Column            | Type    | Source / derivation                              |
|-------------------|---------|--------------------------------------------------|
| `game_id`         | chr     | `"YYYY-MM-DD_AWAY_HOME"` (spaces removed)        |
| `game_date`       | Date    | `mdy(DATE)`                                      |
| `home_team`       | factor  | parsed EPISODE, canonicalized                    |
| `away_team`       | factor  | parsed EPISODE, canonicalized                    |
| `season`          | factor  | raw `SEASON` (3 levels)                          |
| `season_type`     | factor  | `REGULAR SEASON` / `POST SEASON`                 |
| `network`         | factor  | `network_combined` (rollup concatenation if any) |
| `duration_min`    | int     | raw DURATION (MINS)                              |
| `telecast_time`   | hms     | raw TELECAST TIME                                |
| `p2_plus`         | int     | raw P2+                                          |
| `p18_49`          | int     | raw P18-49                                       |
| `hoopr_game_id`   | int64   | joined from hoopR team box (NA for 18 rows)      |
| `matched_to_hoopr`| lgl     | `!is.na(hoopr_game_id)`                          |
| `raw_row_id`      | int     | stable row id from the raw file (for audit)     |

`game_id` is unique across all 639 rows (checked via `stopifnot`).

## Decisions made in this phase

- **Drop tagging, not silent filtering.** Every removed raw row is written to `phase1_drops.csv` with a reason string — the counts above are reproducible from that file alone.
- **ESPNU folded into ESPN at step 2** (before rollup dedup) so any latent ESPN+ESPNU simulcast is treated as a same-network duplicate, not a multi-network rollup.
- **Rollup dedup uses max P2+ within `(date, home, away)`**; the concatenated `network_combined` is retained (factor level) for any downstream "which networks simulcast this game" analysis.
- **Kept fuzzy ±3d matching out of production** — adds one row at the cost of a more complex audit trail; exact+swap covers 97.18 %.
- **`matched_to_hoopr == FALSE` rows are kept in the canonical table**, not dropped. Feature-engineering code in Phase 2 is responsible for skipping them when it needs hoopR joins.

## Assumptions relied on

- NBA-TV rows are correctly labeled in the `NETWORK` column (no mis-coded ABC/ESPN games tagged as NBA-TV).
- ESPNU is operationally equivalent to ESPN for modeling purposes (same network family, same distribution tier).
- Within a `(date, home, away)` duplicate group, the max-P2+ row is the simulcast combined total. Observed combos (TNT+TRUTV, ESPN+ESPN2, ABC+ESPN) match known league simulcast pairs.
- FINALS rows are exact duplicates of the corresponding POST SEASON rows (verified in Phase 0 — 12 rows dropped cleanly).
- `mdy(DATE)` parses every raw row without NAs (checked via `stopifnot`).

## Alternatives considered but not chosen

- *Drop unmatched-to-hoopR rows here* — no; they have clean ratings data (network, time, P2+), and Phase 2 features that don't need hoopR (timing, network) are still computable. Let the feature layer decide.
- *Sum P2+ within rollup groups instead of taking max* — no; the max rule matched Phase 0's assumption that the max row IS the combined total, and summing would double-count in cases where one of the duplicate rows is already the rollup.
- *Emit as a tibble of characters and convert to factor downstream* — no; factors belong in the canonical table so every downstream script sees the same level orderings.
- *Carry every raw Nielsen column forward* — no; this stage emits the modeling schema, not a verbose mirror.

## Risks / things a human should double-check

1. **18 rows with `matched_to_hoopr == FALSE`** — ratings are clean but they'll be excluded from any feature that needs hoopR (starters, team form). Phase 2 will log the effective-n after these drops.
2. **Factor-level orderings** are locked here (`2023/2024 < 2024/2025 < 2025/2026`; `REGULAR SEASON < POST SEASON`). If any later script relies on a different ordering, it should re-`factor()` explicitly.
3. **`network_combined` factor levels** depend on what simulcast combinations happen to be in the data — adding a new season may introduce new levels (e.g., `NBC+PEACOCK`).

## Code quality self-assessment

The script is linear, deterministic (`set.seed(4010)`), and idempotent. Every
drop is tagged via a single helper (`tag_drops`) so the audit file always
stays in sync with the step counts. One uncertainty: the hoopR attach here
is intentionally simpler than Phase 0 (exact + swap only, no fuzzy) — the
match rate is 0.16 pp lower than Phase 0's, which is a deliberate trade
for a shorter audit trail. If Phase 2 needs the extra row, it can re-run
the fuzzy stage.

## --- HUMAN COLLABORATION LOG ---

### Human inputs / decisions that shaped this phase

- "ok - start with phase 1" → green-lit Phase 1 after reviewing the Phase 0 resolutions. No additional scope changes requested.
- Phase 0 resolutions carried forward verbatim: ESPNU→ESPN collapse, `LOS ANGELES`→Lakers, acceptance of n=639, `"N/A"`-string handling (that last one lives in Phase 0 follower code — Phase 1 doesn't touch the follower file).

### Human questions answered in-chat

- (none this phase)

### Where the human did NOT intervene

- Canonical `game_id` format (`YYYY-MM-DD_AWAY_HOME`, spaces stripped).
- Decision to keep `matched_to_hoopr == FALSE` rows rather than dropping them here.
- Decision to skip fuzzy-±3d matching in the production cleanup.
- The drop-reason tag strings and the `phase1_drops.csv` / `phase1_step_counts.csv` layout.
- Factor-level orderings for `season` and `season_type`.
