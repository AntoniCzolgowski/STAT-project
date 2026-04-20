suppressPackageStartupMessages({library(dplyr); library(tidyr); library(here)})
d <- readRDS(here("data","processed","model_data.rds"))

required <- c(
  "p2_plus","starting5_followers_total",
  "team_handle_followers_home","team_handle_followers_away",
  "market_hh_combined",
  "home_last5_win_pct","away_last5_win_pct","on_fire_either",
  "combined_season_win_pct","playoff_stakes","network",
  "time_slot","is_holiday","is_weekend"
)

pi <- d |> filter(playoff_stakes == "play_in")

cat("== per-required-column missingness among 12 play_in rows ==\n")
for (col in required) {
  n_na <- sum(is.na(pi[[col]]))
  if (n_na > 0) cat(sprintf("  %-35s : %d NA\n", col, n_na))
}

cat("\n== complete-case count for play_in rows ==\n")
cc <- pi |> drop_na(all_of(required))
cat("rows kept:", nrow(cc), "of 12\n")

cat("\n== all rows lost by required-cols drop, by playoff_stakes ==\n")
df_cc <- d |> drop_na(all_of(required))
cat("rows before:", nrow(d), " after:", nrow(df_cc), "\n")
cat("\nbefore:\n"); print(table(d$playoff_stakes, useNA = "ifany"))
cat("\nafter drop_na(required):\n"); print(table(df_cc$playoff_stakes, useNA = "ifany"))
