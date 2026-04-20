# =============================================================================
# Phase 0 resolution — investigate the 6 items the human flagged for review.
# This script is diagnostic only; it writes a summary RDS and prints results.
# Not part of the production pipeline.
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(readxl); library(janitor)
  library(stringr); library(lubridate); library(purrr); library(tidyr)
  library(here); library(hoopR)
})
source(here("R", "utils.R"))

hr <- function(msg) cat("\n\n========== ", msg, " ==========\n", sep = "")

# ---- reload data ----
unmatched <- read_csv(here("data", "interim", "phase0_unmatched.csv"),
                     show_col_types = FALSE)
clean     <- readRDS(here("data", "interim", "phase0_ratings_cleaned.rds"))
diag      <- readRDS(here("data", "interim", "phase0_diag_summary.rds"))

tb <- load_nba_team_box(seasons = 2024:2026)
games <- tb |>
  filter(team_home_away == "home",
         !team_display_name %in% c("Eastern Conf All-Stars",
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
cat("hoopR games loaded:", nrow(games),
    " | date range:", format(min(games$hoopr_date)),
    "to", format(max(games$hoopr_date)), "\n")

# =============================================================================
# ITEM 1 — investigate the 17 unmatched ratings rows
# =============================================================================
hr("ITEM 1: 17 UNMATCHED ROWS")

resolve_unmatched <- function(r) {
  # Any hoopR game with these two canonical teams within ±14 days
  cand <- games |>
    filter((home_team == r$home_team & away_team == r$away_team) |
           (home_team == r$away_team & away_team == r$home_team)) |>
    filter(abs(as.integer(hoopr_date - r$game_date)) <= 14) |>
    arrange(abs(as.integer(hoopr_date - r$game_date)))

  if (nrow(cand) == 0) {
    # nothing for that pair — show any game involving either team on that day
    neighbors <- games |>
      filter(hoopr_date == r$game_date,
             (home_team %in% c(r$home_team, r$away_team) |
              away_team %in% c(r$home_team, r$away_team)))
    list(
      resolution = "no_team_pair_within_14d",
      n_candidates = 0L,
      best_hoopr_game_id = NA_integer_,
      best_hoopr_date = as.Date(NA),
      day_delta = NA_integer_,
      note = sprintf("%d hoopR games involving either team on %s",
                     nrow(neighbors), r$game_date)
    )
  } else {
    best <- cand |> slice(1)
    list(
      resolution = "candidate_found",
      n_candidates = nrow(cand),
      best_hoopr_game_id = best$hoopr_game_id,
      best_hoopr_date = best$hoopr_date,
      day_delta = as.integer(best$hoopr_date - r$game_date),
      note = sprintf("hoopR has: %s home / %s away on %s",
                     best$home_team, best$away_team, best$hoopr_date)
    )
  }
}

res1 <- map(seq_len(nrow(unmatched)),
            \(i) resolve_unmatched(unmatched[i, ])) |>
  map_dfr(as_tibble) |>
  bind_cols(unmatched |> select(rating_id, game_date, episode_raw,
                                home_team, away_team), y = _)
print(res1 |>
        select(rating_id, game_date, episode_raw, resolution,
               day_delta, note),
      n = Inf, width = 200)

cat("\nSummary:\n")
print(res1 |> count(resolution))

# =============================================================================
# ITEM 4 — traded player with inconsistent "Total Followership Count (Totals)"
# =============================================================================
hr("ITEM 4: TRADED PLAYER WITH INCONSISTENT TOTALS")

foll <- read_excel(here("data", "raw", "nba_team_athlete_followership.xlsx"),
                   sheet = "Accounts", skip = 25) |>
  filter(`Account Type` != "Community")

athletes <- foll |> filter(`Account Type` == "Athlete")

inconsistent <- athletes |>
  group_by(`Account Name`) |>
  summarise(n_rows = n(),
            n_distinct_totals = n_distinct(`Total Followership Count (Totals)`),
            totals = paste(sort(unique(as.character(
              `Total Followership Count (Totals)`))), collapse = "; "),
            teams = paste(sort(unique(`Team Name`)), collapse = "; "),
            .groups = "drop") |>
  filter(n_rows > 1 & n_distinct_totals > 1)

cat("Athletes with > 1 team row AND inconsistent Totals:\n")
print(inconsistent, width = 200)

if (nrow(inconsistent) > 0) {
  cat("\nFull row detail for each such athlete:\n")
  for (nm in inconsistent$`Account Name`) {
    cat("\n--- ", nm, " ---\n")
    print(athletes |>
            filter(`Account Name` == nm) |>
            select(`Team Name`, `Account Name`,
                   `Total Followership Count (Totals)`,
                   `Total Followership Count (Facebook)`,
                   `Total Followership Count (Instagram)`,
                   `Total Followership Count (X)`,
                   `Total Followership Count (YouTube)`))
  }
}

# =============================================================================
# ITEM 5 — LOS ANGELES/MINNESOTA: Lakers or Clippers?
# =============================================================================
hr("ITEM 5: LOS ANGELES/MINNESOTA DISAMBIGUATION")

rat_raw <- read_csv(here("data", "raw", "nba_national_ratings.csv"),
                    show_col_types = FALSE) |>
  clean_names() |>
  mutate(game_date = mdy(date))

la_mn <- rat_raw |> filter(episode == "LOS ANGELES/MINNESOTA")
cat("Raw row(s):\n")
print(la_mn |> select(season, season_type, network, program, episode,
                      game_date, p2_plus = p2))

for (i in seq_len(nrow(la_mn))) {
  d <- la_mn$game_date[i]
  cat(sprintf("\nDate %s — hoopR candidates (±3 days) against Minnesota:\n", d))
  for (la in c("Los Angeles Lakers", "LA Clippers")) {
    m <- games |>
      filter(abs(as.integer(hoopr_date - d)) <= 3,
             (home_team == la & away_team == "Minnesota Timberwolves") |
             (home_team == "Minnesota Timberwolves" & away_team == la))
    cat(sprintf("  %-20s : %d candidate(s)\n", la, nrow(m)))
    if (nrow(m) > 0) print(m)
  }
}

# =============================================================================
# ITEM 6 — Slash-format convention: is first team usually away?
# =============================================================================
hr("ITEM 6: SLASH-FORMAT home/away CONVENTION")

# Slash-format matched rows (from the cleaned dataset)
slash_matched <- clean |>
  filter(matched_to_hoopr,
         !str_detect(episode_raw, "\\s+AT\\s+"),
         !str_detect(episode_raw, "\\s+VS\\.?\\s+"),
         str_detect(episode_raw, "/"))
cat("total slash-format matched rows:", nrow(slash_matched), "\n")

# Compare ratings-side home/away to hoopR's home/away
slash_join <- slash_matched |>
  left_join(games |> rename(hoopr_home = home_team,
                            hoopr_away = away_team),
            by = "hoopr_game_id") |>
  mutate(
    first_token = str_trim(str_split_fixed(episode_raw, "/", 2)[, 1]),
    first_canonical = canonicalize_team(first_token),
    first_is_hoopr_away = first_canonical == hoopr_away,
    first_is_hoopr_home = first_canonical == hoopr_home
  )

cat("first team before '/' equals hoopR AWAY (first=away convention holds): ",
    sum(slash_join$first_is_hoopr_away, na.rm = TRUE), "\n")
cat("first team before '/' equals hoopR HOME (first=home convention):      ",
    sum(slash_join$first_is_hoopr_home, na.rm = TRUE), "\n")

# Per-episode-type breakdown (regular season vs post-season)
cat("\nBy season_type:\n")
print(slash_join |>
        count(season_type,
              convention = case_when(
                first_is_hoopr_away ~ "first = AWAY",
                first_is_hoopr_home ~ "first = HOME",
                TRUE                ~ "other/NA"
              )) |>
        pivot_wider(names_from = convention, values_from = n, values_fill = 0))

# =============================================================================
# SAVE
# =============================================================================
hr("SAVE")
saveRDS(list(item1_unmatched_resolution = res1,
             item4_inconsistent_players = inconsistent,
             item5_la_mn_rows = la_mn,
             item6_slash_convention = slash_join |>
               select(rating_id, episode_raw, season_type,
                      first_is_hoopr_home, first_is_hoopr_away)),
        here("data", "interim", "phase0_resolve.rds"))
cat("Wrote data/interim/phase0_resolve.rds\n")
