set.seed(4010)

project_path <- function(...) file.path(getwd(), ...)

d <- readRDS(project_path("data", "processed", "model_data.rds"))
m_primary <- readRDS(project_path("data", "processed", "primary_model.rds"))

required <- c(
  "p2_plus", "starting5_followers_total",
  "team_handle_followers_home", "team_handle_followers_away",
  "market_hh_combined",
  "home_last5_win_pct", "away_last5_win_pct", "on_fire_either",
  "combined_season_win_pct", "playoff_stakes", "network",
  "time_slot", "is_holiday", "is_weekend",
  "game_date", "season"
)

season_end <- aggregate(game_date ~ season, data = d[d$playoff_stakes == "regular", ],
                        FUN = max)
names(season_end)[2] <- "reg_end"

d <- merge(d, season_end, by = "season", all.x = TRUE, sort = FALSE)
d$weeks_until_regular_end <- as.numeric(d$reg_end - d$game_date) / 7

d_reg <- d[d$playoff_stakes == "regular", c(required, "weeks_until_regular_end")]
d_reg <- droplevels(d_reg[stats::complete.cases(d_reg), ])

primary_rhs <- paste(deparse(formula(m_primary)[[3]]), collapse = " ")
f1_rhs <- gsub("\\s*\\+\\s*playoff_stakes", "", primary_rhs)

form_F1 <- as.formula(paste("log(p2_plus) ~", f1_rhs))
form_F2 <- as.formula(paste("log(p2_plus) ~", f1_rhs, "+ weeks_until_regular_end"))

m_F1 <- lm(form_F1, data = d_reg)
m_F2 <- lm(form_F2, data = d_reg)

tidy_model <- function(model, label) {
  coef_mat <- summary(model)$coefficients
  ci_mat <- confint(model)

  data.frame(
    model = label,
    term = rownames(coef_mat),
    estimate = coef_mat[, "Estimate"],
    std.error = coef_mat[, "Std. Error"],
    statistic = coef_mat[, "t value"],
    p.value = coef_mat[, "Pr(>|t|)"],
    conf.low = ci_mat[, 1],
    conf.high = ci_mat[, 2],
    row.names = NULL,
    check.names = FALSE
  )
}

coef_tbl <- rbind(
  tidy_model(m_F1, "F1_regular_only"),
  tidy_model(m_F2, "F2_regular_plus_season_timing")
)

summary_tbl <- data.frame(
  model = c("F1_regular_only", "F2_regular_plus_season_timing"),
  n = c(stats::nobs(m_F1), stats::nobs(m_F2)),
  r_squared = c(summary(m_F1)$r.squared, summary(m_F2)$r.squared),
  adj_r_squared = c(summary(m_F1)$adj.r.squared, summary(m_F2)$adj.r.squared),
  row.names = NULL,
  check.names = FALSE
)

write.csv(
  coef_tbl,
  project_path("outputs", "tables", "tbl5_regular_season_coefficients.csv"),
  row.names = FALSE
)

write.csv(
  summary_tbl,
  project_path("outputs", "tables", "tbl5_regular_season_model_summary.csv"),
  row.names = FALSE
)

cat("Wrote:\n")
cat("  outputs/tables/tbl5_regular_season_coefficients.csv\n")
cat("  outputs/tables/tbl5_regular_season_model_summary.csv\n")
