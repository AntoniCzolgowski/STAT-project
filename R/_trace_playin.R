suppressPackageStartupMessages({library(dplyr); library(here)})
d <- readRDS(here("data","processed","model_data.rds"))

cat("== playoff_stakes class and levels in model_data.rds ==\n")
cat("class:", class(d$playoff_stakes), "\n")
print(levels(d$playoff_stakes))

cat("\n== raw table ==\n")
print(table(d$playoff_stakes, useNA = "ifany"))

cat("\n== rows where playoff_stakes == 'play_in' ==\n")
pi <- d |> filter(playoff_stakes == "play_in")
cat("n =", nrow(pi), "\n")
print(pi |> select(game_id, game_date, home_team, away_team, season_type,
                   playoff_stakes, network, p2_plus) |> head(15))
