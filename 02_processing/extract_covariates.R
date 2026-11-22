# ==============================================================================
# extract_covariates.R -- the outside data the index is compared against.
#
# Not part of the SDG chain (01-05), so it has no number. Run it after
# 03_wrangle_sdg.R, which supplies the country-years and the UN country names.
#
#   income_level                 World Bank historical income classification
#                                (OGHIST.xlsx), by the calendar year the data
#                                cover; income codes expanded to labels
#   country_name                 the UN's names, from the cleaned SDG data
#   gdp_pc                       GDP per capita, current US$ (WDI NY.GDP.PCAP.CD),
#                                from the World Bank Data360 API
#   spi_overall, spi_overall_mod World Bank Statistical Performance Indicators.
#                                spi_overall is the published index (mean of all
#                                5 pillars); spi_overall_mod drops pillar 3, which
#                                scores SDG availability from the same UN database
#                                as the index, and averages pillars 1, 2, 4, 5
#   hrv, hrv_sd                  HRV2 transparency index (Hollyer, Ge, Rosendorff &
#                                Vreeland 2024). HRV2 ends in 2015, so only the
#                                2015 rows have a value.
#   spi_p1_use ... spi_p5_infra  the five SPI pillar scores
#
# CITE HRV2: Hollyer, Ge, Rosendorff & Vreeland (2024), "Measuring Transparency,
#   Again: Updating and Extending the HRV Transparency Index." Original: Hollyer,
#   Rosendorff & Vreeland (2014), Political Analysis 22(1).
#
# DATED DOWNLOADS: each live source is written once to
# 01_data/raw/covariates/<name>__<date>.csv with a row in _manifest.csv, and
# read from the newest file after that, so a rebuild is reproducible.
# REFRESH=1 re-pulls and writes new dated files.
#
# INPUT   01_data/raw/covariates/*.csv
#         01_data/processed/grid_all_series.rds, sdg_full_data.csv.gz
# OUTPUT  01_data/processed/country_covariates.csv
#         one row per iso3 x year for the index's 197 countries, 2015-2023
# RUN     Rscript 02_processing/extract_covariates.R              (REFRESH=1 to re-pull;
#         HRV2_RDATA=/path/to/HRV2ExpandedCntriesExtracted.RData for a new HRV release)
# ==============================================================================
suppressPackageStartupMessages({library(data.table); library(here); library(jsonlite)})

REFRESH <- identical(Sys.getenv("REFRESH"), "1")
snap_dir <- here("01_data/raw/covariates")
manifest <- file.path(snap_dir, "_manifest.csv")
source(here("rules.R"))
years    <- start_year:end_year
say <- function(...) cat(sprintf("[%s] ", format(Sys.time(), "%H:%M:%S")), ..., "\n", sep = "")

# Read the newest dated snapshot of `name`, or pull it with `pull_fn` and save one.
snap <- function(name, pull_fn) {
  have <- sort(list.files(snap_dir, pattern = paste0("^", name, "__\\d{4}-\\d{2}-\\d{2}\\.csv$"),
                          full.names = TRUE), decreasing = TRUE)
  if (!REFRESH && length(have)) { say("[snapshot] ", name, " <- ", basename(have[1])); return(fread(have[1])) }
  say("[snapshot] ", name, ": pulling live")
  d   <- as.data.table(pull_fn())
  out <- file.path(snap_dir, paste0(name, "__", format(Sys.Date()), ".csv"))
  fwrite(d, out)
  row <- data.table(source = name, file = basename(out), pulled = format(Sys.Date()),
                    rows = nrow(d), cols = ncol(d))
  m <- if (file.exists(manifest)) fread(manifest, colClasses = "character") else NULL
  fwrite(rbind(m, row[, lapply(.SD, as.character)], fill = TRUE), manifest)
  say("[snapshot] wrote ", basename(out), " (", nrow(d), " rows)")
  d
}

# ---- income classification and names: World Bank OGHIST.xlsx --------------------
pull_income <- function() {
  url <- "https://datacatalogfiles.worldbank.org/ddh-published/0037712/DR0090754/OGHIST.xlsx"
  tf  <- tempfile(fileext = ".xlsx"); download.file(url, tf, mode = "wb", quiet = TRUE)
  x   <- readxl::read_excel(tf, sheet = "Country Analytical History", col_names = FALSE, .name_repair = "minimal")
  yr_row <- which(x[[2]] == "Data for calendar year :")
  yrs <- suppressWarnings(as.integer(unlist(x[yr_row, ])))
  body <- x[grepl("^[A-Z]{3}$", x[[1]]), ]
  keep <- which(!is.na(yrs))
  rbindlist(lapply(keep, function(j) data.table(iso3 = body[[1]], country_name = body[[2]],
                                                 year = yrs[j], income_code = body[[j]])))
}
inc <- snap("income", pull_income)

# ---- GDP per capita, current US$: World Bank Data360 API -----------------------
pull_gdp <- function() {
  base <- paste0("https://data360api.worldbank.org/data360/data?DATABASE_ID=WB_WDI",
                 "&INDICATOR=WB_WDI_NY_GDP_PCAP_CD&timePeriodFrom=", min(years),
                 "&timePeriodTo=", max(years))
  out <- list(); skip <- 0
  repeat {
    r <- fromJSON(paste0(base, "&skip=", skip))
    if (!length(r$value)) break
    out[[length(out) + 1]] <- as.data.table(r$value)[, .(iso3 = REF_AREA, year = as.integer(TIME_PERIOD),
                                                          gdp_pc = as.numeric(OBS_VALUE))]
    skip <- skip + nrow(r$value)
    if (skip >= r$count) break
  }
  rbindlist(out)
}
gdp <- snap("gdp_pc", pull_gdp)

# ---- SPI: newest snapshot already in the repo ----------------------------------
spi_file <- sort(list.files(snap_dir, pattern = "^spi__\\d{4}-\\d{2}-\\d{2}\\.csv$", full.names = TRUE),
                 decreasing = TRUE)[1]
say("[snapshot] spi <- ", basename(spi_file))
spi <- fread(spi_file)[, .(iso3 = iso3c, year = as.integer(date),
                           spi_overall = SPI.INDEX,
                           spi_overall_mod = rowMeans(cbind(SPI.INDEX.PIL1, SPI.INDEX.PIL2,
                                                            SPI.INDEX.PIL4, SPI.INDEX.PIL5)),
                           # the five pillars, for validate_vsi_external_measures.R,
                           # so no later script has to open the raw SPI file
                           spi_p1_use = SPI.INDEX.PIL1, spi_p2_services = SPI.INDEX.PIL2,
                           spi_p3_products = SPI.INDEX.PIL3, spi_p4_sources = SPI.INDEX.PIL4,
                           spi_p5_infra = SPI.INDEX.PIL5)]

# ---- HRV2: a new snapshot, ONLY when a new release has been downloaded ---------
# The authors publish HRV2 only as a 360 MB .RData holding the full JAGS
# posterior; all this project needs is 5,052 country-year rows. Set HRV2_RDATA
# to the downloaded file to cut a new dated snapshot; otherwise this section is
# skipped and the newest snapshot already in 01_data/raw/covariates/ is used.
#   SOURCE https://hrvtransparency.org/wp-content/uploads/HRV2/HRV2ExpandedCntriesExtracted.RData
#   Not downloaded automatically and not committed. Do not confuse it with
#   HRV2013.dta / TransparencyIndex2013.RData on the same page: those are the
#   ORIGINAL index, 125 countries, 1980-2010.
#   HRV2 ends in 2015 and the panel starts in 2015, so exactly ONE year overlaps:
#   it supports a cross-sectional check at 2015 and nothing longitudinal.
rdata <- Sys.getenv("HRV2_RDATA", unset = NA_character_)
if (!is.na(rdata)) {
  if (!file.exists(rdata))
    stop("HRV2_RDATA points to ", rdata, ", which does not exist.", call. = FALSE)
  # loaded into its own environment: the file also carries a 280 MB rjags object
  # and several loose loop variables (j, k, n) that would clobber the session
  e <- new.env()
  load(rdata, envir = e)
  if (!"TransparencyData" %in% ls(e))
    stop("TransparencyData not found in ", basename(rdata),
         " -- is this the HRV2 release?", call. = FALSE)

  td <- as.data.table(get("TransparencyData", envir = e))
  rm(e); invisible(gc())

  # `ccode` is already ISO3 despite the name; `Country` is a factor
  hrv <- td[, .(iso3    = as.character(ccode),
                year    = as.integer(year),
                hrv     = transparencyindex,
                hrv_lb  = transparencyindexlb,
                hrv_ub  = transparencyindexub,
                hrv_sd  = transparencyindexsd,
                country = as.character(Country))]
  setorder(hrv, iso3, year)

  stopifnot(!anyNA(hrv$iso3), all(nchar(hrv$iso3) == 3), !anyNA(hrv$hrv),
            hrv[, all(hrv_lb <= hrv & hrv <= hrv_ub)])
  cat("HRV2: ", nrow(hrv), " country-years | ", uniqueN(hrv$iso3), " countries | ",
      paste(range(hrv$year), collapse = "-"), "\n", sep = "")

  stamp <- format(Sys.Date())
  out   <- file.path(snap_dir, paste0("hrv__", stamp, ".csv"))
  fwrite(hrv, out)
  cat("wrote ", basename(out), "\n", sep = "")

  # The section below reads the newest hrv__<date>.csv, so no undated copy is written.

  man <- manifest
  m <- fread(man)
  # fread types the existing `pulled` column as IDate, so a character stamp
  # would be coerced to NA -- match the column's type instead
  m <- rbind(m[source != "hrv"], data.table(source = "hrv", file = basename(out),
    pulled = if (inherits(m$pulled, "IDate")) data.table::as.IDate(Sys.Date()) else stamp,
    rows = nrow(hrv), cols = ncol(hrv)))
  fwrite(m, man)
  cat("manifest updated\n")
}

# ---- HRV2: newest snapshot (made by the HRV section above) -----------------------
hrv_file <- sort(list.files(snap_dir, pattern = "^hrv__\\d{4}-\\d{2}-\\d{2}\\.csv$", full.names = TRUE),
                 decreasing = TRUE)[1]
say("[snapshot] hrv <- ", basename(hrv_file))
hrv <- fread(hrv_file)[, .(iso3, year = as.integer(year), hrv, hrv_sd)]

# ---- assemble on the index's own country-years -----------------------------------
# The country-years are the full grid's (03_wrangle_sdg.R), so this script
# depends on processing only, never on a model's output.
cy  <- unique(readRDS(here("01_data/processed/grid_all_series.rds"))[, .(iso3, year)])
lab <- c(L = "Low income", LM = "Lower-middle income", UM = "Upper-middle income", H = "High income")
inc[, income_level := unname(lab[income_code])]
# Names: the UN's own (geo_area_name in the cleaned SDG data), so they match the
# source the index is built from; World Bank names only where the UN has none.
un  <- unique(fread(here("01_data/processed/sdg_full_data.csv.gz"),
                    select = c("iso3", "geo_area_name"))[!is.na(iso3)])[, .SD[1], by = iso3]
wb  <- inc[, .(wb_name = country_name[!is.na(country_name)][1]), by = iso3]
nm  <- merge(un[, .(iso3, country_name = geo_area_name)], wb, by = "iso3", all = TRUE)
nm[is.na(country_name), country_name := wb_name][, wb_name := NULL]

cov <- merge(cy, nm, by = "iso3", all.x = TRUE)
cov <- merge(cov, inc[, .(iso3, year, income_level)], by = c("iso3", "year"), all.x = TRUE)
cov <- merge(cov, gdp, by = c("iso3", "year"), all.x = TRUE)
cov <- merge(cov, spi, by = c("iso3", "year"), all.x = TRUE)
cov <- merge(cov, hrv, by = c("iso3", "year"), all.x = TRUE)
cov[is.na(country_name), country_name := countrycode::countrycode(iso3, "iso3c", "country.name", warn = FALSE)]
cov[is.na(country_name), country_name := iso3]
cov[is.na(income_level), income_level := "Unclassified"]
setcolorder(cov, c("iso3", "year", "country_name", "income_level", "gdp_pc",
                   "spi_overall", "spi_overall_mod", "hrv", "hrv_sd"))
fwrite(cov[order(iso3, year)], here("01_data/processed/country_covariates.csv"))

say("wrote 01_data/processed/country_covariates.csv | ", nrow(cov), " country-years | ",
    "unclassified ", cov[income_level == "Unclassified", .N], " | gdp missing ", cov[is.na(gdp_pc), .N],
    " | spi missing ", cov[is.na(spi_overall), .N], " | hrv present ", cov[!is.na(hrv), .N])
