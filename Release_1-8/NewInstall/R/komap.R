####################################################################
####################################################################
##
## KOMAP
##
## https://github.com/xinxiong0238/KOMAP
##
## Requires R 4.3.0 or later and R Studio.
## Make sure you can read/write to input/output directories.
##
####################################################################
####################################################################

#===================================================================
# MAKE SURE THESE ARE INSTALLED
#===================================================================

# install.packages("remotes")
# remotes::install_github("xinxiong0238/KOMAP")
# # To connect to a database
# install.packages("odbc")
# install.packages("DBI")
# install.packages("rstudioapi")

#===================================================================
# OPTION 1: IMPORT DATA FROM A DATABASE
#===================================================================

library(DBI)
library(odbc)
con <- DBI::dbConnect(odbc::odbc(), driver = "SQL Server", server = "*****", database = "*****", uid = "*****", pwd = rstudioapi::askForPassword("Database password"))
#con <- DBI::dbConnect(odbc::odbc(), driver= "{Oracle in OraDB19Home1}", dbq = "*****", uid = "*****", pwd = rstudioapi::askForPassword("Database password"))
phenotypes <- dbGetQuery(con, "select phenotype from dbo.dt_komap_phenotype;")
data_dict_all <- dbGetQuery(con, "select phenotype, feature_cd, feature_name from dbo.dt_komap_phenotype_feature_dict;")
data_cov_all <- dbGetQuery(con, "select phenotype, feature_cd1, feature_cd2, covar from dbo.dt_komap_phenotype_covar;")

#===================================================================
# OPTION 2: IMPORT DATA FROM CSV
#===================================================================

#phenotypes <- read.csv("C:\\komap\\input\\dt_komap_phenotype.csv")
#data_dict_all <- read.csv("C:\\komap\\input\\dt_komap_phenotype_feature_dict.csv")
#data_cov_all <- read.csv("C:\\komap\\input\\dt_komap_phenotype_covar.csv")

# Ensure that column names are lowercase so that they will match references
names(phenotypes) <- base::tolower(names(phenotypes))
names(data_dict_all) <- base::tolower(names(data_dict_all))
names(data_cov_all) <- base::tolower(names(data_cov_all))

#===================================================================
# RUN KOMAP
#===================================================================

library(KOMAP)

if (exists("phenotype_feature_coef")) {rm(phenotype_feature_coef)}
phenotype_feature_coef <- do.call("rbind", lapply(phenotypes$phenotype, function(phe){
data_dict <- subset(data_dict_all, phenotype==phe, c(feature_cd, feature_name))
data_cov <- subset(data_cov_all, phenotype==phe, c(feature_cd1, feature_cd2, covar))
target.code<-phe
target.cui <- NULL
nm.utl<-'Utilization:IcdDates'
out_input_long <- KOMAP(data_cov, is.wide = FALSE, target.code, target.cui, nm.utl, nm.multi = NULL, data_dict, pred = FALSE, eval.real = FALSE, eval.sim = FALSE)
coef <- out_input_long$est$lst$`mainICD + allfeature`$beta
return(data.frame(phenotype=phe, feature_cd=coef$feat, coef=coef$theta))
}))

#===================================================================
# OPTION 1: EXPORT RESULTS TO A DATABASE
#===================================================================

colnames(phenotype_feature_coef) <- toupper(names(phenotype_feature_coef))
dbWriteTable(con, DBI::Id(schema="dbo", table="DT_KOMAP_PHENOTYPE_FEATURE_COEF"), phenotype_feature_coef, overwrite=FALSE, append=TRUE)
#dbWriteTable(con, DBI::Id(table="DT_KOMAP_PHENOTYPE_FEATURE_COEF"), phenotype_feature_coef, overwrite=FALSE, append=TRUE)
dbDisconnect(con)

#===================================================================
# OPTION 2: EXPORT RESULTS TO CSV
#===================================================================

#write.csv(phenotype_feature_coef, file="C:\\keser\\output\\dt_komap_phenotype_feature_coef.csv", row.names=FALSE, quote=FALSE)

