# Visible States: statistical reporting across countries, policy sectors, and time

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.23997606.svg)](https://doi.org/10.5281/zenodo.23997606)

This repository builds, validates and releases the **Visible States Index (VSI)**, a measure of how much each government reports to the UN Sustainable Development Goal (SDG) database. It treats a missing value as information about the government, not a gap to impute.

Author: Sevastian Sanchez, Columbia University (SIPA and QMSS)

## The index

**[Visible States Project &rarr; sevastiansanchez.github.io/visible-states-project](https://sevastiansanchez.github.io/visible-states-project/)**

*Statistical reporting across countries, policy sectors, and time.*

The first transparency measure covering the SDG era: latent reporting behaviour across 524 statistical series and 197 countries, 2015–2023, with uncertainty quantified for every country-year. Existing transparency indices stop in 2015; this one begins there, and resolves reporting by policy domain rather than returning a single national score.

The headline measure is the **Visible States Index (VSI)**: one overall score per country-year, plus one score per SDG goal. The site carries the rankings, the yearly trend, the goal scores, a version roadmap and the downloadable scores. It is a preliminary release, and citable.

### How to cite

> Sanchez, S. (2026). *Visible States: statistical reporting across countries, policy sectors, and time* (v1.4.0) [Data set]. Zenodo. https://doi.org/10.5281/zenodo.23997606

Use the **concept DOI** above when referring to the dataset generally — it always resolves to the newest version. Cite the **version DOI** for the release your analysis actually used, so your results stay reproducible after later versions change the scores:

| Release | Version DOI | Published as |
|---|---|---|
| v1.4.0 | [10.5281/zenodo.24301441](https://doi.org/10.5281/zenodo.24301441) | Visible States |
| v1.3.0 | [10.5281/zenodo.24100866](https://doi.org/10.5281/zenodo.24100866) | Visible States |
| v1.2.1 | [10.5281/zenodo.24094834](https://doi.org/10.5281/zenodo.24094834) | The World on Record |
| v1.2.0 | [10.5281/zenodo.24091914](https://doi.org/10.5281/zenodo.24091914) | The World on Record |
| v1.0.0 | [10.5281/zenodo.23997607](https://doi.org/10.5281/zenodo.23997607) | The World on Record |

Versions 1.0.0 to 1.2.1 were deposited under the name **The World on Record**
and keep that title, so earlier citations still resolve. The scores in 1.2.1
and 1.3.0 are identical; only the names changed. From 1.3.0 the columns are
`vsi` and `vsi_se`, previously `twr` and `twr_se`.

**Names from v1.4.0.** The goal scores are `vsi_goal` (`goal_level` in v1.3.0),
and v1.4.0 adds `vsi_goal_relative`, each goal net of the country's own overall
level. The overall score stays `vsi`. Deposited releases keep the names they were
published with; `releases/README.md` explains how each version is packaged.

Machine-readable metadata is in [CITATION.cff](CITATION.cff). Code is MIT-licensed ([LICENSE](LICENSE)); the data are CC BY 4.0 ([LICENSE-DATA](LICENSE-DATA)).

## Data

| Source | Use |
|---|---|
| UN SDG Global Database, 2015–2023 (665 series, 197 geographies, ~1.3M observations) | The measure: reported vs. missing observations by country, year and series |
| World Bank Statistical Performance Indicators (SPI); HRV Transparency Index | External validation (dated downloads in `01_data/raw/covariates/`) |

The cleaned tables, their grain, keys and every column are documented in the **[interactive data dictionary](https://sevastiansanchez.github.io/visible-states-project/data_dictionary.html)** (also available as [markdown](01_data/processed/README.md)).

## Repository layout

The top level reads in run order: data → processing → measures → publish.

```
01_data/        raw/ (never edited) · intermediate/ (not on GitHub) · processed/ (written by 02) · vsi_scores/ (written by 03)
02_processing/  UN exports → the 524-series grid the models fit, in five numbered steps
03_measures/    vsi/ · vsi_goal/ · vsi_goal_relative/ — each score's build script and its validate_measure/
04_publish/     the site's data files and the measurement paper's numbers (maintainer only)
rules.R         the fixed numbers every script uses: years, the 2–98% cutoffs, the 10-series minimum, held goals
packages.R      installs and loads the packages
```

**Data lives only in `01_data/`.** Each stage keeps its functions in its own
`functions/` folder, sourced and never run alone. `02_processing/05_validate_data_sdg.R`
validates the data before any model runs and stops if a check fails. Each measure's
`validate_measure/` folder tests the measure after it is fitted, and writes what it
finds to `validate_measure/output/`. `02_processing/diagnostics/` holds reports run by
hand. **Nothing in an `output/` folder is ever read as an input.**

| Folder | What | Run order |
|---|---|---|
| `01_data/raw/` | `un_sdg_exports/`: the 17 UN SDG goal exports (310 MB, not on GitHub; see Reproducing) and the UN's update log `sdg_update_info.xlsx`. `covariates/`: dated downloads of World Bank income groups and GDP per capita, SPI and HRV, with a `_manifest.csv` of pull dates | |
| `01_data/intermediate/` | Working files passed from step 01 to 02 to 03. Rebuilt by running them; not on GitHub | |
| `01_data/processed/` | Cleaned UN rows, the full and model grids, the series list with stability, the duplicate-series map, each model series' goal, the series count after each rule, provenance, `country_covariates.csv`, and `count_measures/` (the count-based measures that came before the index). Data dictionary in its `README.md` | |
| `01_data/vsi_scores/` | Scores, fits and series parameters: `vsi/` (`vsi`), `vsi_goal/` (`vsi_goal`), `vsi_goal_relative/` (`vsi_goal_relative`, new in v1.4.0) | |
| `02_processing/` | | 1 `01_extract_sdg.R` · 2 `02_clean_sdg.R` · 3 `03_wrangle_sdg.R` · 4 `04_select_model_series_sdg.R` (the 2–98% rule, duplicate series, one goal per series) · 5 `05_validate_data_sdg.R` (**must pass before any fit**) · then `extract_covariates.R` (income groups, GDP, SPI, HRV; `REFRESH=1` re-pulls), `build_count_measures.R`, `build_series_provenance.R` · diagnostics: `check_series_coverage.R`, `collinear_series_report.R`, `check_subgroup_only_cells.R` |
| `03_measures/vsi/` | The overall index | 6 `build_irt_vsi.R` · validate: `validate_vsi_external_measures.R` |
| `03_measures/vsi_goal/` | One score per goal | 7 `build_irt_vsi_goal.R` · validate: `validate_vsi_goal_heldout.R` (~13 min), `validate_vsi_goal_bootstrap.R` (~98 min on 8 cores) |
| `03_measures/vsi_goal_relative/` | A goal net of the country's own overall level | `build_irt_vsi_goal_relative.R` (long, checkpointed, resumes) · validate: `validate_vsi_goal_relative_heldout.R` (~2.5 h), `validate_vsi_goal_relative_bootstrap.R` (~4.7 h, checkpointed) |
| `03_measures/functions/` | `model_data.R` (turns the saved grids into what every model reads, so all fit the identical matrix), `bifactor_scorer.R` | |
| `04_publish/` | Maintainer only; not needed to reproduce the scores | `build_docs_data.R` → `docs/` · `paper_numbers.R` → `paper_numbers.txt`, every figure the measurement paper quotes · `build_release_bundle.R` → the Zenodo files |
| `docs/` | The published site: [Visible States Project](https://sevastiansanchez.github.io/visible-states-project/), the interactive data dictionary, and the published copy of the scores. GitHub Pages builds it from `main` | |
| `releases/` | What was deposited at Zenodo, one folder per version. Never edited | |

`run_all.R` runs processing and the quick checks in order; refits only on request.
It never publishes and never runs the diagnostics.

Steps 6 and 7 are independent of each other; both read only `01_data/processed/`.
Every fit setting comes from `METHODS_LOG.md`: **read it before changing one.**
One script writes each file. All paths go through `here()`, so any script runs
whatever the working directory is.

## Reproducing

Dependencies are handled by `packages.R`, which installs anything
missing and then loads everything. Scripts source it directly.

**Everything runs from a fresh clone except steps 01–03.** Every input the later
scripts need is tracked, including the cleaned UN data
(`01_data/processed/sdg_full_data.csv.gz`) and the full grid
(`01_data/processed/grid_all_series.rds`), so you do not have to rebuild them to
run anything downstream.

The UN SDG goal exports are 310 MB, too large to track. To rebuild from source,
download them from the [UN SDG Global Database](https://unstats.un.org/sdgs/dataportal)
into `01_data/raw/un_sdg_exports/`, then run `02_processing/01_extract_sdg.R`,
`02_clean_sdg.R` and `03_wrangle_sdg.R` (or `Rscript run_all.R`, which runs them when
the exports are there). Nothing else requires that download.

## Related work

The Politics of NAs paper, which uses the index to ask whether autocratization episodes reduce SDG reporting, is in its own repository, `politics-of-nas-paper`.

Di Gennaro Splendore, L., and Sanchez, S. (2025). *Untangling the relationship between democracy, data, and development: A dynamic two-stage analysis of the Sustainable Development Goals* (Preprint). SSRN. https://doi.org/10.2139/ssrn.6998939

## License

Code is MIT; see [LICENSE](LICENSE). The data this code produces — `01_data/processed/`, `01_data/vsi_scores/` and the files published in `docs/` — are CC BY 4.0; see [LICENSE-DATA](LICENSE-DATA). Third-party source data in `01_data/raw/` remains under its own terms.
