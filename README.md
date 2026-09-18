# Prévision de la consommation d'électricité française

Prévision quantile de la **demande nette** d'électricité en France (`Net_demand = Load − Solar_power − Wind_power`)
sur la période de sobriété énergétique, évaluée à la **pinball loss**.

Projet de Modélisation Prédictive (M1) — Anne-Laure Sulmont et Amjad Proietti.

Le rapport complet est dans [`Rapport.pdf`](Rapport.pdf).

---

## Approche

Plutôt que de modéliser directement la demande nette, on décompose le problème en
**trois GAM séparés** dont les prévisions sont ensuite recombinées :

| Modèle | Cible | Principaux effets |
|---|---|---|
| `gam_load` | `Load` | `toy` (cyclique), `Temp`, `Load.1`, `WeekDays` |
| `gam_solar` | `Solar_power` | `toy`, températures lissées, `Nebulosity × toy` (tensor), retards, calendrier |
| `gam_wind` | `Wind_power` | `toy`, `Wind`, `Wind_weighted`, retards, `Nebulosity`, calendrier |

La prévision moyenne est `pred_load − pred_wind − pred_solar`.

Viennent ensuite trois raffinements :

1. **Correction des résidus par ARIMA** — un `auto.arima` est ajusté sur les résidus de
   la demande nette sur l'ensemble de validation, puis extrapolé sur l'horizon de test.
2. **Passage à des quantiles** — pour chaque `τ ∈ {0.3, 0.5, 0.8}`, deux décalages sont
   calculés : un quantile **gaussien** (`μ + qnorm(τ)·σ` sur les résidus) et un quantile
   **empirique** (`quantile(résidus, τ)`).
3. **Régression quantile additive** — un `qgam` ajusté directement sur `Net_demand`,
   avec un jeu de variables plus riche (prix ENTSO-E, indicatrice de confinement).

Enfin, ces prédicteurs sont combinés par **agrégation d'experts** (`opera::mixture`,
algorithme `MLpol`, perte pinball) :

```
qgam  |  3 modèles + quantile normal  |  ARIMA + quantile normal
      |  3 modèles + quantile empirique  |  ARIMA + quantile empirique
```

### Variables ajoutées

- **Prix de l'électricité** (ENTSO-E, 2015–2023) : `mean`, `min`, `std`, `night_mean`,
  `ramp_18_6`, etc., joints par date.
- **Confinement** : indicatrice des trois confinements français (mars–mai 2020,
  oct.–déc. 2020, avril–mai 2021).

---

## Structure du dépôt

```
.
├── modele_final.R          # pipeline complet : données → 3 GAM → ARIMA → qgam → agrégation
├── install_packages.R      # installe les dépendances CRAN
├── Script/
│   └── score.R             # métriques : pinball_loss, rmse, mape, bias
├── Data/
│   ├── ENTSOEDailyFeatures20152023.csv                   # prix ENTSO-E (séparateur ;)
│   └── net-load-forecasting-during-soberty-period/
│       ├── train.csv       # 3 471 jours, 39 colonnes (avec Net_demand)
│       └── test.csv        # 395 jours, 37 colonnes (sans cible)
├── Rapport.pdf             # rapport détaillé
└── output/                 # généré à l'exécution (ignoré par git)
    └── submission_final.csv
```

---

## Exécution

Nécessite **R ≥ 4.2**.

```bash
# 1. dépendances (une seule fois)
Rscript install_packages.R

# 2. pipeline complet
Rscript modele_final.R
```

> **Important :** le script utilise des chemins relatifs (`Data/...`, `Script/score.R`).
> Il faut donc le lancer **depuis la racine du dépôt**. Sous RStudio, ouvrez
> `france-power-demand-forecasting.Rproj` : le répertoire de travail est alors correct
> automatiquement.

Durée : quelques minutes (les trois `qgam` dominent le temps de calcul).

Le script écrit `output/submission_final.csv` (colonnes `Id`, `Net_demand`, 395 lignes).

### Dépendances

`mgcv`, `qgam`, `forecast`, `opera`, `data.table`, `readr`, `dplyr`, `magrittr` — toutes sur le CRAN.

---

## Résultats

Pinball loss (τ = 0.5) sur l'ensemble de validation (2022+), par modèle intermédiaire :

| Cible | Pinball loss |
|---|---|
| `Load` | ≈ 383 |
| `Solar_power` | ≈ 135 |
| `Wind_power` | ≈ 296 |

Le modèle final est l'agrégation MLpol des cinq experts ci-dessus ; voir `Rapport.pdf`
pour la comparaison détaillée et les graphiques de poids des experts.

### Note sur les avertissements

À l'exécution, `qgam` affiche `l'algorithme n'a pas convergé` pour les trois quantiles.
C'est un avertissement de `bgam.fitd` lié à `discrete = TRUE` ; les prédictions restent
exploitables et sont celles utilisées dans le rapport.
