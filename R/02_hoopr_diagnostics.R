# =============================================================================
# Phase 0 — Pre-modeling diagnostics
# =============================================================================
# Executes the checks in 00_PROJECT_CONTEXT.md §4 and writes:
#   - data/interim/phase0_ratings_cleaned.rds   (clean ratings after §4.1–4.2)
#   - data/interim/phase0_diag_summary.rds      (list of diagnostic outputs)
#   - data/interim/phase0_unmatched.csv         (ratings rows unmatched to hoopR)
# Console output is the human-readable summary; a separate script
# (R/02_hoopr_diagnostics_writeup.R) converts that into the .md writeup.
# =============================================================================

set.seed(4010)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(readxl)
  library(janitor)
  library(stringr)
  library(lubridate)
  library(tidyr)
  library(purrr)
  library(here)
  library(hoopR)
})

source(here::here("R", "utils.R"))

# -----------------------------------------------------------------------------
# helper: divider print
# -----------------------------------------------------------------------------
hr <- function(msg) cat("\n\n==== ", msg, " ====\n", sep = "")

# =============================================================================
# 4.1  RATINGS CLEANUP
# =============================================================================
hr("4.1 RATINGS CLEANUP")

rat_raw <- read_csv(
  here("data", "raw", "nba_national_ratings.csv"),
  show_col_types = FALSE
) |>
  clean_names()

stopifnot(all(c("season", "season_type", "network", "program",
                "episode", "date", "duration_mins", "p2") %in% names(rat_raw)))

counts <- list()
counts[["01_start"]] <- nrow(rat_raw)

rat <- rat_raw |>
  mutate(game_date = mdy(date))
stopifnot(sum(is.na(rat$game_date)) == 0)

# -- Drop NBA-TV --
rat <- rat |> filter(network != "NBA-TV")
counts[["02_drop_nba_tv"]] <- nrow(rat)

# -- Collapse ESPNU into ESPN (per human decision: ESPNU is an ESPN feed
#    and should be modeled as the same network level) --
rat <- rat |> mutate(network = if_else(network == "ESPNU", "ESPN", network))

# -- Drop ALL STAR WEEKEND --
rat <- rat |> filter(season_type != "ALL STAR WEEKEND")
counts[["03_drop_all_star"]] <- nrow(rat)

# -- Drop FINALS rows (dedup with POST SEASON) --
rat <- rat |> filter(season_type != "FINALS")
counts[["04_drop_finals"]] <- nrow(rat)

# -- Drop explicit rollup rows not tied to a single game --
# Observed: one EPISODE == "VARIOUS TEAMS AND TIMES" (weekly multi-game pooled)
rat <- rat |> filter(episode != "VARIOUS TEAMS AND TIMES")
counts[["04b_drop_various"]] <- nrow(rat)

# =============================================================================
# 4.2  MATCHUP PARSING
# =============================================================================
hr("4.2 MATCHUP PARSING")

parsed <- parse_episode(rat$episode)
rat <- bind_cols(rat |> select(-any_of(c("episode_raw","away_raw","home_raw",
                                         "away_team","home_team","parse_status"))),
                 parsed)

parse_status_tbl <- table(rat$parse_status, useNA = "ifany")
cat("parse_status counts:\n")
print(parse_status_tbl)

unparsed_rows <- rat |> filter(parse_status != "ok")
cat("\nSample unparsed / unknown rows (up to 10):\n")
print(unparsed_rows |>
        select(episode_raw, away_raw, home_raw, parse_status, program) |>
        slice_head(n = 10))

# Drop anything not "ok"
rat <- rat |> filter(parse_status == "ok")
counts[["05_drop_unparsed_matchup"]] <- nrow(rat)

# -----------------------------------------------------------------------------
# ROLLUP / DUPLICATE HANDLING
# -----------------------------------------------------------------------------
# Spec §4.1 step: "For each game, when a rollup row exists use it and drop the
# per-network row(s) for that game". The raw file has no explicit rollup flag,
# so we identify duplicates by (game_date, home_team, away_team) and — per
# §3 caveat 4 ("when a rollup exists, it IS the canonical total") — keep the
# row with the maximum P2+ in each group. This is the simulcast total.
hr("4.1b ROLLUP DEDUP (within game_date × home × away)")

dup_groups <- rat |>
  count(game_date, home_team, away_team, name = "n") |>
  filter(n > 1) |>
  arrange(desc(n))
cat("duplicate (date,home,away) groups:", nrow(dup_groups), "\n")
cat("rows involved in duplicate groups:", sum(dup_groups$n), "\n\n")

cat("Network combinations in duplicate groups (top 10):\n")
dup_network_combos <- rat |>
  semi_join(dup_groups, by = c("game_date", "home_team", "away_team")) |>
  arrange(game_date, home_team, away_team, desc(p2)) |>
  group_by(game_date, home_team, away_team) |>
  summarise(networks = paste(network, collapse = "+"),
            p2_values = paste(p2, collapse = ","),
            .groups = "drop") |>
  count(networks, sort = TRUE)
print(dup_network_combos, n = 15)

rat <- rat |>
  group_by(game_date, home_team, away_team) |>
  arrange(desc(p2), .by_group = TRUE) |>
  mutate(network_combined = paste(sort(unique(network)), collapse = "+")) |>
  slice(1) |>
  ungroup()
counts[["06_after_rollup_dedup"]] <- nrow(rat)

# -----------------------------------------------------------------------------
# DURATION FILTER
# -----------------------------------------------------------------------------
hr("4.1c DURATION FILTER (>= 60 min)")

short_games <- rat |> filter(duration_mins < 60)
cat("rows with duration_mins < 60:", nrow(short_games), "\n")
if (nrow(short_games) > 0) {
  cat("sample:\n")
  print(short_games |> select(game_date, home_team, away_team, network,
                              duration_mins, program) |> slice_head(n = 5))
}
rat <- rat |> filter(duration_mins >= 60)
counts[["07_after_duration_filter"]] <- nrow(rat)

# -----------------------------------------------------------------------------
# Counts summary
# -----------------------------------------------------------------------------
hr("CLEANUP COUNTS")
counts_df <- tibble(step = names(counts), n = unlist(counts))
print(counts_df)

# Target 650-900 check
final_n <- counts[["07_after_duration_filter"]]
in_target <- final_n >= 650 & final_n <= 900
cat(sprintf("\nFinal observation count: %d (target 650-900): %s\n",
            final_n, if (in_target) "OK" else "OUT OF RANGE"))

# =============================================================================
# 4.3  hoopR COVERAGE
# =============================================================================
hr("4.3 hoopR COVERAGE")

cat("Loading hoopR team box for seasons 2024, 2025, 2026...\n")
tb <- load_nba_team_box(seasons = 2024:2026)
cat("tb rows:", nrow(tb), " | unique game_ids:", n_distinct(tb$game_id), "\n")

# Extract one row per game from the home-team perspective; drop All-Star teams.
games <- tb |>
  filter(team_home_away == "home") |>
  filter(!team_display_name %in% c("Eastern Conf All-Stars",
                                   "Western Conf All-Stars"),
         !opponent_team_display_name %in% c("Eastern Conf All-Stars",
                                            "Western Conf All-Stars")) |>
  transmute(
    hoopr_game_id = game_id,
    hoopr_date    = as.Date(game_date),
    hoopr_season_type = season_type,
    home_team     = team_display_name,
    away_team     = opponent_team_display_name
  )
cat("hoopR games (non-All-Star):", nrow(games), "\n")

rat <- rat |> mutate(rating_id = row_number())

# -- Attempt 1: exact (date, home, away) match --
m1 <- rat |>
  inner_join(games, by = c("game_date" = "hoopr_date",
                           "home_team",  "away_team"))
cat("\nExact match:", nrow(m1), "/", nrow(rat),
    sprintf(" (%.1f%%)\n", 100 * nrow(m1) / nrow(rat)))

# -- Attempt 2: swapped home/away (handles slash-format ambiguity) --
left_after_m1 <- rat |> anti_join(m1, by = "rating_id")
m2 <- left_after_m1 |>
  inner_join(games, by = c("game_date" = "hoopr_date",
                           "home_team" = "away_team",
                           "away_team" = "home_team"),
             suffix = c("", ".swap"))
# Swapped: the hoopR view says our "home_team" is actually the away team.
# Re-align so that final data has true hoopR home/away.
m2 <- m2 |>
  mutate(ratings_home = home_team,
         ratings_away = away_team,
         home_team = ratings_away,
         away_team = ratings_home) |>
  select(-ratings_home, -ratings_away)
cat("Swapped-order match (additional):", nrow(m2), "\n")

# -- Attempt 3: ±3 day tolerance on still-unmatched rows (covers TZ edge cases
#    and Nielsen-airdate vs game-date drift) --
left_after_m2 <- rat |>
  anti_join(bind_rows(m1 |> select(rating_id),
                      m2 |> select(rating_id)),
            by = "rating_id")

if (nrow(left_after_m2) > 0) {
  games_fuzzy <- games |>
    transmute(hoopr_game_id, hoopr_season_type,
              home_team, away_team, hoopr_date)

  m3 <- left_after_m2 |>
    inner_join(games_fuzzy, by = c("home_team", "away_team"),
               relationship = "many-to-many") |>
    filter(abs(as.integer(game_date - hoopr_date)) <= 3) |>
    group_by(rating_id) |>
    slice_min(order_by = abs(as.integer(game_date - hoopr_date)), n = 1) |>
    ungroup()

  left_after_m3 <- left_after_m2 |> anti_join(m3, by = "rating_id")
  m4 <- left_after_m3 |>
    inner_join(games_fuzzy, by = c("home_team" = "away_team",
                                   "away_team" = "home_team"),
               relationship = "many-to-many") |>
    filter(abs(as.integer(game_date - hoopr_date)) <= 3) |>
    group_by(rating_id) |>
    slice_min(order_by = abs(as.integer(game_date - hoopr_date)), n = 1) |>
    ungroup() |>
    mutate(ratings_home = home_team,
           ratings_away = away_team,
           home_team = ratings_away,
           away_team = ratings_home) |>
    select(-ratings_home, -ratings_away)
} else {
  m3 <- tibble(); m4 <- tibble()
}

cat("Fuzzy ±3d match (additional):", nrow(m3), "\n")
cat("Fuzzy ±3d swapped match (additional):", nrow(m4), "\n")

matched <- bind_rows(m1, m2, m3, m4) |> distinct(rating_id, .keep_all = TRUE)
unmatched <- rat |> anti_join(matched, by = "rating_id")

match_rate <- nrow(matched) / nrow(rat)
cat(sprintf("\nTOTAL matched: %d / %d (%.2f%%)\n",
            nrow(matched), nrow(rat), 100 * match_rate))
cat(sprintf("Target: >= 95%%.  Halt threshold: < 90%%.  Status: %s\n",
            ifelse(match_rate >= 0.95, "OK",
                   ifelse(match_rate >= 0.90, "WARN", "HALT"))))

# breakdown of unmatched by season / season_type
if (nrow(unmatched) > 0) {
  cat("\nUnmatched breakdown by season × season_type:\n")
  print(unmatched |> count(season, season_type) |> arrange(desc(n)))
  cat("\nSample unmatched rows (up to 15):\n")
  print(unmatched |> select(game_date, season, season_type, network,
                            home_team, away_team, program, episode_raw) |>
          slice_head(n = 15))
  write_csv(unmatched |> select(rating_id, game_date, season, season_type, network,
                                home_team, away_team, program, episode_raw,
                                p2, p18_49),
            here("data", "interim", "phase0_unmatched.csv"))
}

# -----------------------------------------------------------------------------
# 4.3b  Starter availability check on matched games
# -----------------------------------------------------------------------------
hr("4.3b STARTER AVAILABILITY (player_box)")

cat("Loading hoopR player box for seasons 2024, 2025, 2026 (may take a minute)...\n")
pb <- load_nba_player_box(seasons = 2024:2026)
cat("pb rows:", nrow(pb), "\n")
cat("columns (first 20):\n"); print(head(names(pb), 20))

# Check for starter-related column. hoopR typically has `starter` (logical)
# or `did_not_play` flags. We'll inspect.
starter_col <- intersect(c("starter", "starting_position"), names(pb))
cat("starter-related columns found:", paste(starter_col, collapse = ", "), "\n")

# Count starters per game per team
matched_game_ids <- unique(matched$hoopr_game_id)
cat("matched hoopR game_ids:", length(matched_game_ids), "\n")

pb_matched <- pb |> filter(game_id %in% matched_game_ids)

if ("starter" %in% names(pb_matched)) {
  starter_summary <- pb_matched |>
    group_by(game_id, team_id) |>
    summarise(n_starters = sum(starter, na.rm = TRUE),
              n_players  = n(), .groups = "drop")
  games_with_starters <- starter_summary |>
    group_by(game_id) |>
    summarise(min_starters = min(n_starters),
              max_starters = max(n_starters), .groups = "drop")
  n_bad_starters <- sum(games_with_starters$min_starters < 5)
  cat(sprintf("matched games with >= 5 starters on BOTH teams: %d / %d (%.1f%%)\n",
              nrow(games_with_starters) - n_bad_starters,
              nrow(games_with_starters),
              100 * (1 - n_bad_starters / nrow(games_with_starters))))
  if (n_bad_starters > 0) {
    cat("Games where at least one team has < 5 starters (first 10):\n")
    print(games_with_starters |> filter(min_starters < 5) |> slice_head(n = 10))
  }
} else {
  cat("No `starter` column in player_box — checking alternatives:\n")
  cat("first row columns:\n"); print(names(pb_matched))
  starter_summary <- NULL
  games_with_starters <- NULL
  n_bad_starters <- NA
}

# =============================================================================
# 4.4  FOLLOWERSHIP FILE
# =============================================================================
hr("4.4 FOLLOWERSHIP FILE")

foll_raw <- read_excel(
  here("data", "raw", "nba_team_athlete_followership.xlsx"),
  sheet = "Accounts", skip = 25
)
counts_foll <- list()
counts_foll[["01_start"]] <- nrow(foll_raw)

# Drop Community
foll <- foll_raw |> filter(`Account Type` != "Community")
counts_foll[["02_drop_community"]] <- nrow(foll)

# Team sanity check
team_rows <- foll |> filter(`Account Type` == "Team")
cat("Team rows:", nrow(team_rows), " (expected: 30)\n")
missing_teams <- setdiff(team_rows$`Team Name`, team_rows$`Team Name`) # always empty — sanity
all_teams <- sort(unique(team_rows$`Team Name`))
cat("Distinct teams:", length(all_teams), "\n")

# Athletes — per-player follower count.
# Some rows have the literal string "N/A" in follower-count columns (observed:
# Brandon Miller has two Charlotte Hornets rows — one with Totals = 22271,
# one with Totals = "N/A"). Coerce "N/A" to real NA, then take the max
# non-missing Totals per Account Name as the player's follower count.
athlete_rows <- foll |>
  filter(`Account Type` == "Athlete") |>
  mutate(totals_num = suppressWarnings(as.numeric(
    na_if(as.character(`Total Followership Count (Totals)`), "N/A"))))
cat("Athlete rows (incl. dupes from trades / duplicate listings):",
    nrow(athlete_rows), "\n")

athletes_unique <- athlete_rows |>
  group_by(`Account Name`) |>
  summarise(totals_final = suppressWarnings(max(totals_num, na.rm = TRUE)),
            .groups = "drop") |>
  mutate(totals_final = if_else(is.infinite(totals_final),
                                NA_real_, totals_final))
cat("Unique Account Names (post-dedup):", nrow(athletes_unique),
    " (target 571)\n")

# Check whether Totals really IS identical across a traded player's rows
# (using the numeric, N/A-coerced column; should now be 0).
dup_name_check <- athlete_rows |>
  group_by(`Account Name`) |>
  summarise(n_totals = n_distinct(totals_num[!is.na(totals_num)]),
            n_rows   = n(), .groups = "drop") |>
  filter(n_rows > 1)
cat("Players appearing on >1 team row:", nrow(dup_name_check), "\n")
cat("Of those, how many with inconsistent non-missing Totals:",
    sum(dup_name_check$n_totals > 1), "\n")

# =============================================================================
# SAVE DIAGNOSTIC SUMMARY + CLEANED RATINGS
# =============================================================================
hr("SAVING INTERIM OUTPUTS")

# Attach hoopR match info to the cleaned ratings (still carry unmatched rows
# flagged so Phase 1 can decide what to do)
rat_with_match <- rat |>
  left_join(matched |> select(rating_id, hoopr_game_id, hoopr_season_type),
            by = "rating_id") |>
  mutate(matched_to_hoopr = !is.na(hoopr_game_id))

saveRDS(rat_with_match,
        here("data", "interim", "phase0_ratings_cleaned.rds"))

diag_summary <- list(
  counts_ratings         = counts_df,
  parse_status_tbl       = parse_status_tbl,
  dup_network_combos     = dup_network_combos,
  final_n                = final_n,
  final_in_target_range  = in_target,
  match_exact_n          = nrow(m1),
  match_swap_n           = nrow(m2),
  match_fuzzy_n          = nrow(m3),
  match_fuzzy_swap_n     = nrow(m4),
  match_total_n          = nrow(matched),
  match_rate             = match_rate,
  unmatched_n            = nrow(unmatched),
  unmatched_by_season    = if (nrow(unmatched) > 0)
    unmatched |> count(season, season_type) else NULL,
  bad_starters_n         = n_bad_starters,
  n_games_checked_starters = if (!is.null(games_with_starters))
    nrow(games_with_starters) else NA_integer_,
  foll_counts            = counts_foll,
  foll_team_rows         = nrow(team_rows),
  foll_unique_athletes   = nrow(athletes_unique),
  foll_traded_players_n  = nrow(dup_name_check),
  foll_traded_inconsistent_n = sum(dup_name_check$n_totals > 1),
  hoopr_n_games          = nrow(games),
  hoopr_data_updated     = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  r_version              = R.version.string,
  set_seed               = 4010L
)
saveRDS(diag_summary,
        here("data", "interim", "phase0_diag_summary.rds"))

hr("PHASE 0 SCRIPT DONE")
cat("Interim files written:\n")
cat("  data/interim/phase0_ratings_cleaned.rds\n")
cat("  data/interim/phase0_diag_summary.rds\n")
if (nrow(unmatched) > 0)
  cat("  data/interim/phase0_unmatched.csv\n")
cat("\nNext: render writeups/02_hoopr_diagnostics.md from diag_summary.\n")
