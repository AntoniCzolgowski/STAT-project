suppressPackageStartupMessages({
  library(dplyr); library(here); library(broom); library(lmtest); library(sandwich)
})
m <- readRDS(here("data","processed","primary_model.rds"))
vc <- sandwich::vcovHC(m, type = "HC3")
tr <- broom::tidy(coeftest(m, vcov. = vc), conf.int = TRUE)
print(tr |> mutate(across(where(is.numeric), \(x) signif(x, 3))), n = Inf)
