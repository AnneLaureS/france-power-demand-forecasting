# Installs the CRAN packages required by modele_final.R.
# Run once:  Rscript install_packages.R

packages <- c(
  "mgcv",        # GAM
  "qgam",        # additive quantile regression
  "forecast",    # auto.arima
  "opera",       # expert aggregation (MLpol)
  "data.table",  # fread
  "readr",       # read_delim
  "dplyr",       # filter, %>%
  "magrittr"     # %>%
)

missing <- setdiff(packages, rownames(installed.packages()))

if (length(missing) == 0) {
  message("All packages are already installed.")
} else {
  message("Installing: ", paste(missing, collapse = ", "))
  install.packages(missing, repos = "https://cloud.r-project.org")
}
