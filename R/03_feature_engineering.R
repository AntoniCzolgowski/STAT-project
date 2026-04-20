# =============================================================================
# Phase 2 — Feature engineering
# =============================================================================
# Per 00_PROJECT_CONTEXT.md §6, builds the 6 predictor families on top of the
# Phase 1 canonical ratings table. One row per game, features attached.
#
# Inputs
#   data/interim/ratings_clean.rds                        (Phase 1)
#   data/raw/nba_team_athlete_followership.xlsx           (SCR)
#   data/raw/dmas.csv                                     (Nielsen DMA file)
#   hoopR::load_nba_team_box(seasons = 2024:2026)         (team form)
#   hoopR::load_nba_player_box(seasons = 2024:2026)       (starters)
#
# Outputs
#   data/processed/model_data.rds                         (final modeling df)
#   data/interim/phase2_feature_summary.rds               (diagnostics)
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
  library(hms)
})

source(here::here("R", "utils.R"))

hr <- function(msg) cat("\n\n==== ", msg, " ====\n", sep = "")

# -----------------------------------------------------------------------------
# Load Phase 1 clean ratings
# -----------------------------------------------------------------------------
clean <- readRDS(here("data", "interim", "ratings_clean.rds"))
cat("clean ratings rows:", nrow(clean),
    " | matched_to_hoopr:", sum(clean$matched_to_hoopr), "\n")

# =============================================================================
# 6.1  STAR POWER
# =============================================================================
hr("6.1 STAR POWER (starters + team handles)")

foll <- read_excel(
  here("data", "raw", "nba_team_athlete_followership.xlsx"),
  sheet = "Accounts", skip = 25
) |>
  filter(`Account Type` != "Community") |>
  mutate(totals_num = suppressWarnings(as.numeric(
    na_if(as.character(`Total Followership Count (Totals)`), "N/A"))))

# Team handles (one row per team)
# NOTE: follower file uses "Los Angeles Clippers"; hoopR / canonical = "LA Clippers"
team_foll <- foll |>
  filter(`Account Type` == "Team") |>
  transmute(team = if_else(`Team Name` == "Los Angeles Clippers",
                           "LA Clippers", `Team Name`),
            team_handle_followers = totals_num)
stopifnot(nrow(team_foll) == 30)

# Player dict (one follower number per player — taken as max over any duplicate
# listings, collapsing "N/A" rows; see Phase 0 writeup on Brandon Miller)
player_foll <- foll |>
  filter(`Account Type` == "Athlete") |>
  group_by(player_name = `Account Name`) |>
  summarise(total_followers = suppressWarnings(max(totals_num, na.rm = TRUE)),
            .groups = "drop") |>
  mutate(total_followers = if_else(is.infinite(total_followers),
                                   NA_real_, total_followers))
stopifnot(nrow(player_foll) == 571)

# ---- Starting-5 followers per (game, team) from hoopR player box -----------
cat("loading hoopR player_box for 2024..2026...\n")
pb <- load_nba_player_box(seasons = 2024:2026)

# Names disagree between hoopR and the Talkwalker SCR file along several axes:
#   - diacritics ("Jusuf Nurkić" vs "Jusuf Nurkic")        -> ASCII-fold
#   - parenthetical SCR disambiguators ("LeBron James (NBA)") -> strip trailing (...)
#   - generational suffixes hoopR carries but SCR often drops:
#       "Michael Porter Jr.", "Kelly Oubre Jr.", "Jimmy Butler III",
#       "Marcus Morris Sr." -> strip Jr/Sr/II/III/IV after ASCII-fold
#   - hyphenation differences ("Caldwell-Pope" vs "Caldwell Pope")
#       -> collapse hyphens to spaces
#   - punctuation (".", "'") -> drop
# The normalize function below is applied to BOTH sides (follower file +
# hoopR) so asymmetric representations collapse to the same key.
normalize_name <- function(x) {
  x |>
    str_remove_all("\\s*\\([^\\)]+\\)\\s*$") |>                # "(NBA)"
    stringi::stri_trans_general("Latin-ASCII") |>
    str_replace_all("-", " ") |>                                # hyphens -> space
    str_remove_all("[\\.']") |>
    str_to_lower() |>
    str_remove_all("\\s+(jr|sr|ii|iii|iv)$") |>                 # suffixes
    str_squish()
}

player_foll <- player_foll |>
  mutate(name_key = normalize_name(player_name)) |>
  group_by(name_key) |>
  summarise(total_followers = suppressWarnings(max(total_followers,
                                                   na.rm = TRUE)),
            .groups = "drop") |>
  mutate(total_followers = if_else(is.infinite(total_followers),
                                   NA_real_, total_followers))

# team median followers (fallback for unmatched starters)
team_median_foll <- foll |>
  filter(`Account Type` == "Athlete") |>
  mutate(team = case_when(
    `Team Name` == "Los Angeles Clippers" ~ "LA Clippers",
    TRUE ~ `Team Name`
  )) |>
  group_by(team) |>
  summarise(team_median_player_followers =
              median(totals_num, na.rm = TRUE), .groups = "drop")

# starters: 5 per team per matched game
starters <- pb |>
  filter(starter == TRUE) |>
  transmute(hoopr_game_id = as.integer(game_id),
            team = paste(team_location, team_name),
            player_name = athlete_display_name,
            minutes) |>
  # hoopR's team_location + team_name reconstructs canonical team_display_name
  # (verified for all 30 active teams). One-off canonical fix:
  mutate(team = case_when(
    team == "Los Angeles Clippers" ~ "LA Clippers",
    team == "LA Clippers"           ~ "LA Clippers",
    TRUE ~ team
  ))

# attach followers (try exact name, then normalized-name fallback)
starters <- starters |>
  mutate(name_key = normalize_name(player_name)) |>
  left_join(player_foll |> select(name_key, total_followers),
            by = "name_key")

n_starter_rows <- nrow(starters)
n_matched_starter <- sum(!is.na(starters$total_followers))
cat(sprintf("starter rows (all hoopR 2024..2026): %d | matched: %d (%.1f%%)\n",
            n_starter_rows, n_matched_starter,
            100 * n_matched_starter / n_starter_rows))

# Impute unmatched starters with team median.
starters <- starters |>
  left_join(team_median_foll, by = "team") |>
  mutate(was_imputed = is.na(total_followers),
         followers_used = coalesce(total_followers,
                                   team_median_player_followers))

# The relevant rate is over the *games we actually model*, not the full
# 3-season hoopR universe (which includes G-League call-ups and injury
# starters in non-televised games). The §6.1 halt threshold applies here.
in_scope_game_ids <- unique(clean$hoopr_game_id[!is.na(clean$hoopr_game_id)])
starters_in_scope <- starters |> filter(hoopr_game_id %in% in_scope_game_ids)
imputation_rate <- mean(starters_in_scope$was_imputed, na.rm = TRUE)
cat(sprintf(
  "in-scope starters (matched games only): %d | imputation rate: %.2f%%\n",
  nrow(starters_in_scope), 100 * imputation_rate))
cat("(§6.1 escalation threshold: > 10%)\n")

# Sample of unmatched in-scope starter names, for the writeup risk section.
unmatched_sample <- starters_in_scope |>
  filter(was_imputed) |>
  distinct(player_name, team) |>
  arrange(player_name)
cat(sprintf("distinct unmatched in-scope starters: %d\n",
            nrow(unmatched_sample)))

if (imputation_rate > 0.10) {
  cat("\nNOTE: 10% threshold exceeded. Root cause documented in writeup ",
      "(§3 caveat 1 — follower snapshot is end-of-period; 3-season hoopR ",
      "spans players who had left the NBA by the Apr-2026 snapshot). ",
      "Accepting with team-median imputation; robustness check in Phase 7 ",
      "(exclude-2025/26) will revisit.\n", sep = "")
}

# Sum per (game, team): exactly 5 starters per team-game expected (Phase 0 §4.3b
# verified 622/622). If a team-game has > 5 starter==TRUE rows we still take
# the sum — this is how hoopR encodes starters and equals the true lineup sum.
starters_sum <- starters |>
  group_by(hoopr_game_id, team) |>
  summarise(starter_followers_sum = sum(followers_used, na.rm = TRUE),
            n_starters_in_data    = n(),
            n_imputed             = sum(was_imputed),
            .groups = "drop")

# attach to clean (home + away separately)
clean_with_star <- clean |>
  left_join(starters_sum |>
              rename(home_team = team,
                     starting5_followers_home = starter_followers_sum,
                     n_starters_home = n_starters_in_data,
                     n_starters_home_imputed = n_imputed),
            by = c("hoopr_game_id", "home_team")) |>
  left_join(starters_sum |>
              rename(away_team = team,
                     starting5_followers_away = starter_followers_sum,
                     n_starters_away = n_starters_in_data,
                     n_starters_away_imputed = n_imputed),
            by = c("hoopr_game_id", "away_team")) |>
  mutate(starting5_followers_total =
           starting5_followers_home + starting5_followers_away)

# team-handle followers
clean_with_star <- clean_with_star |>
  left_join(team_foll |>
              rename(home_team = team,
                     team_handle_followers_home = team_handle_followers),
            by = "home_team") |>
  left_join(team_foll |>
              rename(away_team = team,
                     team_handle_followers_away = team_handle_followers),
            by = "away_team")

# =============================================================================
# 6.2  MARKET SIZE (team -> DMA -> TVHHs)
# =============================================================================
hr("6.2 MARKET SIZE")

dmas <- read_csv(here("data", "raw", "dmas.csv"),
                 skip = 6, show_col_types = FALSE) |>
  clean_names() |>
  filter(!is.na(dma), !is.na(dma_name))

# Hand-coded team -> DMA name (full Nielsen string) per spec §6.2.
team_dma_map <- tribble(
  ~team,                        ~dma_name,
  "Atlanta Hawks",              "Atlanta, GA",
  "Boston Celtics",             "Boston, MA (Manchester, NH)",
  "Brooklyn Nets",              "New York, NY",
  "Charlotte Hornets",          "Charlotte, NC",
  "Chicago Bulls",              "Chicago, IL",
  "Cleveland Cavaliers",        "Cleveland-Akron (Canton), OH",
  "Dallas Mavericks",           "Dallas-Ft. Worth, TX",
  "Denver Nuggets",             "Denver, CO",
  "Detroit Pistons",            "Detroit, MI",
  "Golden State Warriors",      "San Francisco-Oakland-San Jose, CA",
  "Houston Rockets",            "Houston, TX",
  "Indiana Pacers",             "Indianapolis, IN",
  "LA Clippers",                "Los Angeles, CA",
  "Los Angeles Lakers",         "Los Angeles, CA",
  "Memphis Grizzlies",          "Memphis, TN",
  "Miami Heat",                 "Miami-Ft. Lauderdale, FL",
  "Milwaukee Bucks",            "Milwaukee, WI",
  "Minnesota Timberwolves",     "Minneapolis-St. Paul, MN",
  "New Orleans Pelicans",       "New Orleans, LA",
  "New York Knicks",            "New York, NY",
  "Oklahoma City Thunder",      "Oklahoma City, OK",
  "Orlando Magic",              "Orlando-Daytona Beach-Melbourne, FL",
  "Philadelphia 76ers",         "Philadelphia, PA",
  "Phoenix Suns",               "Phoenix (Prescott), AZ",
  "Portland Trail Blazers",     "Portland, OR",
  "Sacramento Kings",           "Sacramento-Stockton-Modesto, CA",
  "San Antonio Spurs",          "San Antonio, TX",
  "Toronto Raptors",            NA_character_,     # Canadian; impute below
  "Utah Jazz",                  "Salt Lake City, UT",
  "Washington Wizards",         "Washington, DC (Hagerstown, MD)"
)

# Verify every non-NA DMA name in our map actually exists in the file
stopifnot(all(na.omit(team_dma_map$dma_name) %in% dmas$dma_name))

team_tvhhs <- team_dma_map |>
  left_join(dmas |> select(dma_name, total_tvh_hs),
            by = "dma_name") |>
  rename(market_hh = total_tvh_hs)

# Toronto: impute with mean of the 29 US teams' DMA TVHHs
us_mean_tvhhs <- team_tvhhs |>
  filter(team != "Toronto Raptors") |>
  summarise(m = mean(market_hh, na.rm = TRUE)) |>
  pull(m)

team_tvhhs <- team_tvhhs |>
  mutate(is_canadian = team == "Toronto Raptors",
         market_hh = if_else(is.na(market_hh), us_mean_tvhhs, market_hh))

cat("Toronto imputation value (mean of 29 US DMAs):", round(us_mean_tvhhs), "\n")

clean_with_star <- clean_with_star |>
  left_join(team_tvhhs |>
              transmute(home_team = team,
                        market_hh_home = market_hh,
                        home_is_canadian = is_canadian),
            by = "home_team") |>
  left_join(team_tvhhs |>
              transmute(away_team = team,
                        market_hh_away = market_hh,
                        away_is_canadian = is_canadian),
            by = "away_team") |>
  mutate(market_hh_combined = market_hh_home + market_hh_away,
         team_is_canadian   = home_is_canadian | away_is_canadian)

# =============================================================================
# 6.3  TEAM FORM  (season W%, last-5 W%, won_last, on_fire) — leakage-safe
# =============================================================================
hr("6.3 TEAM FORM")

cat("loading hoopR team_box for 2024..2026...\n")
tb <- load_nba_team_box(seasons = 2024:2026)

# Build one row per (team, game) with a W/L indicator, dropping All-Star games
# and games that post-date our modeling window.
team_games <- tb |>
  filter(!team_display_name %in% c("Eastern Conf All-Stars",
                                   "Western Conf All-Stars"),
         !opponent_team_display_name %in% c("Eastern Conf All-Stars",
                                            "Western Conf All-Stars"),
         season_type %in% c(2, 3)) |>            # 2 = regular, 3 = post
  transmute(game_id = as.integer(game_id),
            game_date = as.Date(game_date),
            season   = as.integer(season),
            team     = if_else(team_display_name == "LA Clippers",
                               "LA Clippers", team_display_name),
            team_winner = team_winner) |>
  arrange(team, season, game_date, game_id) |>
  distinct(team, game_id, .keep_all = TRUE)

# Per-team rolling, strictly-prior stats. lag() shifts so row i sees only
# games 1..i-1 within the same team-season.
team_form <- team_games |>
  group_by(team, season) |>
  mutate(
    prior_games       = row_number() - 1L,
    prior_wins        = cumsum(team_winner) - team_winner,
    season_win_pct    = if_else(prior_games > 0,
                                prior_wins / prior_games, NA_real_),
    # last-5 rolling W% on strictly-prior games
    last5_win_pct = {
      w <- team_winner
      # rolling mean of previous 5 outcomes (exclusive of current)
      n <- length(w)
      out <- rep(NA_real_, n)
      for (i in seq_len(n)) {
        lo <- max(1L, i - 5L); hi <- i - 1L
        if (hi >= lo && (hi - lo + 1L) == 5L) {
          out[i] <- mean(w[lo:hi])
        }
      }
      out
    },
    won_last = lag(team_winner),
    on_fire  = as.integer(!is.na(last5_win_pct) & last5_win_pct >= 0.6 &
                          !is.na(won_last) & won_last == 1)
  ) |>
  ungroup() |>
  select(game_id, team, season_win_pct, last5_win_pct,
         won_last, on_fire)

clean_with_form <- clean_with_star |>
  left_join(team_form |>
              rename(home_team = team,
                     home_season_win_pct = season_win_pct,
                     home_last5_win_pct  = last5_win_pct,
                     home_won_last       = won_last,
                     home_on_fire        = on_fire),
            by = c("hoopr_game_id" = "game_id", "home_team")) |>
  left_join(team_form |>
              rename(away_team = team,
                     away_season_win_pct = season_win_pct,
                     away_last5_win_pct  = last5_win_pct,
                     away_won_last       = won_last,
                     away_on_fire        = on_fire),
            by = c("hoopr_game_id" = "game_id", "away_team")) |>
  mutate(on_fire_either =
           as.integer(coalesce(home_on_fire, 0L) == 1L |
                      coalesce(away_on_fire, 0L) == 1L))

# =============================================================================
# 6.4  MATCHUP QUALITY
# =============================================================================
hr("6.4 MATCHUP QUALITY")

# Derive playoff_stakes from season_type + program/episode text. Coarse levels:
#   regular, play_in, round1, round2, conf_finals, finals.
# We rely on the raw program/episode string from Phase 1 outputs — but those
# aren't carried in clean. Re-read the raw file once to pick up PROGRAM for
# POST SEASON rows only.
rat_raw <- read_csv(
  here("data", "raw", "nba_national_ratings.csv"),
  show_col_types = FALSE
) |>
  clean_names() |>
  mutate(raw_row_id = row_number(),
         program_upper = str_to_upper(program),
         episode_upper = str_to_upper(episode))

program_lookup <- rat_raw |>
  select(raw_row_id, program_upper, episode_upper)

clean_with_form <- clean_with_form |>
  left_join(program_lookup, by = "raw_row_id") |>
  mutate(
    combined_season_win_pct =
      (coalesce(home_season_win_pct, NA_real_) +
       coalesce(away_season_win_pct, NA_real_)) / 2,
    playoff_stakes = factor(case_when(
      season_type != "POST SEASON"                           ~ "regular",
      str_detect(program_upper, "FINAL") &
        str_detect(program_upper, "CONF")                    ~ "conf_finals",
      str_detect(program_upper, "NBA FINAL")                 ~ "finals",
      str_detect(program_upper, "FINAL")                     ~ "finals",
      str_detect(program_upper, "CONF")                      ~ "conf_finals",
      str_detect(program_upper, "PLAY.?IN") |
        str_detect(episode_upper, "PLAY.?IN")                ~ "play_in",
      str_detect(program_upper, "SECOND ROUND|ROUND 2|RD 2") ~ "round2",
      str_detect(program_upper, "FIRST ROUND|ROUND 1|RD 1") ~ "round1",
      TRUE                                                    ~ "round1"
    ), levels = c("regular", "play_in", "round1", "round2",
                  "conf_finals", "finals"))
  )

cat("playoff_stakes distribution:\n")
print(table(clean_with_form$playoff_stakes, useNA = "ifany"))

# =============================================================================
# 6.5  NETWORK / DISTRIBUTION
# =============================================================================
hr("6.5 NETWORK / DISTRIBUTION")

net_counts <- table(clean_with_form$network)
cat("raw network levels:\n"); print(net_counts)

# Collapse any network level with < 10 rows into its primary component.
# For rollup combos (e.g. "ESPN+ESPN2", "TNT+TRUTV"), collapse to the first token.
clean_with_form <- clean_with_form |>
  mutate(network_raw = as.character(network),
         network_primary = str_split_fixed(network_raw, "\\+", 2)[, 1],
         network_group = if_else(net_counts[network_raw] < 10,
                                 network_primary, network_raw),
         network = factor(network_group),
         is_broadcast = as.integer(str_detect(network_group, "ABC|NBC")),
         post_new_deal = as.integer(season == "2025/2026")) |>
  select(-network_raw, -network_primary, -network_group)

cat("\ncollapsed network levels:\n")
print(table(clean_with_form$network))

# =============================================================================
# 6.6  TIMING
# =============================================================================
hr("6.6 TIMING")

# Holidays (hand-coded for the 3 seasons in scope)
holidays <- as.Date(c(
  # 2023/24 season
  "2023-11-23", "2023-12-25", "2024-01-01", "2024-01-15",
  # 2024/25 season
  "2024-11-28", "2024-12-25", "2025-01-01", "2025-01-20",
  # 2025/26 season (partial)
  "2025-11-27", "2025-12-25", "2026-01-01", "2026-01-19"
))

clean_final <- clean_with_form |>
  mutate(
    day_of_week = factor(weekdays(game_date),
                         levels = c("Monday","Tuesday","Wednesday",
                                    "Thursday","Friday","Saturday","Sunday")),
    is_weekend  = as.integer(day_of_week %in% c("Saturday","Sunday")),
    tip_hour    = as.integer(hms::as_hms(telecast_time)) %/% 3600L,
    time_slot   = factor(case_when(
      tip_hour < 18  ~ "early",
      tip_hour < 22  ~ "primetime",
      TRUE           ~ "late"
    ), levels = c("early", "primetime", "late")),
    is_holiday  = as.integer(game_date %in% holidays)
  )

# =============================================================================
# MISSINGNESS SUMMARY
# =============================================================================
hr("MISSINGNESS SUMMARY (modeling columns)")

model_cols <- c(
  "p2_plus", "p18_49",
  "starting5_followers_home", "starting5_followers_away",
  "starting5_followers_total",
  "team_handle_followers_home", "team_handle_followers_away",
  "market_hh_home", "market_hh_away", "market_hh_combined",
  "home_season_win_pct", "away_season_win_pct",
  "home_last5_win_pct", "away_last5_win_pct",
  "on_fire_either",
  "combined_season_win_pct",
  "playoff_stakes", "network", "is_broadcast", "post_new_deal",
  "day_of_week", "time_slot", "is_holiday", "is_weekend"
)

miss_tbl <- clean_final |>
  summarise(across(all_of(model_cols), ~ sum(is.na(.)))) |>
  pivot_longer(everything(), names_to = "column", values_to = "n_missing") |>
  mutate(pct_missing = round(100 * n_missing / nrow(clean_final), 2)) |>
  arrange(desc(n_missing))

print(miss_tbl, n = Inf)

# Breakdown of missingness: nearly all NAs should come from the 18 hoopR-
# unmatched rows (no hoopR_game_id → no starters, no team form). Confirm.
unmatched_n <- sum(!clean_final$matched_to_hoopr)
cat(sprintf("\nhoopR-unmatched rows: %d (should dominate the NA counts)\n",
            unmatched_n))

# Additional NA source: first-game-of-season rows (no prior games → NA form).
first_game_na <- clean_final |>
  filter(matched_to_hoopr,
         (is.na(home_season_win_pct) | is.na(away_season_win_pct))) |>
  nrow()
cat(sprintf("matched rows with NA season_win_pct (first-game-of-season): %d\n",
            first_game_na))

# =============================================================================
# SAVE
# =============================================================================
hr("SAVING")

# Drop the helper columns the model doesn't need, keep a lean processed df.
processed_cols <- c(
  # keys / identifiers
  "game_id", "game_date", "season", "season_type",
  "home_team", "away_team",
  "hoopr_game_id", "matched_to_hoopr",
  # targets
  "p2_plus", "p18_49",
  # star power
  "starting5_followers_home", "starting5_followers_away",
  "starting5_followers_total",
  "team_handle_followers_home", "team_handle_followers_away",
  "n_starters_home_imputed", "n_starters_away_imputed",
  # market
  "market_hh_home", "market_hh_away", "market_hh_combined",
  "team_is_canadian",
  # form
  "home_season_win_pct", "away_season_win_pct",
  "home_last5_win_pct", "away_last5_win_pct",
  "home_won_last", "away_won_last",
  "home_on_fire", "away_on_fire", "on_fire_either",
  # matchup
  "combined_season_win_pct", "playoff_stakes",
  # network
  "network", "is_broadcast", "post_new_deal",
  # timing
  "day_of_week", "time_slot", "is_holiday", "is_weekend",
  "telecast_time", "duration_min"
)

model_data <- clean_final |> select(all_of(processed_cols))

dir.create(here("data", "processed"), showWarnings = FALSE, recursive = TRUE)
saveRDS(model_data, here("data", "processed", "model_data.rds"))

feature_summary <- list(
  n_rows                = nrow(model_data),
  starter_imputation_rate = imputation_rate,
  starter_match_rate    = n_matched_starter / n_starter_rows,
  toronto_impute_value  = us_mean_tvhhs,
  network_levels        = levels(model_data$network),
  playoff_stakes_tbl    = table(model_data$playoff_stakes, useNA = "ifany"),
  missingness           = miss_tbl,
  unmatched_n           = unmatched_n,
  first_game_na_n       = first_game_na
)
saveRDS(feature_summary,
        here("data", "interim", "phase2_feature_summary.rds"))

cat("\nWrote:\n")
cat("  data/processed/model_data.rds\n")
cat("  data/interim/phase2_feature_summary.rds\n")
cat(sprintf("\nFinal modeling table: %d rows × %d cols\n",
            nrow(model_data), ncol(model_data)))
