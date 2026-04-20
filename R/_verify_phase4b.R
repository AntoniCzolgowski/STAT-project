suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(here); library(broom)
  library(lmtest); library(sandwich); library(car)
})

m <- readRDS(here("data","processed","primary_model.rds"))
d <- readRDS(here("data","processed","model_data.rds"))

# -----------------------------------------------------------------
# (A) HC3 vs classical: sign-flip check on significance
# -----------------------------------------------------------------
cat("== (A) HC3 vs classical inference ==\n")
tc <- broom::tidy(m, conf.int = TRUE)
vc <- sandwich::vcovHC(m, type = "HC3")
tr <- broom::tidy(coeftest(m, vcov. = vc), conf.int = TRUE)

cmp <- tc |> select(term, est = estimate, p_cls = p.value) |>
  left_join(tr |> select(term, p_hc3 = p.value), by = "term") |>
  mutate(sig_cls = p_cls < 0.05, sig_hc3 = p_hc3 < 0.05,
         flip = sig_cls != sig_hc3)
print(cmp, n = Inf)

cat("\nterms where significance flips between classical and HC3:\n")
print(cmp |> filter(flip))

cat("\nmax |p_hc3 - p_cls| among 'sig under classical':\n")
print(cmp |> filter(sig_cls) |>
        mutate(dp = abs(p_hc3 - p_cls)) |>
        arrange(desc(dp)) |> head(5))

# -----------------------------------------------------------------
# (B) condition number of design + max VIF
# -----------------------------------------------------------------
cat("\n== (B) design conditioning ==\n")
X <- model.matrix(m)
kap <- kappa(X, exact = TRUE)
cat(sprintf("kappa(X) exact = %.1f (>1000 = concerning)\n", kap))

# -----------------------------------------------------------------
# (C) condition if we drop 2025/26 (exclude-post-new-deal scenario)
# -----------------------------------------------------------------
cat("\n== (C) Refit excluding 2025/26 (the natural post-new-deal robustness) ==\n")
fitted_rows <- as.integer(rownames(model.frame(m)))
df_fit <- d[fitted_rows, ]
cat("seasons in fitted data:\n"); print(table(df_fit$season))

df_pre <- df_fit |> filter(season != "2025/2026")
cat(sprintf("pre-2025/26 rows: %d (of %d)\n", nrow(df_pre), nrow(df_fit)))

# Drop levels that vanish
df_pre <- df_pre |> mutate(across(where(is.factor), droplevels))
cat("remaining network levels:\n"); print(table(df_pre$network))
cat("remaining playoff_stakes levels:\n"); print(table(df_pre$playoff_stakes))

m_pre <- update(m, data = df_pre)
cat(sprintf("\npre-2025/26: n=%d  R^2=%.4f  adj R^2=%.4f\n",
            nobs(m_pre), summary(m_pre)$r.squared, summary(m_pre)$adj.r.squared))

cat("\ncoef deltas (full vs pre-2025/26), top 8 by |delta|:\n")
co_full <- coef(m); co_pre <- coef(m_pre)
shared <- intersect(names(co_full), names(co_pre))
delta <- tibble(term = shared,
                full = co_full[shared],
                pre  = co_pre[shared]) |>
  mutate(abs_d = abs(full - pre)) |>
  arrange(desc(abs_d))
print(delta |> head(10))

# -----------------------------------------------------------------
# (D) NBC / post-new-deal confound magnitude
# -----------------------------------------------------------------
cat("\n== (D) NBC × season crosstab ==\n")
print(table(df_fit$network, df_fit$season))
cat("\n== (D) network × (season == 2025/26) confound ==\n")
df_fit <- df_fit |> mutate(post = season == "2025/2026")
print(table(df_fit$network, df_fit$post))

# -----------------------------------------------------------------
# (E) relaimpo availability?
# -----------------------------------------------------------------
cat("\n== (E) package availability ==\n")
cat("relaimpo installed:", requireNamespace("relaimpo", quietly=TRUE), "\n")
cat("hier.part installed:", requireNamespace("hier.part", quietly=TRUE), "\n")
