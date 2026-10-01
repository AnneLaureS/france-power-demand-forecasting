# Forecasting French Electricity Demand

Quantile forecasting of French **net electricity demand**
(`Net_demand = Load − Solar_power − Wind_power`) over the energy-sobriety period,
evaluated with the **pinball loss**.

Predictive Modelling project (M1 Mathematics & AI, Université Paris-Saclay) —
Anne-Laure Sulmont and Amjad Proietti.

The full write-up is in [`Rapport.pdf`](Rapport.pdf).

---

## Approach

Rather than modelling net demand directly, we decompose the problem into
**three separate GAMs** whose forecasts are then recombined:

| Model | Target | Main effects |
|---|---|---|
| `gam_load` | `Load` | `toy` (cyclic), `Temp`, `Load.1`, `WeekDays` |
| `gam_solar` | `Solar_power` | `toy`, smoothed temperatures, `Nebulosity × toy` (tensor), lags, calendar |
| `gam_wind` | `Wind_power` | `toy`, `Wind`, `Wind_weighted`, lags, `Nebulosity`, calendar |

The mean forecast is `pred_load − pred_wind − pred_solar`.

Three refinements follow:

1. **ARIMA residual correction** — an `auto.arima` is fitted to the net-demand residuals
   on the validation set, then extrapolated over the test horizon.
2. **Moving to quantiles** — for each `τ ∈ {0.3, 0.5, 0.8}` two shifts are computed: a
   **Gaussian** quantile (`μ + qnorm(τ)·σ` on the residuals) and an **empirical** quantile
   (`quantile(residuals, τ)`).
3. **Additive quantile regression** — a `qgam` fitted directly on `Net_demand`, with a
   richer feature set (ENTSO-E prices, lockdown indicator).

Finally these predictors are combined by **expert aggregation** (`opera::mixture`,
`MLpol` algorithm, pinball loss):

```
qgam  |  3 models + Gaussian quantile  |  ARIMA + Gaussian quantile
      |  3 models + empirical quantile  |  ARIMA + empirical quantile
```

### Added features

- **Electricity prices** (ENTSO-E, 2015–2023): `mean`, `min`, `std`, `night_mean`,
  `ramp_18_6` and others, joined on date.
- **Lockdowns**: indicator for the three French lockdowns (Mar–May 2020,
  Oct–Dec 2020, Apr–May 2021).

---

## Repository layout

```
.
├── modele_final.R          # full pipeline: data → 3 GAMs → ARIMA → qgam → aggregation
├── install_packages.R      # installs the CRAN dependencies
├── Script/
│   └── score.R             # metrics: pinball_loss, rmse, mape, bias
├── Data/
│   ├── ENTSOEDailyFeatures20152023.csv                   # ENTSO-E prices (';' separated)
│   └── net-load-forecasting-during-soberty-period/
│       ├── train.csv       # 3,471 days, 39 columns (with the target)
│       └── test.csv        # 395 days, 37 columns (no target)
├── Rapport.pdf             # detailed report
└── output/                 # created at runtime (git-ignored)
    └── submission_final.csv
```

---

## Running it

Requires **R ≥ 4.2**.

```bash
# 1. dependencies (once)
Rscript install_packages.R

# 2. full pipeline
Rscript modele_final.R
```

> **Important:** the script uses relative paths (`Data/...`, `Script/score.R`), so it must
> be run **from the repository root**. In RStudio, open
> `france-power-demand-forecasting.Rproj` and the working directory will be correct
> automatically.

Runtime: a few minutes (the three `qgam` fits dominate).

The script writes `output/submission_final.csv` (columns `Id`, `Net_demand`, 395 rows).

### Dependencies

`mgcv`, `qgam`, `forecast`, `opera`, `data.table`, `readr`, `dplyr`, `magrittr` — all on CRAN.

---

## Results

Pinball loss (τ = 0.5) on the validation set (2022 onwards), per intermediate model:

| Target | Pinball loss |
|---|---|
| `Load` | ≈ 383 |
| `Solar_power` | ≈ 135 |
| `Wind_power` | ≈ 296 |

The final model is the MLpol aggregation of the five experts above; see `Rapport.pdf`
for the detailed comparison and the expert-weight plots.

### A note on warnings

At runtime `qgam` reports a non-convergence warning for all three quantiles. This comes
from `bgam.fitd` and is tied to `discrete = TRUE`; the predictions remain usable and are
the ones reported in the write-up.
