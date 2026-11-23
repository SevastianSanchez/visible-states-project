# `01_data/processed/` — data dictionary

What the Visible States Index is built from. Written by
[`02_processing/`](../../02_processing/) from the UN SDG Global Database, **2015–2023**,
**197 geographies**, **665 series**, downloaded 16 Aug 2026. Every table keys on `iso3` + `year`.

The published scores (`vsi_scores`, `vsi_goal_scores`, `vsi_goal_relative_scores`) are
documented in [`04_publish/DATA_DICTIONARY.md`](../../04_publish/DATA_DICTIONARY.md).
📊 **[Interactive version](https://sevastiansanchez.github.io/visible-states-project/data_dictionary.html)**
covers both: the scores and the tables below.

## Lineage

```
sdg_full_data  (1 row = 1 observation)                                   03_wrangle_sdg.R
   │
   ├── geo_exclusions             reference: geographies dropped or rolled up
   ├── series_stability_list      input: what each series is, its goals, and its lifespan
   ├── agg_series_depth           input: reported or not, per country, series and year
   │      └── grid_all_series   input: 1,773 country-years × 665 series, 1 = reported
   │             │                                               04_select_model_series_sdg.R
   │             ├── series_variant_map   input: which series repeat another (607 → 524)
   │             ├── grid_model_series  input: 1,773 × 524, what the models fit
   │             ├── series_goal          input: each model series and its one goal
   │             └── filter_log           reference: the series count after each rule
   └── series_provenance_nature   reference: who produced each series

country_covariates   reference: income groups and comparison benchmarks (World Bank, SPI, HRV)
count_measures/      the count-based measures that came before the index (not part of it)
```

665 series → 607 after dropping those reported in 2% or fewer, or 98% or more, of
country-years → 524 after counting repeated series once
(`02_processing/04_select_model_series_sdg.R`; the count after each rule is in `filter_log.csv`).

## Files at a glance

| Dataset | Role | Grain | Key | Rows | File |
|---|---|---|---|---|---|
| `sdg_full_data` | source | one observation | — | 1,307,990 | `.csv.gz` |
| `agg_series_depth` | input | country × series × year | geo_area_code + series_code + year + goal | 508,432 | `.csv.gz` + `.rds` |
| `series_stability_list` | input | goal-target-indicator-series | series_code (+ path) | 726 | `.csv` |
| `grid_all_series` | input | country × year | iso3 + year | 1,773 (× 665 series) | `.rds` |
| `series_variant_map` | input | one series | series_code | 607 | `.csv` |
| `grid_model_series` | input | country × year | iso3 + year | 1,773 (× 524 series) | `.rds`, `.csv` |
| `series_goal` | input | one model series | series_code | 524 | `.csv` |
| `filter_log` | reference | one rule | step | 4 | `.csv` |
| `series_provenance_nature` | reference | one series | SeriesCode | 668 | `.csv` |
| `geo_exclusions` | reference | one geography | geo_area_code | 63 | `.csv` |
| `country_covariates` | reference | country × year | iso3 + year | 1,773 | `.csv` |

> The `.rds` copy of `agg_series_depth` keeps exact column types and the `attr()`
> labels. Reading a `.csv` guesses types and drops the labels.

The subfolder `count_measures/` holds two count-based tables, `goal_lvl_dv_data` and
`agg_series_counts_rc`, built by `02_processing/build_count_measures.R`. They are kept
for comparison, are not part of the index, and are not documented here.

---

## `sdg_full_data` — source

The cleaned UN SDG Global Database: one row per observation (country × series × year ×
breakdown). Every other table here derives from it.

**Grain:** one observation &nbsp;·&nbsp; **Rows:** 1,307,990 &nbsp;·&nbsp; **Columns:** 19

| Column | Type | Description |
|---|---|---|
| `goal` `target` `indicator` | mixed | SDG hierarchy, e.g. `1` / `1.2` / `1.2.1`. |
| `series_code` `series_description` | chr | The statistical series (665 distinct). |
| `geo_area_code` `geo_area_name` `iso3` | chr | UN M49 code, UN name, and `iso3`, the join key. **MERGE** |
| `year` | int | 2015–2023. |
| `value` | chr | The reported number, as text. `NA` = an empty cell the UN opened. A few rows carry censored bounds like `<0.1`. |
| `missing_reason` | chr | Why an empty cell is empty: `structural` (does not apply) / `suppressed` (withheld) / `unknown`. `NA` when a value is present. |
| `age` `sex` `location` `units` | chr | Breakdown dimensions; blank where the series has none. |
| `nature` | chr | Who produced the number (see below). |
| `observation_status` | chr | SDMX status flag (`A` normal, `M`/`O`/`Q` kinds of missing, …). |
| `source` `foot_note` | chr | Free-text provenance from the UN export. |

**`nature` codes** (the UN's definitions, condensed):

| Code | Who | Meaning |
|---|---|---|
| `C` | country | Produced and published by the country, including data it adjusted to international standards |
| `CA` | country | Produced by the country, adjusted by the international agency for comparability |
| `E` | agency | Estimated by the agency from national data (surveys, records) when country figures are missing, conflicting or of poor quality |
| `M` | agency | Modelled by the agency from other variables when there is no national data on the variable at all |
| `G` | agency | Global monitoring data, produced by the agency, with no corresponding country figure |
| `N` | — | Not relevant |

---

## `agg_series_depth` — input

One row per country, series and year that the UN export holds. **The index reads one
column, `reported`**: it becomes the 1 = reported / 0 = not grid every model is fitted on.
The other columns describe each cell.

**Grain:** country × series × year &nbsp;·&nbsp; **Key:** `geo_area_code` + `series_code` + `year` + `goal` &nbsp;·&nbsp; **Rows:** 508,432

| Column | Type | Description |
|---|---|---|
| `goal` `geo_area_code` `geo_area_name` `iso3` `year` `series_code` | mixed | Grain keys. `iso3` joins out. **KEY / MERGE** |
| `reported` | lgl | At least one published value here. **What the index is built from.** |
| `reported_country` | lgl | At least one country-produced value (`C`/`CA`). |
| `applicable` | lgl | The series applies here: not every empty cell is marked structural. |
| `n_disagg_rows` | int | Breakdowns the country published (rows in `sdg_full_data`). |
| `n_country_rows` / `n_agency_rows` | int | Of those, by producer (`C`/`CA` vs `E`/`M`/`G`). |
| `nature_codes` | chr | Nature codes present, joined with "/", e.g. `C/E`. NA where the cell is all empty. |
| `n_declared_missing` | int | Empty cells here. |
| `n_missing_structural` / `n_missing_suppressed` | int | Split of the above by reason. |
| `depth_frontier` | int | Per-series ceiling: the most breakdowns any country-year published. |
| `depth_union` | int | Per-series ceiling: every breakdown ever seen, pooled. No single country can reach it. |
| `dv_depth_pct_frontier` / `dv_depth_pct_union` | dbl | `n_disagg_rows` as a share of each ceiling, in [0,1]. |

---

## `series_stability_list` — input

What each series *is*, which goals it sits under, and its lifespan. One row per
goal-target-indicator-series path: 726 rows for 665 series, since a series can sit under
more than one path. The models read `series_code` and `goal` from it; a series under
several goals is assigned to the goal with the fewest series (see `series_goal`).

The SDG framework grew during 2015–2023, so some series did not exist in early years.
The 409 series live in every year form the **stable core**, used by the count-based
measures to check for framework growth. The index does not use the stability columns.

**Grain:** goal-target-indicator-series &nbsp;·&nbsp; **Key:** `series_code` (+ path) &nbsp;·&nbsp; **Rows:** 726

| Column | Type | Description |
|---|---|---|
| `goal` `target` `indicator` `series_code` `series_description` | mixed | The SDG path and series identity. **KEY** |
| `first_year` `last_year` `n_years_live` | int | When the series has data. `n_years_live` counts years present, so gaps show here. |
| `is_stable_core` `starts_late` `ends_early` `status` | lgl/chr | Lifespan flags. Filter on `ends_early` for every discontinued series; `status` files a series that both starts late and ends early under `entered_late` only. |
| `n_observations` `n_observations_country` `n_observations_agency` | int | Published values for the series, split by producer. |
| `n_declared_missing` `n_missing_structural` `n_missing_suppressed` | int | Empty cells for the series, by reason. |
| `pct_country_produced` | dbl | Share country-produced: 2% to 100% across series. |
| `max_countries` | int | The most countries reporting the series in any year. |
| `log_first_seen` `log_added_date` `log_removed_date` `n_log_events` | Date/int | Supporting dates from the UN update log. |

---

## `grid_all_series` — input

The full grid: one row per country-year, one column per series, 1 = at least one value
published that year under any breakdown, 0 = none. A series under several goals has one
column. Built by `03_wrangle_sdg.R` from `agg_series_depth`. Descriptive work uses this.

**Grain:** country × year &nbsp;·&nbsp; **Key:** `iso3` + `year` &nbsp;·&nbsp; **Rows:** 1,773 &nbsp;·&nbsp; **Columns:** `iso3`, `year`, then 665 series

---

## `series_variant_map` — input

Which series repeat another. Some measurements are published twice (stunting as a
percentage and as a count); kept, they would let a country earn two points for one act of
reporting. A series is collapsed into its cluster only when it has the same reported/not
pattern in every country-year **and** measures the same thing. Built by
[`04_select_model_series_sdg.R`](../../02_processing/04_select_model_series_sdg.R);
[`05_validate_data_sdg.R`](../../02_processing/05_validate_data_sdg.R) stops the run if a
collapsed group does not move as one.

**Grain:** one series (the 607 that pass the 2–98% filter) &nbsp;·&nbsp; **Key:** `series_code` &nbsp;·&nbsp; **Rows:** 607

| Column | Type | Description |
|---|---|---|
| `series_code` | chr | **KEY** |
| `indicator` `units` `series_description` | chr | What the series is. |
| `pattern_group` | int | Series with an identical reported/not pattern share a group. |
| `cluster` | chr | The series that represents the cluster; the one kept. |
| `verdict` | chr | `single` (no twin, 435) · `collapse` (a repeat, 142 series in 59 clusters) · `keep_separate` (same pattern, different measurement, 16) · `review` (not yet decided; kept separate, 14). |
| `evidence` | chr | Why: pattern match, description similarity, indicators and units. |

---

## `grid_model_series` — input

What the models fit: `grid_all_series` restricted to the 524 series that pass the 2–98%
rule and the duplicate collapse. Built by `04_select_model_series_sdg.R`.

**Grain:** country × year &nbsp;·&nbsp; **Key:** `iso3` + `year` &nbsp;·&nbsp; **Rows:** 1,773 &nbsp;·&nbsp; **Columns:** `iso3`, `year`, then 524 series

---

## `series_goal` — input

Each model series and the one goal it counts toward. A series listed under several goals
goes to whichever of its own goals has the fewest series, so no goal is starved by an
arbitrary choice. Built by `04_select_model_series_sdg.R`.

**Grain:** one model series &nbsp;·&nbsp; **Key:** `series_code` &nbsp;·&nbsp; **Rows:** 524

| Column | Type | Description |
|---|---|---|
| `series_code` | chr | **KEY** |
| `goals_listed` | chr | Every goal the series sits under, e.g. `1/11/13`. |
| `goal_assigned` | int | The goal it counts toward. |

---

## `filter_log` — reference

The series count after each rule that chooses the model series: 665 → 637 → 607 → 524.

| Column | Type | Description |
|---|---|---|
| `step` | int | 0 = the starting set. |
| `rule` | chr | The rule applied. |
| `series` | int | Series left after it. |

---

## `series_provenance_nature` — reference

Who produced each series, from the `nature` codes. Used for each goal's agency share
(`weight_agency_pct` in the release's `goal_diagnostics.csv`). For disclosure only: nothing
is dropped on provenance. Built by [`build_series_provenance.R`](../../02_processing/build_series_provenance.R)
from the full UN exports, so it counts a few series codes outside the 665.

**Grain:** one series &nbsp;·&nbsp; **Key:** `SeriesCode` &nbsp;·&nbsp; **Rows:** 668

| Column | Type | Description |
|---|---|---|
| `SeriesCode` | chr | **KEY** |
| `obs` | int | Published values. |
| `pct_C` `pct_E` `pct_M` `pct_G` `pct_other` | dbl | Share of values with each nature code; `pct_C` includes `CA`. |
| `mostly_country` | lgl | At least half country-produced (419 series). |

---

## `geo_exclusions` — reference

Every geography that left its own code, and why. The index scores sovereign states:
uninhabited places, defunct states, dependent territories and sub-national strata are
dropped, and the UK's three devolved jurisdictions are rolled up into the UK. Generated
from the same list that drives the filter, so it cannot drift from what happened. 197
geographies remain.

**Grain:** one geography &nbsp;·&nbsp; **Key:** `geo_area_code` &nbsp;·&nbsp; **Rows:** 63

| Column | Type | Description |
|---|---|---|
| `geo_area_code` `geo_area_name` | chr | The geography removed. **KEY** |
| `disposition` | chr | `excluded` (dropped, 60) or `rolled up` (merged into a parent, 3). |
| `reason` | chr | defunct entity · uninhabited · sub-national stratum · dependent territory · devolved jurisdiction. |
| `parent_code` | int | Roll-up target (UK = 826). NA for excluded rows. |
| `n_observations` `n_obs_retained` `n_series` `n_years` `first_year` `last_year` | int | What the geography contributed, and how much a roll-up kept. |

---

## `country_covariates` — reference

Country facts from outside the UN database: the income groups printed with the scores, and
the benchmarks the index is checked against. Built by
[`extract_covariates.R`](../../02_processing/extract_covariates.R) from dated
downloads in `01_data/raw/covariates/`.

**Grain:** country × year &nbsp;·&nbsp; **Key:** `iso3` + `year` &nbsp;·&nbsp; **Rows:** 1,773

| Column | Type | Description |
|---|---|---|
| `iso3` `year` | mixed | Join key. **KEY / MERGE** |
| `country_name` | chr | UN name. |
| `income_level` | chr | World Bank income group for that year (historical classifications). |
| `gdp_pc` | dbl | GDP per capita, current US$ (World Bank WDI). 1,738 rows. |
| `spi_overall` | dbl | World Bank Statistical Performance Indicators, overall score (all five pillars). 1,425 rows. |
| `spi_overall_mod` | dbl | SPI without pillar 3, which partly scores SDG data availability from the same UN database; pillars 1, 2, 4 and 5 at 25% each. 1,432 rows. |
| `hrv` `hrv_sd` | dbl | HRV transparency index, version 2 (Hollyer, Ge, Rosendorff & Vreeland 2024), and its standard deviation. It ends in 2015, so only 149 rows have a value. |
| `spi_p1_use` `spi_p2_services` `spi_p3_products` `spi_p4_sources` `spi_p5_infra` | dbl | The five SPI pillars: data use, services, products, sources, infrastructure. Pillar 3 partly scores SDG data availability from the same UN database as the index. |
