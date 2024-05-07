####################################################################
####################################################################
##
## KESER - GENERATE EMBEDDINGS
##
## April 25, 2024
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
CO_all <- dbGetQuery(con, "select cohort, feature_num1, feature_num2, coocur_count from dt_keser_feature_cooccur;")
freq_all <- dbGetQuery(con, "select cohort, feature_num, feature_cd, feature_name, feature_count from dt_keser_feature_count;")

#===================================================================
# OPTION 2: IMPORT DATA FROM CSV
#===================================================================

#CO_all <- read.csv("C:\\keser\\input\\dt_keser_feature_cooccur.csv")
#freq_all <- read.csv("C:\\keser\\input\\dt_keser_feature_count.csv")

#===================================================================
# RUN KESER (GENERATE EMBEDDINGS)
#===================================================================

library(KESER.i2b2)

# Set the output directory for debugging files
output_dir <- "C:\\keser\\output\\"

# Set the column names
colnames(CO_all) <- c("cohort","index1","index2","count")
colnames(freq_all) <- c("cohort","index","code","description","freq_count")

# Split into training and test cohorts
CO_train <- CO_all[CO_all$cohort == 0, c("index1","index2","count")]
CO_test <- CO_all[CO_all$cohort == 1, c("index1","index2","count")]
freq_train <- freq_all[freq_all$cohort == 0, c("index","code","description","freq_count")]
freq_test <- freq_all[freq_all$cohort == 1, c("index","code","description","freq_count")]

# Get embeddings for training data
dims_train <- seq(100, 1000, 100)
out_dir <- NULL
summary_train <- get_eval_embed(use.dataframe = TRUE, CO_file = CO_train, freq_file = freq_train, dims = dims_train, out_dir = output_dir, save.summary = FALSE)
#get_report(summary_train, plot_val = "auc", knit_format = "html")
best_train <- get_best_dim(summary_train)
embed_train <- best_train$embedding
best_dim <- best_train$dim

# Get embeddings for test data
summary_test <- get_eval_embed(use.dataframe = TRUE, CO_file = CO_test, freq_file = freq_test, dims = best_dim, save.summary = FALSE)
best_test <- get_best_dim(summary_test)
embed_test <- best_test$embedding

# Pivot the training embeddings for the database
embed_m <- embed_train
colnames(embed_m) <- as.list(as.character(seq(best_dim)))
embed_df <- as.data.frame.table(embed_m)
embed_all <- data.frame(cohort=0, feature_cd=embed_df$Var1, dim=as.integer(embed_df$Var2), val=embed_df$Freq)

# Pivot the test embeddings for the database
embed_m <- embed_test
colnames(embed_m) <- as.list(as.character(seq(best_dim)))
embed_df <- as.data.frame.table(embed_m)
embed_all <- rbind(embed_all, data.frame(cohort=1, feature_cd=embed_df$Var1, dim=as.integer(embed_df$Var2), val=embed_df$Freq))

#===================================================================
# OPTION 1: EXPORT RESULTS TO A DATABASE
#===================================================================

colnames(embed_all) <- toupper(names(embed_all))
dbWriteTable(con, DBI::Id(schema="dbo", table="DT_KESER_EMBEDDING"), embed_all, overwrite=FALSE, append=TRUE)
#dbWriteTable(con, DBI::Id(table="DT_KESER_EMBEDDING"), embed_all, overwrite=FALSE, append=TRUE)
dbDisconnect(con)

#===================================================================
# OPTION 2: EXPORT RESULTS TO CSV
#===================================================================

#write.csv(embed_all, file="C:\\keser\\output\\dt_keser_embedding.csv", row.names=FALSE, quote=FALSE)

