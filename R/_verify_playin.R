suppressPackageStartupMessages({library(dplyr); library(here)})
m <- readRDS(here("data","processed","primary_model.rds"))
d <- readRDS(here("data","processed","model_data.rds"))

cat("== levels in fit ==\n")
fm <- model.frame(m)
print(levels(fm$playoff_stakes))
print(table(fm$playoff_stakes, useNA="ifany"))

cat("\n== full coef vector length & names ==\n")
cat(length(coef(m)), "coefs\n")
print(names(coef(m)))

cat("\n== model.matrix columns ==\n")
X <- model.matrix(m)
print(colnames(X))
print(ncol(X))
