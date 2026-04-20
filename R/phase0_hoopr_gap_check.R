# Does hoopR have a gap in late March - April 2025?
suppressPackageStartupMessages({
  library(dplyr); library(hoopR); library(lubridate); library(here)
})

tb <- load_nba_team_box(seasons = 2024:2026)
games <- tb |>
  filter(team_home_away == "home",
         !team_display_name %in% c("Eastern Conf All-Stars",
                                   "Western Conf All-Stars"))

daily <- games |>
  mutate(d = as.Date(game_date)) |>
  count(d, season, name = "n_games") |>
  arrange(d)

cat("n games per day, 2025-03-20 through 2025-04-25:\n")
print(daily |> filter(d >= as.Date("2025-03-20"),
                      d <= as.Date("2025-04-25")),
      n = 60)

cat("\nn games per day, 2025-10-20 through 2025-11-05 (2025-26 start):\n")
print(daily |> filter(d >= as.Date("2025-10-20"),
                      d <= as.Date("2025-11-05")),
      n = 30)

cat("\nGolden State Warriors season-2025 games in hoopR:\n")
gsw <- games |>
  filter(season == 2025,
         team_display_name == "Golden State Warriors" |
         opponent_team_display_name == "Golden State Warriors") |>
  transmute(game_date = as.Date(game_date),
            home_team = team_display_name,
            away_team = opponent_team_display_name) |>
  arrange(game_date)
cat("total:", nrow(gsw), " | date range:",
    format(min(gsw$game_date)), "to", format(max(gsw$game_date)), "\n")
print(tail(gsw, 15))
