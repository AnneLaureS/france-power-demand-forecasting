# Installe les packages CRAN nécessaires à modele_final.R.
# À lancer une seule fois :  Rscript install_packages.R

packages <- c(
  "mgcv",        # GAM
  "qgam",        # regression quantile additive
  "forecast",    # auto.arima
  "opera",       # agregation d'experts (MLpol)
  "data.table",  # fread
  "readr",       # read_delim
  "dplyr",       # filter, %>%
  "magrittr"     # %>%
)

manquants <- setdiff(packages, rownames(installed.packages()))

if (length(manquants) == 0) {
  message("Tous les packages sont deja installes.")
} else {
  message("Installation de : ", paste(manquants, collapse = ", "))
  install.packages(manquants, repos = "https://cloud.r-project.org")
}
