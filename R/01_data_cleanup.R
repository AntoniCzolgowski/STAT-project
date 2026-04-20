# =============================================================================
# Phase 1 — Data cleanup (production)
# =============================================================================
# Applies the cleaning rules validated in Phase 0 diagnostics and emits the
# canonical row-level modeling table per 00_PROJECT_CONTEXT.md §5.
#
# Inputs
#   data/raw/nba_national_ratings.csv
#   hoopR::load_nba_team_box(seasons = 2024:2026)    (for game_id join only)
#
# Outputs
#   data/interim/ratings_clean.rds       - canonical schema, one row per game
#   data/interim/phase1_drops.csv        - every dropped raw row with reason
#   data/interim/phase1_step_counts.csv  - before/after row counts per step
#
# Each row removed from the raw file is tagged with a reason in
# `phase1_drops.csv`. No silent drops.
# =============================================================================

set.seed(4010)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(janitor)
  library(stringr)
  library(lubridate)
  library(tidyr)
  library(here)
  library(hoopR)
})

source(here::here("R", "utils.R"))

# -----------------------------------------------------------------------------
# 0. Load raw + stable row id for drop tracking
# -----------------------------------------------------------------------------
rat_raw <- read_csv(
  here("data", "raw", "nba_national_ratings.csv"),
  show_col_types = FALSE
) |>
  clean_names() |>
  mutate(raw_row_id = row_number(),
         game_date  = mdy(date))

stopifnot(sum(is.na(rat_raw$game_date)) == 0)

drops        <- list()   # accumulated (raw_row_id, reason) tibbles
step_counts  <- list()
step_counts[["00_start"]] <- nrow(rat_raw)

rat <- rat_raw

tag_drops <- function(rows_removed, reason) {
  tibble(raw_row_id = rows_removed$raw_row_id,
         reason     = reason,
         season     = rows_removed$season,
         season_type = rows_removed$season_type,
         network    = rows_removed$network,
         episode    = rows_removed$episode,
         game_date  = rows_removed$game_date)
}

# -----------------------------------------------------------------------------
# 1. Drop NBA-TV (spec §3 caveat 5: cable specialty, not a mainstream broadcast)
# -----------------------------------------------------------------------------
dropped <- rat |> filter(network == "NBA-TV")
drops[["01_nba_tv"]] <- tag_drops(dropped, "network == NBA-TV (spec: cable, excluded)")
rat <- rat |> filter(network != "NBA-TV")
step_counts[["01_drop_nba_tv"]] <- nrow(rat)

# -----------------------------------------------------------------------------
# 2. Collapse ESPNU -> ESPN (human decision: same network family)
# -----------------------------------------------------------------------------
rat <- rat |> mutate(network = if_else(network == "ESPNU", "ESPN", network))
step_counts[["02_collapse_espnu"]] <- nrow(rat)

# -----------------------------------------------------------------------------
# 3. Drop ALL STAR WEEKEND (no starting 5, no standard game structure)
# -----------------------------------------------------------------------------
dropped <- rat |> filter(season_type == "ALL STAR WEEKEND")
drops[["03_all_star"]] <- tag_drops(dropped, "season_type == ALL STAR WEEKEND")
rat <- rat |> filter(season_type != "ALL STAR WEEKEND")
step_counts[["03_drop_all_star"]] <- nrow(rat)

# -----------------------------------------------------------------------------
# 4. Drop FINALS rows (they re-appear as POST SEASON; keep the POST SEASON copy)
# -----------------------------------------------------------------------------
dropped <- rat |> filter(season_type == "FINALS")
drops[["04_finals"]] <- tag_drops(dropped, "season_type == FINALS (dup of POST SEASON)")
rat <- rat |> filter(season_type != "FINALS")
step_counts[["04_drop_finals"]] <- nrow(rat)

# -----------------------------------------------------------------------------
# 5. Drop "VARIOUS TEAMS AND TIMES" (weekly multi-game rollup, no single game)
# -----------------------------------------------------------------------------
dropped <- rat |> filter(episode == "VARIOUS TEAMS AND TIMES")
drops[["05_various"]] <- tag_drops(dropped, "episode == VARIOUS TEAMS AND TIMES (multi-game rollup)")
rat <- rat |> filter(episode != "VARIOUS TEAMS AND TIMES")
step_counts[["05_drop_various"]] <- nrow(rat)

# -----------------------------------------------------------------------------
# 6. Parse EPISODE -> (away_team, home_team). Drop anything unparseable.
# -----------------------------------------------------------------------------
parsed <- parse_episode(rat$episode)
rat <- bind_cols(
  rat |> select(-any_of(c("episode_raw","away_raw","home_raw",
                          "away_team","home_team","parse_status"))),
  parsed
)

dropped <- rat |> filter(parse_status != "ok")
drops[["06_unparseable"]] <- tag_drops(
  dropped,
  paste0("unparseable EPISODE (parse_status=", dropped$parse_status, ")")
)
rat <- rat |> filter(parse_status == "ok")
step_counts[["06_drop_unparseable"]] <- nrow(rat)

# -----------------------------------------------------------------------------
# 7. Rollup dedup: collapse duplicate (game_date, home, away) to the max-P2+
#    row (assumed simulcast combined total). Record network concatenation.
# -----------------------------------------------------------------------------
# Identify groups first so we can tag the dropped per-network rows.
grp_keys <- rat |>
  group_by(game_date, home_team, away_team) |>
  mutate(grp_n = n(),
         is_winner = row_number(desc(p2)) == 1) |>
  ungroup()

dropped <- grp_keys |> filter(grp_n > 1, !is_winner)
drops[["07_rollup"]] <- tag_drops(
  dropped,
  "rollup dedup: lower-P2+ per-network row within (date, home, away) group"
)

rat <- grp_keys |>
  group_by(game_date, home_team, away_team) |>
  arrange(desc(p2), .by_group = TRUE) |>
  mutate(network_combined = paste(sort(unique(network)), collapse = "+")) |>
  slice(1) |>
  ungroup() |>
  select(-grp_n, -is_winner)

step_counts[["07_rollup_dedup"]] <- nrow(rat)

# -----------------------------------------------------------------------------
# 8. Duration filter: >= 60 minutes (drop highlight/fragment telecasts).
# -----------------------------------------------------------------------------
dropped <- rat |> filter(duration_mins < 60)
drops[["08_duration"]] <- tag_drops(dropped, "duration_mins < 60")
rat <- rat |> filter(duration_mins >= 60)
step_counts[["08_duration_filter"]] <- nrow(rat)

# -----------------------------------------------------------------------------
# 9. Attach hoopR game_id (left join; unmatched rows kept with NA).
#    Matching logic mirrors Phase 0: exact on (date, home, away), then swap.
#    The ±3d fuzzy window in Phase 0 recovered only 1 extra row; we keep
#    only the exact+swap stages here for a simpler audit trail. (Phase 0
#    covers 622/639 with full fuzzy; this join covers 621/639 = 97.2%,
#    which still clears the 95% target.)
# -----------------------------------------------------------------------------
tb <- load_nba_team_box(seasons = 2024:2026)
games <- tb |>
  filter(team_home_away == "home",
         !team_display_name %in% c("Eastern Conf All-Stars",
                                   "Western Conf All-Stars"),
         !opponent_team_display_name %in% c("Eastern Conf All-Stars",
                                            "Western Conf All-Stars")) |>
  transmute(hoopr_game_id = game_id,
            hoopr_date    = as.Date(game_date),
            hoopr_home    = team_display_name,
            hoopr_away    = opponent_team_display_name)

m_exact <- rat |>
  inner_join(games, by = c("game_date" = "hoopr_date",
                           "home_team" = "hoopr_home",
                           "away_team" = "hoopr_away")) |>
  select(raw_row_id, hoopr_game_id)

m_swap <- rat |>
  anti_join(m_exact, by = "raw_row_id") |>
  inner_join(games, by = c("game_date" = "hoopr_date",
                           "home_team" = "hoopr_away",
                           "away_team" = "hoopr_home")) |>
  select(raw_row_id, hoopr_game_id)

matched <- bind_rows(m_exact, m_swap) |> distinct(raw_row_id, .keep_all = TRUE)

rat <- rat |>
  left_join(matched, by = "raw_row_id") |>
  mutate(matched_to_hoopr = !is.na(hoopr_game_id))

cat(sprintf(
  "hoopR match: %d / %d (%.2f%%)\n",
  sum(rat$matched_to_hoopr), nrow(rat),
  100 * mean(rat$matched_to_hoopr)
))

# -----------------------------------------------------------------------------
# 10. Build canonical schema.
# -----------------------------------------------------------------------------
clean <- rat |>
  transmute(
    game_id = sprintf("%s_%s_%s",
                      format(game_date, "%Y-%m-%d"),
                      str_replace_all(away_team, "\\s+", ""),
                      str_replace_all(home_team, "\\s+", "")),
    game_date,
    home_team     = factor(home_team),
    away_team     = factor(away_team),
    season        = factor(season,
                           levels = c("2023/2024", "2024/2025", "2025/2026")),
    season_type   = factor(season_type,
                           levels = c("REGULAR SEASON", "POST SEASON")),
    network       = factor(network_combined),
    duration_min  = as.integer(duration_mins),
    telecast_time,
    p2_plus       = as.integer(p2),
    p18_49        = as.integer(p18_49),
    hoopr_game_id,
    matched_to_hoopr,
    raw_row_id
  )

# Sanity: game_id should be unique
stopifnot(!any(duplicated(clean$game_id)))

# -----------------------------------------------------------------------------
# 11. Write outputs.
# -----------------------------------------------------------------------------
saveRDS(clean, here("data", "interim", "ratings_clean.rds"))

drops_df <- bind_rows(drops, .id = "step")
write_csv(drops_df, here("data", "interim", "phase1_drops.csv"))

counts_df <- tibble(step = names(step_counts),
                    n    = unlist(step_counts)) |>
  mutate(delta = n - lag(n))
write_csv(counts_df, here("data", "interim", "phase1_step_counts.csv"))

# -----------------------------------------------------------------------------
# 12. Console summary.
# -----------------------------------------------------------------------------
cat("\n== Phase 1 step counts ==\n")
print(counts_df)
cat("\n== Drop reasons ==\n")
print(drops_df |> count(step, reason, sort = TRUE))
cat("\n== Canonical table ==\n")
cat(sprintf("rows: %d | unique game_id: %d | matched_to_hoopr: %d\n",
            nrow(clean), n_distinct(clean$game_id),
            sum(clean$matched_to_hoopr)))
cat("\nWrote:\n")
cat("  data/interim/ratings_clean.rds\n")
cat("  data/interim/phase1_drops.csv\n")
cat("  data/interim/phase1_step_counts.csv\n")
