####################################################################
####################################################################
##
## KESER - EMBEDDING REGRESSION
##
## https://github.com/celehs/KESER-i2b2
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
# remotes::install_github("celehs/KESER-i2b2")
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
embed_all <- dbGetQuery(con, "select cohort, feature_cd, dim, val from dbo.dt_keser_embedding;")
phenotypes <- dbGetQuery(con, "select phenotype from dbo.dt_keser_phenotype;")

#===================================================================
# OPTION 2: IMPORT DATA FROM CSV
#===================================================================

#embed_all <- read.csv("C:\\keser\\input\\dt_keser_embedding.csv")
#phenotypes <- read.csv("C:\\keser\\input\\dt_keser_phenotype.csv")

# Ensure that column names are lowercase so that they will match references
names(embed_all) <- base::tolower(names(embed_all))
names(phenotypes) <- base::tolower(names(phenotypes))

#===================================================================
# RUN KESER (EMBEDDING REGRESSION)
#===================================================================

library(KESER.i2b2)
library(tidyr)

# Get the train embeddings
embed_df <- embed_all[embed_all$cohort == 0, c("feature_cd","dim","val")]
embed_pw <- pivot_wider(embed_df,names_from=dim,values_from=val,names_sort=TRUE)
embed_train <- apply(as.matrix.noquote(embed_pw[,-1]),2,as.numeric)
rownames(embed_train) <- embed_pw$feature_cd

# Get the test embeddings
embed_df <- embed_all[embed_all$cohort == 1, c("feature_cd","dim","val")]
embed_pw <- pivot_wider(embed_df,names_from=dim,values_from=val,names_sort=TRUE)
embed_test <- apply(as.matrix.noquote(embed_pw[,-1]),2,as.numeric)
rownames(embed_test) <- embed_pw$feature_cd

# Get the number of dimensions
best_dim <- ncol(embed_train)

# Run regression
phecodes <- phenotypes$phenotype
lambda_vec <- c(seq(1, 51, 1) * 1e-6, seq(60, 1000, 50) * 1e-6)
alpha = 0.25 
regression_summary <- get_embed_regression(embed_train = embed_train, embed_valid = embed_test, phecodes = phecodes, dim = best_dim, lambda_vec = lambda_vec, alpha = alpha)

# Get a list of best features for each phenotype (phecode)
phenotype_feature <- do.call("rbind", lapply(phecodes, function(phecodes){
# Get the list of selected features
sf <- regression_summary$selected_features[[phecodes]]
# Create a data frame of the summary data in format for the database
return(data.frame(phenotype=phecodes, feature_cd=sf$codes, feature_rank=seq.int(nrow(sf)), feature_beta=sf$beta, feature_cosine=sf$cosine))
}))

#===================================================================
# OPTION 1: EXPORT RESULTS TO A DATABASE
#===================================================================

colnames(phenotype_feature) <- toupper(names(phenotype_feature))
dbWriteTable(con, DBI::Id(schema="dbo", table="DT_KESER_PHENOTYPE_FEATURE"), phenotype_feature, overwrite=FALSE, append=TRUE)
#dbWriteTable(con, DBI::Id(table="DT_KESER_PHENOTYPE_FEATURE"), phenotype_feature, overwrite=FALSE, append=TRUE)
dbDisconnect(con)

#===================================================================
# OPTION 2: EXPORT RESULTS TO CSV
#===================================================================

#write.csv(phenotype_feature, file="C:\\keser\\output\\dt_keser_phenotype_feature.csv", row.names=FALSE, quote=FALSE)


