suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(here); library(broom)
})

m <- readRDS(here("data","processed","primary_model.rds"))
d <- readRDS(here("data","processed","model_data.rds"))

cat("== n obs used in fit:", nobs(m), "\n")

co <- coef(m)
cat("\n== NA coefficients (aliased) ==\n")
print(co[is.na(co)])

cat("\n== All coefficients ==\n")
print(co)

cat("\n== alias() summary ==\n")
a <- alias(m)
print(a)

cat("\n== playoff_stakes levels and counts in fitted data ==\n")
fitted_rows <- rownames(model.frame(m))
df_fit <- d[as.integer(fitted_rows), ]
print(table(df_fit$playoff_stakes, useNA="ifany"))

cat("\n== finals × network ==\n")
print(table(df_fit$playoff_stakes, df_fit$network, useNA="ifany"))

cat("\n== finals × is_weekend ==\n")
print(table(df_fit$playoff_stakes, df_fit$is_weekend, useNA="ifany"))

cat("\n== finals × time_slot ==\n")
print(table(df_fit$playoff_stakes, df_fit$time_slot, useNA="ifany"))

cat("\n== finals × is_holiday ==\n")
print(table(df_fit$playoff_stakes, df_fit$is_holiday, useNA="ifany"))
