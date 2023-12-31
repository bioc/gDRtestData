# only for testing purpuses not displayed as example in the visualization

library(SummarizedExperiment)
library(BumpyMatrix)
library(gDRutils)
library(gDRwrapper)
library(gDRcore)
library(reshape2)

#' Test accuracy of the fitted metrics based on the model
#'
#' @param se SummarizedExperiment for testing
#' @param e_inf e_inf
#' @param ec50 ec50
#' @param hill_coef hill_coef
#'
#' @return data.frame with quality metrics
test_accuracy <- function(se, e_inf, ec50, hill_coef) {
  
  dt <- gDRutils::convert_se_assay_to_dt(se, "Metrics")
  dt <- gDRutils::flatten(dt, groups = c("normalization_type", "fit_source"),
                          wide_cols = gDRutils::get_header("response_metrics"))
  colnames(dt) <- gDRutils::prettify_flat_metrics(colnames(dt), FALSE)
  rows <- unique(SummarizedExperiment::rowData(se)$Gnumber)
  cols <- SummarizedExperiment::colData(se)$clid
  quart <- c(.05, .5, .95)
  
  df_QC <- rbind(
    stats::quantile(acastVar(dt, "E_inf") - e_inf[rows, cols], quart),
    stats::quantile(log10(acastVar(dt, "EC50")) - log10(ec50[rows, cols]), quart),
    stats::quantile(acastVar(dt, "h_RV") - hill_coef[rows, cols], quart),
    stats::quantile((acastVar(dt, "h_RV") - hill_coef[rows, cols])[
      acastVar(dt, "EC50") < 3 & acastVar(dt, "E_inf") < .8], quart
    ),
    1 - stats::quantile(acastVar(dt, "RV_r2"), quart)
  )
  
  rownames(df_QC) <- c("delta_einf", "delta_ec50", "delta_hill", "d_hill_fitted", "1_r2")
  df_QC
}

acastVar <- function(dt, var) {
  reshape2::acast(dt, Gnumber ~ clid, value.var = var)
}



cell_lines <- create_synthetic_cell_lines()
drugs <- create_synthetic_drugs()
e_inf <- generate_e_inf(drugs, cell_lines)
ec50 <- generate_ec50(drugs, cell_lines)
hill_coef <- generate_hill_coef(drugs, cell_lines)

#### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# generate the data for the 1st test set: no noise
df_layout <- merge(cell_lines[2:11, ], drugs[2:11, ], by = NULL)
df_layout <- add_data_replicates(df_layout)
df_layout <- add_concentration(df_layout)

df_merged_data <- generate_response_data(df_layout, 0)

finalSE_1_no_noise <- gDRcore::runDrugResponseProcessingPipeline(df_merged_data)


df_merged_data_day0 <- add_day0_data(df_merged_data, 0)
finalSE_1_no_noise_day0 <- gDRcore::runDrugResponseProcessingPipeline(df_merged_data_day0)


# testing
df_divTime <- data.frame(calculated_div_time = colMeans(assay(finalSE_1_no_noise_day0, 6)))
df_divTime <- merge(colData(finalSE_1_no_noise_day0), df_divTime, by = 0)

all(abs(df_divTime$ReferenceDivisionTime - df_divTime$calculated_div_time) < .06)

dt <- convert_se_assay_to_dt(finalSE_1_no_noise, "Averaged")
dt_day0 <- convert_se_assay_to_dt(finalSE_1_no_noise_day0, "Averaged")
dt_values <- merge(dt_day0, dt, by = c("rId", "cId", "Concentration"))

all(dt_values$RelativeViability.y - dt_values$RelativeViability.x == 0)
all(abs(dt_values$GRvalue.y - dt_values$GRvalue.x) < 2e-3)


dt_test <- test_accuracy(finalSE_1_no_noise_day0, e_inf, ec50, hill_coef)
print(dt_test)
# test:
print(apply(abs(dt_test) < c(1e-3, 2.2e-3, 0.04, 0.015, 1e-4), 1, all))

saveArtifacts(
  tsvObj = df_merged_data_day0,
  tsvName = "synthdata_small_wDay0_no_noise_rawdata.tsv",
  rdsObj = finalSE_1_no_noise,
  rdsName = "finalSE_small_wDay0_no_noise.RDS"
)


#### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# generate the data for the 1st test set with ligand as reference
df_layout <- merge(cell_lines[2:6, ], drugs[2:5, ], by = NULL)
df_layout <- add_data_replicates(df_layout)
df_layout <- add_concentration(df_layout)

df_merged_data <- generate_response_data(df_layout, 0)
df_merged_data$Ligand <- 0.1
df_merged_data2 <- df_merged_data[df_merged_data$Gnumber %in% c("vehicle", "G00002", "G00003"), ]
df_merged_data2$Ligand <- 0
df_merged_data2$ReadoutValue <- 105 - pmax(0, pmin(104, (105 - df_merged_data2$ReadoutValue) ^ 1.1))
df_merged_data2$ReadoutValue[df_merged_data2$clid %in% paste0("CL000", 11:12)] <-
    0.8 * df_merged_data2$ReadoutValue[df_merged_data2$clid %in% paste0("CL000", 11:12)]
df_merged_data2$ReadoutValue[df_merged_data2$clid %in% paste0("CL000", 13:14)] <-
    0.5 * df_merged_data2$ReadoutValue[df_merged_data2$clid %in% paste0("CL000", 13:14)]
df_merged_data2$ReadoutValue <- round(df_merged_data2$ReadoutValue, 1)
df_merged_data2$Barcode <- paste0(df_merged_data2$Barcode, "1")
df_merged_data <- rbind(df_merged_data, df_merged_data2)

df_merged_data_day0 <- add_day0_data(df_merged_data, 0)
df_merged_data_day0 <- df_merged_data_day0[df_merged_data_day0$Ligand == 0.1 | df_merged_data_day0$Duration > 0, ]

finalSE_1_Ligand <- gDRcore::runDrugResponseProcessingPipeline(
  df_merged_data, 
  override_untrt_controls = c(Ligand = 0.1)
)
finalSE_1_Ligand_day0 <- gDRcore::runDrugResponseProcessingPipeline(
  df_merged_data_day0, 
  override_untrt_controls = c(Ligand = 0.1)
)

dt_test <- test_accuracy(finalSE_1_Ligand_day0[rowData(finalSE_1_Ligand_day0)$Ligand > 0, ], e_inf, ec50, hill_coef)
print(dt_test)
# test:
print(apply(abs(dt_test) < c(1e-3, 3e-3, 0.031, 0.015, 1e-4), 1, all))

dt <- convert_se_assay_to_dt(finalSE_1_Ligand, "Averaged")
dt_day0 <- convert_se_assay_to_dt(finalSE_1_Ligand_day0, "Averaged")
dt_values <- merge(dt_day0, dt, by = c("rId", "cId", "Concentration"))

all(dt_values$RelativeViability.y - dt_values$RelativeViability.x == 0)
all(abs(dt_values$GRvalue.y - dt_values$GRvalue.x) < 2e-3)

saveArtifacts(
  tsvObj = df_merged_data,
  tsvName = "synthdata_wLigand_wDay0_rawdata.tsv",
  rdsObj = finalSE_1_Ligand,
  rdsName = "finalSE_wLigand_wDay0.RDS"
)

