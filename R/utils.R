# R/utils.R
# Shared helpers for the pipeline. Keep this file small and pure
# (no I/O at load time, no library() calls beyond what's required).

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(tibble)
})

# -------------------------------------------------------------------------
# Team name canonicalization
# -------------------------------------------------------------------------
# EPISODE strings in nba_national_ratings.csv appear in two formats:
#   (a) "AWAY AT HOME" using nicknames ("MAVERICKS AT CELTICS")
#   (b) "AWAY/HOME"    mostly using cities ("ATLANTA/CHICAGO")
# The same ratings file mixes the two; some tokens are qualified
# ("NY KNICKS", "LA CLIPPERS") in either format for disambiguation.
#
# The map below covers every variant observed so far. Canonical names
# match hoopR team_display_name (ESPN convention).

.TEAM_VARIANTS <- tribble(
  ~variant,                      ~canonical,
  # Atlanta Hawks
  "HAWKS",                       "Atlanta Hawks",
  "ATLANTA",                     "Atlanta Hawks",
  "ATLANTA HAWKS",               "Atlanta Hawks",
  # Boston Celtics
  "CELTICS",                     "Boston Celtics",
  "BOSTON",                      "Boston Celtics",
  "BOSTON CELTICS",              "Boston Celtics",
  # Brooklyn Nets
  "NETS",                        "Brooklyn Nets",
  "BROOKLYN",                    "Brooklyn Nets",
  "BROOKLYN NETS",               "Brooklyn Nets",
  # Charlotte Hornets
  "HORNETS",                     "Charlotte Hornets",
  "CHARLOTTE",                   "Charlotte Hornets",
  "CHARLOTTE HORNETS",           "Charlotte Hornets",
  # Chicago Bulls
  "BULLS",                       "Chicago Bulls",
  "CHICAGO",                     "Chicago Bulls",
  "CHICAGO BULLS",               "Chicago Bulls",
  # Cleveland Cavaliers
  "CAVALIERS",                   "Cleveland Cavaliers",
  "CAVS",                        "Cleveland Cavaliers",
  "CLEVELAND",                   "Cleveland Cavaliers",
  "CLEVELAND CAVALIERS",         "Cleveland Cavaliers",
  # Dallas Mavericks
  "MAVERICKS",                   "Dallas Mavericks",
  "MAVS",                        "Dallas Mavericks",
  "DALLAS",                      "Dallas Mavericks",
  "DALLAS MAVERICKS",            "Dallas Mavericks",
  # Denver Nuggets
  "NUGGETS",                     "Denver Nuggets",
  "DENVER",                      "Denver Nuggets",
  "DENVER NUGGETS",              "Denver Nuggets",
  # Detroit Pistons
  "PISTONS",                     "Detroit Pistons",
  "DETROIT",                     "Detroit Pistons",
  "DETROIT PISTONS",             "Detroit Pistons",
  # Golden State Warriors
  "WARRIORS",                    "Golden State Warriors",
  "GOLDEN STATE",                "Golden State Warriors",
  "GOLDEN STATE WARRIORS",       "Golden State Warriors",
  "GOLDEN STATE WAR",            "Golden State Warriors",   # EPISODE truncation
  "GOLDEN STATE WARRI",          "Golden State Warriors",   # EPISODE truncation
  # Houston Rockets
  "ROCKETS",                     "Houston Rockets",
  "HOUSTON",                     "Houston Rockets",
  "HOUSTON ROCKETS",             "Houston Rockets",
  # Indiana Pacers
  "PACERS",                      "Indiana Pacers",
  "INDIANA",                     "Indiana Pacers",
  "INDIANA PACERS",              "Indiana Pacers",
  # LA Clippers (hoopR uses "LA Clippers")
  "CLIPPERS",                    "LA Clippers",
  "CLIPPER",                     "LA Clippers",  # observed typo
  "LA CLIPPERS",                 "LA Clippers",
  "LOS ANGELES CLIPPERS",        "LA Clippers",
  # Los Angeles Lakers
  # NOTE: bare "LOS ANGELES" is ambiguous in principle (Lakers vs Clippers),
  # but in THIS corpus the Clippers are always written "LA CLIPPERS" /
  # "CLIPPERS" / "CLIPPER", never "LOS ANGELES". The single slash-format
  # row "LOS ANGELES/MINNESOTA" (2025-10-29) was verified against hoopR
  # as Lakers @ Minnesota. Mapping "LOS ANGELES" -> Lakers is therefore
  # correct in this corpus; revisit if the dataset expands.
  "LAKERS",                      "Los Angeles Lakers",
  "LA LAKERS",                   "Los Angeles Lakers",
  "LOS ANGELES",                 "Los Angeles Lakers",
  "LOS ANGELES LAKERS",          "Los Angeles Lakers",
  # Memphis Grizzlies
  "GRIZZLIES",                   "Memphis Grizzlies",
  "MEMPHIS",                     "Memphis Grizzlies",
  "MEMPHIS GRIZZLIES",           "Memphis Grizzlies",
  # Miami Heat
  "HEAT",                        "Miami Heat",
  "MIAMI",                       "Miami Heat",
  "MIAMI HEAT",                  "Miami Heat",
  # Milwaukee Bucks
  "BUCKS",                       "Milwaukee Bucks",
  "MILWAUKEE",                   "Milwaukee Bucks",
  "MILWAUKEE BUCKS",             "Milwaukee Bucks",
  # Minnesota Timberwolves
  "TIMBERWOLVES",                "Minnesota Timberwolves",
  "WOLVES",                      "Minnesota Timberwolves",
  "MINNESOTA",                   "Minnesota Timberwolves",
  "MINNESOTA TIMBERWOLVES",      "Minnesota Timberwolves",
  # New Orleans Pelicans
  "PELICANS",                    "New Orleans Pelicans",
  "NEW ORLEANS",                 "New Orleans Pelicans",
  "NEW ORLEANS PELICANS",        "New Orleans Pelicans",
  # New York Knicks
  # NOTE: the ratings file also uses bare "NEW YORK" for the Knicks in slash-
  # format playoff rows (e.g., "NEW YORK/INDIANA", "PHILADELPHIA/NEW YORK").
  # Brooklyn is never abbreviated to "NEW YORK" in this file — it appears as
  # "NETS" or "BROOKLYN". Mapping NEW YORK -> Knicks is therefore correct in
  # this corpus but a human should double-check if the dataset expands.
  "KNICKS",                      "New York Knicks",
  "NY KNICKS",                   "New York Knicks",
  "NEW YORK",                    "New York Knicks",
  "NEW YORK KNICKS",             "New York Knicks",
  "KNICKRBCKRS",                 "New York Knicks",  # observed shorthand
  "KNICKERBOCKERS",              "New York Knicks",
  # Oklahoma City Thunder
  "THUNDER",                     "Oklahoma City Thunder",
  "OKC THUNDER",                 "Oklahoma City Thunder",
  "OKC",                         "Oklahoma City Thunder",
  "OKLAHOMA",                    "Oklahoma City Thunder",  # short form seen in slash rows
  "OKLAHOMA CITY",               "Oklahoma City Thunder",
  "OKLAHOMA CITY THUNDER",       "Oklahoma City Thunder",
  # Orlando Magic
  "MAGIC",                       "Orlando Magic",
  "ORLANDO",                     "Orlando Magic",
  "ORLANDO MAGIC",               "Orlando Magic",
  # Philadelphia 76ers
  "76ERS",                       "Philadelphia 76ers",
  "76'ERS",                      "Philadelphia 76ers",
  "SIXERS",                      "Philadelphia 76ers",
  "PHILADELPHIA",                "Philadelphia 76ers",
  "PHILADELPHIA 76ERS",          "Philadelphia 76ers",
  "PHILADELPHIA 76'ERS",         "Philadelphia 76ers",
  # Phoenix Suns
  "SUNS",                        "Phoenix Suns",
  "PHOENIX",                     "Phoenix Suns",
  "PHOENIX SUNS",                "Phoenix Suns",
  # Portland Trail Blazers
  "TRAIL BLAZERS",               "Portland Trail Blazers",
  "TRAILBLAZERS",                "Portland Trail Blazers",  # no-space variant
  "BLAZERS",                     "Portland Trail Blazers",
  "PORTLAND",                    "Portland Trail Blazers",
  "PORTLAND TRAIL BLAZERS",      "Portland Trail Blazers",
  # Sacramento Kings
  "KINGS",                       "Sacramento Kings",
  "SACRAMENTO",                  "Sacramento Kings",
  "SACRAMENTO KINGS",            "Sacramento Kings",
  # San Antonio Spurs
  "SPURS",                       "San Antonio Spurs",
  "SAN ANTONIO",                 "San Antonio Spurs",
  "SAN ANTONIO SPURS",           "San Antonio Spurs",
  # Toronto Raptors
  "RAPTORS",                     "Toronto Raptors",
  "TORONTO",                     "Toronto Raptors",
  "TORONTO RAPTORS",             "Toronto Raptors",
  # Utah Jazz
  "JAZZ",                        "Utah Jazz",
  "UTAH",                        "Utah Jazz",
  "UTAH JAZZ",                   "Utah Jazz",
  # Washington Wizards
  "WIZARDS",                     "Washington Wizards",
  "WASHINGTON",                  "Washington Wizards",
  "WASHINGTON WIZARDS",          "Washington Wizards"
)

# Reusable named lookup vector: variant -> canonical
.TEAM_LOOKUP <- setNames(.TEAM_VARIANTS$canonical, .TEAM_VARIANTS$variant)

#' Strip broadcast-metadata suffixes from an episode token.
#'
#' Broadcast metadata attached to team names in EPISODE strings:
#'   "-ST"          — Spanish-audio simulcast marker
#'   " GM3"/"GM4"…  — playoff series game number
#'   " +(ESPN+)"    — simulcast on ESPN+ streaming (many whitespace variants)
#'   trailing punctuation
.strip_token_metadata <- function(tok) {
  x <- tok
  # " +(ESPN+)" and variants with or without spaces/parens
  x <- stringr::str_replace(x, "\\s*\\+\\s*\\(?ESPN\\+\\)?\\s*$", "")
  # trailing "GM<digits>" (possibly preceded by whitespace)
  x <- stringr::str_replace(x, "\\s+GM\\s*\\d+\\s*$", "")
  # trailing "-ST"
  x <- stringr::str_replace(x, "-ST\\s*$", "")
  # collapse internal whitespace and trim
  x <- stringr::str_squish(x)
  x
}

#' Canonicalize a team token (e.g., "LAKERS", "76'ERS", "NY KNICKS").
#' Vectorized. Unknown tokens return NA_character_.
canonicalize_team <- function(tok) {
  tok_up <- stringr::str_to_upper(stringr::str_trim(tok))
  tok_up <- .strip_token_metadata(tok_up)
  unname(.TEAM_LOOKUP[tok_up])
}

# -------------------------------------------------------------------------
# EPISODE parser
# -------------------------------------------------------------------------
# Returns a tibble with one row per input: away, home, parse_status.
# parse_status in {"ok", "unparseable", "unknown_team"}.

parse_episode <- function(episode) {
  ep <- stringr::str_trim(episode)

  # Four observed separators:
  #   " AT "    — standard regular-season EPISODE ("MAVERICKS AT CELTICS")
  #   " VS " / " VS. " — NBA Cup / In-Season Tournament ("KNICKS VS. MAGIC")
  #   "/"       — playoff shorthand ("ATLANTA/CHICAGO", city-based)
  sep_at    <- stringr::str_detect(ep, "\\s+AT\\s+")
  sep_vs    <- stringr::str_detect(ep, "\\s+VS\\.?\\s+")
  sep_slash <- stringr::str_detect(ep, "/")

  away <- rep(NA_character_, length(ep))
  home <- rep(NA_character_, length(ep))

  idx_at <- which(sep_at)
  if (length(idx_at)) {
    parts <- stringr::str_split_fixed(ep[idx_at], "\\s+AT\\s+", 2)
    away[idx_at] <- parts[, 1]
    home[idx_at] <- parts[, 2]
  }

  idx_vs <- which(!sep_at & sep_vs)
  if (length(idx_vs)) {
    parts <- stringr::str_split_fixed(ep[idx_vs], "\\s+VS\\.?\\s+", 2)
    # "VS" has no hard directional convention; by inspection of NBA Cup rows,
    # the pattern appears to be "AWAY VS HOME" (marquee games usually list
    # the road team first). The hoopR-match stage also tries swapped order.
    away[idx_vs] <- parts[, 1]
    home[idx_vs] <- parts[, 2]
  }

  idx_sl <- which(!sep_at & !sep_vs & sep_slash)
  if (length(idx_sl)) {
    parts <- stringr::str_split_fixed(ep[idx_sl], "/", 2)
    away[idx_sl] <- parts[, 1]
    home[idx_sl] <- parts[, 2]
  }

  # Canonicalize
  away_c <- canonicalize_team(away)
  home_c <- canonicalize_team(home)

  parse_status <- dplyr::case_when(
    is.na(away) | is.na(home)       ~ "unparseable",
    is.na(away_c) | is.na(home_c)   ~ "unknown_team",
    TRUE                             ~ "ok"
  )

  tibble::tibble(
    episode_raw  = episode,
    away_raw     = away,
    home_raw     = home,
    away_team    = away_c,
    home_team    = home_c,
    parse_status = parse_status
  )
}

# -------------------------------------------------------------------------
# Convenience: season label <-> hoopR season (ending year)
# -------------------------------------------------------------------------
season_label_to_end_year <- function(label) {
  # "2023/2024" -> 2024
  as.integer(stringr::str_sub(label, -4))
}
