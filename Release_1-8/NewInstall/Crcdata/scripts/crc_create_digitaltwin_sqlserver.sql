-- ********************************************************
-- *           SQL SERVER SCRIPT TO CREATE DATA TABLES 
-- *            FOR "DIGITAL TWIN" DERIVED FACT TOOLS
-- *               Last updated 03/2024
-- **********************************************************/
-- 
-- ********************************************************
-- *           LOYALTY COHORT - See this publication:
-- * Klann JG, Henderson DW, Morris M, et al. A broadly applicable approach to enrich 
-- * electronic-health-record cohorts by identifying patients with complete data: a 
-- * multisite evaluation. J Am Med Inform Assoc Published Online First: 25 August 2023. 
-- * doi:10.1093/jamia/ocad166
-- **********************************************************/



CREATE TABLE [DBO].[DT_LOYALTY_PATHS]( -- Was DT_LOYALTY_PATHS
	[FEATURE_NAME] [VARCHAR](50) NULL,
	[CODE_TYPE] [VARCHAR](50) NULL,
	[CONCEPT_PATH] [VARCHAR](500) NULL,
	[SITE_SPECIFIC_CODE] [VARCHAR](10) NULL,
	[COMMENT] [VARCHAR](250) NULL,
) ON [PRIMARY];

CREATE CLUSTERED INDEX [NDX_PATH] ON [DBO].[DT_LOYALTY_PATHS]
(
	[CONCEPT_PATH] ASC,
	[FEATURE_NAME] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON);

SET ANSI_PADDING OFF;


CREATE TABLE [DBO].[DT_LOYALTY_CHARLSON]( -- Was DT_LOYALTY_CHARLSON
	[CHARLSON_CATGRY] [varchar](50) NULL,
	[CHARLSON_WT] INT NULL,
	[DIAGPATTERN] [varchar](50) NULL
) ON [PRIMARY];

CREATE TABLE [DBO].[DT_LOYALTY_PSCOEFF] ( -- Was DT_LOYALTY_PSCOEFF
  FIELD_NAME VARCHAR(50),
  COEFF NUMERIC(4,3)
);

  CREATE TABLE DBO.[DT_LOYALTY_RESULT_SUMMARY](
    [COHORT_NAME] VARCHAR(100) NOT NULL,
    [SITE] VARCHAR(10) NOT NULL,
    [GENDER_DENOMINATORS_YN] CHAR(1) NOT NULL,
    [CUTOFF_FILTER_YN] CHAR(1) NOT NULL,
    [SUMMARY_DESCRIPTION] VARCHAR(20) NOT NULL,
	  [TABLE_NAME] [VARCHAR](20) NULL,
	  [NUM_DX1] FLOAT NULL,
	  [NUM_DX2] FLOAT NULL,
	  [MED_USE1] FLOAT NULL,
	  [MED_USE2] FLOAT NULL,
	  [MAMMOGRAPHY] FLOAT NULL,
	  [PAP_TEST] FLOAT NULL,
	  [PSA_TEST] FLOAT NULL,
	  [COLONOSCOPY] FLOAT NULL,
	  [FECAL_OCCULT_TEST] FLOAT NULL,
	  [FLU_SHOT] FLOAT NULL,
	  [PNEUMOCOCCAL_VACCINE] FLOAT NULL,
	  [BMI] FLOAT NULL,
	  [A1C] FLOAT NULL,
	  [MEDICAL_EXAM] FLOAT NULL,
	  [INP1_OPT1_VISIT] FLOAT NULL,
	  [OPT2_VISIT] FLOAT NULL,
	  [ED_VISIT] FLOAT NULL,
	  [MDVISIT_PNAME2] FLOAT NULL,
	  [MDVISIT_PNAME3] FLOAT NULL,
	  [ROUTINE_CARE_2] FLOAT NULL,
	  [SUBJECTS_NOCRITERIA] FLOAT NULL,
	  [PREDICTIVE_SCORE_CUTOFF] FLOAT NULL,
	  [MEAN_10YR_PROB] FLOAT NULL,
	  [MEDIAN_10YR_PROB] FLOAT NULL,
	  [MODE_10YR_PROB] FLOAT NULL,
	  [STDEV_10YR_PROB] FLOAT NULL,
    [TOTAL_SUBJECTS] INT NULL,
    [TOTAL_SUBJECTS_FEMALE] INT NULL,
    [TOTAL_SUBJECTS_MALE] INT NULL,
    [PERCENT_POPULATION] FLOAT NULL,
    [PERCENT_SUBJECTS_FEMALE] FLOAT NULL,
    [PERCENT_SUBJECTS_MALE] FLOAT NULL,
    [AVERAGE_FACT_COUNT] FLOAT NULL,
    [EXTRACT_DTTM] DATETIME NOT NULL DEFAULT GETDATE(),
    [LOOKBACK_YR] INT NOT NULL,
    [RUNTIME_MS] INT NULL
  );

  CREATE TABLE [DBO].[DT_LOYALTY_RESULT](
	  [LOOKBACK_YEARS] [INT] NOT NULL,
	  [GENDER_DENOMINATORS_YN] [CHAR](1) NOT NULL,
	  [SITE] [VARCHAR](100) NOT NULL,
	  [COHORT_NAME] [VARCHAR](100) NOT NULL,
	  [PATIENT_NUM] [INT] NOT NULL,
    [DEATH_DT] DATE NULL, /* ADDED OCT2022 */
	  [INDEX_DT] [DATE] NULL,
	  [SEX] [VARCHAR](50) NULL,
	  [AGE] [INT] NULL,
	  [AGE_GRP] [VARCHAR](20) NULL,
	  [NUM_DX1] [BIT] NOT NULL,
	  [NUM_DX2] [BIT] NOT NULL,
	  [MED_USE1] [BIT] NOT NULL,
	  [MED_USE2] [BIT] NOT NULL,
	  [MAMMOGRAPHY] [BIT] NOT NULL,
	  [PAP_TEST] [BIT] NOT NULL,
	  [PSA_TEST] [BIT] NOT NULL,
	  [COLONOSCOPY] [BIT] NOT NULL,
	  [FECAL_OCCULT_TEST] [BIT] NOT NULL,
	  [FLU_SHOT] [BIT] NOT NULL,
	  [PNEUMOCOCCAL_VACCINE] [BIT] NOT NULL,
	  [BMI] [BIT] NOT NULL,
	  [A1C] [BIT] NOT NULL,
	  [MEDICAL_EXAM] [BIT] NOT NULL,
	  [INP1_OPT1_VISIT] [BIT] NOT NULL,
	  [OPT2_VISIT] [BIT] NOT NULL,
	  [ED_VISIT] [BIT] NOT NULL,
	  [MDVISIT_PNAME2] [BIT] NOT NULL,
	  [MDVISIT_PNAME3] [BIT] NOT NULL,
	  [ROUTINE_CARE_2] [BIT] NOT NULL,
	  [PREDICTED_SCORE] [FLOAT] NOT NULL
  );
  
  CREATE TABLE [DBO].[DT_LOYALTY_RESULT_CHARLSON](
	  [LOOKBACK_YEARS] [INT] NULL,
	  [GENDER_DENOMINATORS_YN] [CHAR](1) NULL,
	  [SITE] [VARCHAR](100) NULL,
	  [COHORT_NAME] [VARCHAR](100) NOT NULL,
	  [PATIENT_NUM] [INT] NOT NULL,
    [DEATH_DT] DATE NULL, /* ADDED OCT2022 */
	  [LAST_VISIT] [DATE] NULL,
    [SEX] [VARCHAR](50) NULL,
	  [AGE] [INT] NULL,
	  [AGE_GRP] [VARCHAR](20) NULL,
	  [CHARLSON_INDEX] [INT] NULL,
	  [CHARLSON_10YR_PROB] [NUMERIC](10, 4) NULL,
	  [MI] [INT] NULL,
	  [CHF] [INT] NULL,
	  [CVD] [INT] NULL,
	  [PVD] [INT] NULL,
	  [DEMENTIA] [INT] NULL,
	  [COPD] [INT] NULL,
	  [RHEUMDIS] [INT] NULL,
	  [PEPULCER] [INT] NULL,
	  [MILDLIVDIS] [INT] NULL,
	  [DIABETES_NOCC] [INT] NULL,
	  [DIABETES_WTCC] [INT] NULL,
	  [HEMIPARAPLEG] [INT] NULL,
	  [RENALDIS] [INT] NULL,
	  [CANCER] [INT] NULL,
	  [MSVLIVDIS] [INT] NULL,
	  [METASTATIC] [INT] NULL,
	  [AIDSHIV] [INT] NULL
  );
  
CREATE TYPE DBO.UDT_DT_LOYALTY_COHORTFILTER AS TABLE (PATIENT_NUM INT, COHORT_NAME VARCHAR(100), INDEX_DT DATE);

--##############################################################################
--##############################################################################
--### KESER - Create Tables
--### Date: September 1, 2023
--### Database: Microsoft SQL Server
--### Created By: Griffin Weber (weber@hms.harvard.edu)
--##############################################################################
--##############################################################################


--------------------------------------------------------------------------------
-- Drop existing tables.
--------------------------------------------------------------------------------

-- IF OBJECT_ID(N'DBO.DT_KESER_IMPORT_CONCEPT_FEATURE', N'U') IS NOT NULL DROP TABLE DBO.DT_KESER_IMPORT_CONCEPT_FEATURE;
-- IF OBJECT_ID(N'DBO.DT_KESER_FEATURE', N'U') IS NOT NULL DROP TABLE DBO.DT_KESER_FEATURE;
-- IF OBJECT_ID(N'DBO.DT_KESER_CONCEPT_FEATURE', N'U') IS NOT NULL DROP TABLE DBO.DT_KESER_CONCEPT_FEATURE;
-- IF OBJECT_ID(N'DBO.DT_KESER_CONCEPT_CHILDREN', N'U') IS NOT NULL DROP TABLE DBO.DT_KESER_CONCEPT_CHILDREN;
-- IF OBJECT_ID(N'DBO.DT_KESER_PATIENT_PARTITION', N'U') IS NOT NULL DROP TABLE DBO.DT_KESER_PATIENT_PARTITION;
-- IF OBJECT_ID(N'DBO.DT_KESER_PATIENT_PERIOD_FEATURE', N'U') IS NOT NULL DROP TABLE DBO.DT_KESER_PATIENT_PERIOD_FEATURE;
-- IF OBJECT_ID(N'DBO.DT_KESER_FEATURE_COUNT', N'U') IS NOT NULL DROP TABLE DBO.DT_KESER_FEATURE_COUNT;
-- IF OBJECT_ID(N'DBO.DT_KESER_FEATURE_COOCCUR_TEMP', N'U') IS NOT NULL DROP TABLE DBO.DT_KESER_FEATURE_COOCCUR_TEMP;
-- IF OBJECT_ID(N'DBO.DT_KESER_FEATURE_COOCCUR', N'U') IS NOT NULL DROP TABLE DBO.DT_KESER_FEATURE_COOCCUR;
-- IF OBJECT_ID(N'DBO.DT_KESER_EMBEDDING', N'U') IS NOT NULL DROP TABLE DBO.DT_KESER_EMBEDDING;
-- IF OBJECT_ID(N'DBO.DT_KESER_PHENOTYPE', N'U') IS NOT NULL DROP TABLE DBO.DT_KESER_PHENOTYPE;
-- IF OBJECT_ID(N'DBO.DT_KESER_PHENOTYPE_FEATURE', N'U') IS NOT NULL DROP TABLE DBO.DT_KESER_PHENOTYPE_FEATURE;


--------------------------------------------------------------------------------
-- Create tables for mapping features to local concepts.
--------------------------------------------------------------------------------

CREATE TABLE DBO.DT_KESER_IMPORT_CONCEPT_FEATURE (
	CONCEPT_CD VARCHAR(50) NOT NULL,
	FEATURE_CD VARCHAR(50) NOT NULL,
	FEATURE_NAME VARCHAR(250) NOT NULL
);

CREATE TABLE DBO.DT_KESER_FEATURE (
	FEATURE_NUM INT NOT NULL,
	FEATURE_CD VARCHAR(50) NOT NULL,
	FEATURE_NAME VARCHAR(250) NOT NULL,
	PRIMARY KEY (FEATURE_NUM)
);
CREATE NONCLUSTERED INDEX IDX_FEATURE_CD ON DBO.DT_KESER_FEATURE(FEATURE_CD);

CREATE TABLE DBO.DT_KESER_CONCEPT_FEATURE (
	CONCEPT_CD VARCHAR(50) NOT NULL,
	FEATURE_NUM INT NOT NULL,
	PRIMARY KEY (CONCEPT_CD, FEATURE_NUM)
);
CREATE UNIQUE NONCLUSTERED INDEX IDX_FEATURE_CONCEPT ON DBO.DT_KESER_CONCEPT_FEATURE(FEATURE_NUM, CONCEPT_CD);

CREATE TABLE DBO.DT_KESER_CONCEPT_CHILDREN (
	CONCEPT_CD VARCHAR(50) NOT NULL,
	CHILD_CD VARCHAR(50) NOT NULL,
	PRIMARY KEY (CONCEPT_CD, CHILD_CD)
)

--------------------------------------------------------------------------------
-- Create tables for patient data.
--------------------------------------------------------------------------------

CREATE TABLE DBO.DT_KESER_PATIENT_PARTITION (
	PATIENT_NUM INT NOT NULL,
	PATIENT_PARTITION TINYINT NOT NULL,
	PRIMARY KEY (PATIENT_NUM)
);

CREATE TABLE DBO.DT_KESER_PATIENT_PERIOD_FEATURE (
	PATIENT_PARTITION TINYINT NOT NULL,
	PATIENT_NUM INT NOT NULL,
	TIME_PERIOD INT NOT NULL,
	FEATURE_NUM INT NOT NULL,
	MIN_OFFSET SMALLINT NOT NULL,
	MAX_OFFSET SMALLINT NOT NULL,
	FEATURE_DATES SMALLINT,
	CONCEPT_DATES INT,
	PRIMARY KEY (PATIENT_PARTITION, PATIENT_NUM, TIME_PERIOD, FEATURE_NUM)
);

CREATE TABLE DBO.DT_KESER_FEATURE_COUNT (
	COHORT TINYINT NOT NULL,
	FEATURE_NUM INT NOT NULL,
	FEATURE_CD VARCHAR(50) NOT NULL,
	FEATURE_NAME VARCHAR(250) NOT NULL,
	FEATURE_COUNT INT NOT NULL,
	PRIMARY KEY (COHORT, FEATURE_NUM)
);

CREATE TABLE DBO.DT_KESER_FEATURE_COOCCUR_TEMP (
	COHORT TINYINT NOT NULL,
	FEATURE_NUM1 INT NOT NULL,
	FEATURE_NUM2 INT NOT NULL,
	NUM_PATIENTS INT NOT NULL
);

CREATE TABLE DBO.DT_KESER_FEATURE_COOCCUR (
	COHORT TINYINT NOT NULL,
	FEATURE_NUM1 INT NOT NULL,
	FEATURE_NUM2 INT NOT NULL,
	COOCUR_COUNT INT NOT NULL,
	PRIMARY KEY (COHORT, FEATURE_NUM1, FEATURE_NUM2)
);

--------------------------------------------------------------------------------
-- Create table to store embeddings.
--------------------------------------------------------------------------------

CREATE TABLE DBO.DT_KESER_EMBEDDING (
	COHORT TINYINT NOT NULL,
	FEATURE_CD VARCHAR(50) NOT NULL,
	DIM INT NOT NULL,
	VAL FLOAT NOT NULL,
	PRIMARY KEY (COHORT, FEATURE_CD, DIM)
);

--------------------------------------------------------------------------------
-- Create tables for embedding regression (map phenotypes to features).
--------------------------------------------------------------------------------

CREATE TABLE DBO.DT_KESER_PHENOTYPE (
	PHENOTYPE VARCHAR(50) NOT NULL
	PRIMARY KEY (PHENOTYPE)
);

CREATE TABLE DBO.DT_KESER_PHENOTYPE_FEATURE (
	PHENOTYPE VARCHAR(50) NOT NULL,
	FEATURE_CD VARCHAR(50) NOT NULL,
	FEATURE_RANK INT,
	FEATURE_BETA FLOAT,
	FEATURE_COSINE FLOAT,
	PRIMARY KEY (PHENOTYPE, FEATURE_CD)
);


--------------------------------------------------------------------------------
-- Truncate tables.
--------------------------------------------------------------------------------
--
-- TRUNCATE TABLE DBO.DT_KESER_IMPORT_CONCEPT_FEATURE;
-- TRUNCATE TABLE DBO.DT_KESER_FEATURE;
-- TRUNCATE TABLE DBO.DT_KESER_CONCEPT_FEATURE;
-- TRUNCATE TABLE DBO.DT_KESER_CONCEPT_CHILDREN;
-- TRUNCATE TABLE DBO.DT_KESER_PATIENT_PARTITION;
-- TRUNCATE TABLE DBO.DT_KESER_PATIENT_PERIOD_FEATURE;
-- TRUNCATE TABLE DBO.DT_KESER_FEATURE_COUNT;
-- TRUNCATE TABLE DBO.DT_KESER_FEATURE_COOCCUR_TEMP;
-- TRUNCATE TABLE DBO.DT_KESER_FEATURE_COOCCUR;
-- TRUNCATE TABLE DBO.DT_KESER_EMBEDDING;
-- TRUNCATE TABLE DBO.DT_KESER_PHENOTYPE;
-- TRUNCATE TABLE DBO.DT_KESER_PHENOTYPE_FEATURE;



--##############################################################################
--##############################################################################
--### KOMAP - Create Tables
--### Date: April 23, 2024
--### Database: Microsoft SQL Server
--### Created By: Griffin Weber (weber@hms.harvard.edu)
--##############################################################################
--##############################################################################


--------------------------------------------------------------------------------
-- Drop existing tables.
--------------------------------------------------------------------------------

-- IF OBJECT_ID(N'DBO.DT_KOMAP_PHENOTYPE', N'U') IS NOT NULL DROP TABLE DBO.DT_KOMAP_PHENOTYPE;
-- IF OBJECT_ID(N'DBO.DT_KOMAP_PHENOTYPE_FEATURE_DICT', N'U') IS NOT NULL DROP TABLE DBO.DT_KOMAP_PHENOTYPE_FEATURE_DICT;
-- IF OBJECT_ID(N'DBO.DT_KOMAP_PATIENT_FEATURE', N'U') IS NOT NULL DROP TABLE DBO.DT_KOMAP_PATIENT_FEATURE;
-- IF OBJECT_ID(N'DBO.DT_KOMAP_BASE_COHORT', N'U') IS NOT NULL DROP TABLE DBO.DT_KOMAP_BASE_COHORT;
-- IF OBJECT_ID(N'DBO.DT_KOMAP_PHENOTYPE_SAMPLE', N'U') IS NOT NULL DROP TABLE DBO.DT_KOMAP_PHENOTYPE_SAMPLE;
-- IF OBJECT_ID(N'DBO.DT_KOMAP_PHENOTYPE_SAMPLE_FEATURE', N'U') IS NOT NULL DROP TABLE DBO.DT_KOMAP_PHENOTYPE_SAMPLE_FEATURE;
-- IF OBJECT_ID(N'DBO.DT_KOMAP_PHENOTYPE_SAMPLE_FEATURE_TEMP', N'U') IS NOT NULL DROP TABLE DBO.DT_KOMAP_PHENOTYPE_SAMPLE_FEATURE_TEMP;
-- IF OBJECT_ID(N'DBO.DT_KOMAP_PHENOTYPE_COVAR_INNER', N'U') IS NOT NULL DROP TABLE DBO.DT_KOMAP_PHENOTYPE_COVAR_INNER;
-- IF OBJECT_ID(N'DBO.DT_KOMAP_PHENOTYPE_COVAR', N'U') IS NOT NULL DROP TABLE DBO.DT_KOMAP_PHENOTYPE_COVAR;
-- IF OBJECT_ID(N'DBO.DT_KOMAP_PHENOTYPE_FEATURE_COEF', N'U') IS NOT NULL DROP TABLE DBO.DT_KOMAP_PHENOTYPE_FEATURE_COEF;
-- IF OBJECT_ID(N'DBO.DT_KOMAP_PHENOTYPE_SAMPLE_RESULTS', N'U') IS NOT NULL DROP TABLE DBO.DT_KOMAP_PHENOTYPE_SAMPLE_RESULTS;
-- IF OBJECT_ID(N'DBO.DT_KOMAP_PHENOTYPE_GMM', N'U') IS NOT NULL DROP TABLE DBO.DT_KOMAP_PHENOTYPE_GMM;
-- IF OBJECT_ID(N'DBO.DT_KOMAP_PHENOTYPE_GOLD_STANDARD', N'U') IS NOT NULL DROP TABLE DBO.DT_KOMAP_PHENOTYPE_GOLD_STANDARD;
-- IF OBJECT_ID(N'DBO.DT_KOMAP_PHENOTYPE_PATIENT', N'U') IS NOT NULL DROP TABLE DBO.DT_KOMAP_PHENOTYPE_PATIENT;
-- IF OBJECT_ID(N'DBO.DERIVED_FACT', N'U') IS NOT NULL DROP TABLE DBO.DERIVED_FACT;


--------------------------------------------------------------------------------
-- Create new tables to list the phenotypes and their features.
--------------------------------------------------------------------------------

CREATE TABLE DBO.DT_KOMAP_PHENOTYPE (
	PHENOTYPE VARCHAR(50) NOT NULL,
	PHENOTYPE_NAME VARCHAR(50) NOT NULL,
	THRESHOLD FLOAT,
	GMM_MEAN1 FLOAT,
	GMM_MEAN2 FLOAT,
	GMM_STDEV1 FLOAT,
	GMM_STDEV2 FLOAT,
	PPV FLOAT,
	RECALL FLOAT,
	RECALL_BASE_COHORT FLOAT,
	RECALL_HAS_FEATURE FLOAT,
	FRAC_FEATURE_IN_BASE_COHORT FLOAT,
	GENERATE_FACTS INT,
	PRIMARY KEY (PHENOTYPE)
);

CREATE TABLE DBO.DT_KOMAP_PHENOTYPE_FEATURE_DICT (
	PHENOTYPE VARCHAR(50) NOT NULL,
	FEATURE_CD VARCHAR(50) NOT NULL,
	FEATURE_NAME VARCHAR(250)
	PRIMARY KEY (PHENOTYPE, FEATURE_CD)
);

--------------------------------------------------------------------------------
-- Create new tables to generate the input data for KOMAP.
--------------------------------------------------------------------------------

CREATE TABLE DBO.DT_KOMAP_PATIENT_FEATURE (
	PATIENT_NUM INT NOT NULL,
	FEATURE_CD VARCHAR(50) NOT NULL,
	NUM_DATES INT NOT NULL,
	LOG_DATES FLOAT NOT NULL,
	PRIMARY KEY (FEATURE_CD, PATIENT_NUM)
);

CREATE TABLE DBO.DT_KOMAP_BASE_COHORT (
	PATIENT_NUM INT NOT NULL,
	PRIMARY KEY (PATIENT_NUM)
);

CREATE TABLE DBO.DT_KOMAP_PHENOTYPE_SAMPLE (
	PHENOTYPE VARCHAR(50) NOT NULL,
	PATIENT_NUM INT NOT NULL,
	PRIMARY KEY (PHENOTYPE, PATIENT_NUM)
);

CREATE TABLE DBO.DT_KOMAP_PHENOTYPE_SAMPLE_FEATURE (
	PHENOTYPE VARCHAR(50) NOT NULL,
	PATIENT_NUM INT NOT NULL,
	FEATURE_CD VARCHAR(50) NOT NULL,
	NUM_DATES INT NOT NULL,
	LOG_DATES FLOAT NOT NULL,
	PRIMARY KEY (PHENOTYPE, FEATURE_CD, PATIENT_NUM)
);

CREATE TABLE DBO.DT_KOMAP_PHENOTYPE_SAMPLE_FEATURE_TEMP (
	PHENOTYPE VARCHAR(50) NOT NULL,
	PATIENT_NUM INT NOT NULL,
	FEATURE_CD VARCHAR(50) NOT NULL,
	NUM_DATES INT NOT NULL,
	LOG_DATES FLOAT NOT NULL,
	PRIMARY KEY (PATIENT_NUM, FEATURE_CD)
);

CREATE TABLE DBO.DT_KOMAP_PHENOTYPE_COVAR_INNER (
	PHENOTYPE VARCHAR(50) NOT NULL,
	FEATURE_CD1 VARCHAR(50) NOT NULL,
	FEATURE_CD2 VARCHAR(50) NOT NULL,
	NUM_PATIENTS INT,
	SUM_LOG_DATES FLOAT,
	PRIMARY KEY (PHENOTYPE, FEATURE_CD1, FEATURE_CD2)
);

CREATE TABLE DBO.DT_KOMAP_PHENOTYPE_COVAR (
	PHENOTYPE VARCHAR(50) NOT NULL,
	FEATURE_CD1 VARCHAR(50) NOT NULL,
	FEATURE_CD2 VARCHAR(50) NOT NULL,
	COVAR FLOAT,
	PRIMARY KEY (PHENOTYPE, FEATURE_CD1, FEATURE_CD2)
);

CREATE TABLE DBO.DT_KOMAP_PHENOTYPE_FEATURE_COEF (
	PHENOTYPE VARCHAR(50) NOT NULL,
	FEATURE_CD VARCHAR(50) NOT NULL,
	COEF FLOAT NOT NULL
	PRIMARY KEY (PHENOTYPE, FEATURE_CD)
);

--------------------------------------------------------------------------------
-- Create new tables to store and process the results of KOMAP.
--------------------------------------------------------------------------------

CREATE TABLE DBO.DT_KOMAP_PHENOTYPE_SAMPLE_RESULTS (
	PHENOTYPE VARCHAR(50) NOT NULL,
	PATIENT_NUM INT NOT NULL,
	SCORE FLOAT,
	PHECODE_DATES INT,
	UTILIZATION_DATES INT,
	PHECODE_SCORE FLOAT,
	UTILIZATION_SCORE FLOAT,
	OTHER_POSITIVE_FEATURE_SCORE FLOAT,
	OTHER_NEGATIVE_FEATURE_SCORE FLOAT
	PRIMARY KEY (PHENOTYPE, PATIENT_NUM)
);

CREATE TABLE DBO.DT_KOMAP_PHENOTYPE_GMM (
	PHENOTYPE VARCHAR(50) NOT NULL,
	SCORE_PERCENTILE INT NOT NULL,
	SCORE FLOAT,
	M1 FLOAT,
	M2 FLOAT,
	S1 FLOAT,
	S2 FLOAT,
	G1 FLOAT,
	G2 FLOAT,
	P1 FLOAT,
	P2 FLOAT,
	PRIMARY KEY (PHENOTYPE, SCORE_PERCENTILE)
);

CREATE TABLE DBO.DT_KOMAP_PHENOTYPE_GOLD_STANDARD (
	PHENOTYPE VARCHAR(50) NOT NULL,
	PATIENT_NUM INT NOT NULL,
	HAS_PHENOTYPE INT,
	SCORE FLOAT NULL
	PRIMARY KEY (PHENOTYPE, PATIENT_NUM)
);

CREATE TABLE DBO.DT_KOMAP_PHENOTYPE_PATIENT (
	PHENOTYPE VARCHAR(50) NOT NULL,
	PATIENT_NUM INT NOT NULL,
	SCORE FLOAT,
	PRIMARY KEY (PHENOTYPE, PATIENT_NUM)
);

--------------------------------------------------------------------------------
-- Create a DERIVED_FACT table if one does not alreay exist.
--------------------------------------------------------------------------------

-- CREATE TABLE DBO.DERIVED_FACT(
-- 	ENCOUNTER_NUM int NOT NULL,
-- 	PATIENT_NUM int NOT NULL,
-- 	CONCEPT_CD varchar(50) NOT NULL,
-- 	PROVIDER_ID varchar(50) NOT NULL,
-- 	START_DATE datetime NOT NULL,
-- 	MODIFIER_CD varchar(100) NOT NULL,
-- 	INSTANCE_NUM int NOT NULL,
-- 	VALTYPE_CD varchar(50),
-- 	TVAL_CHAR varchar(255),
-- 	NVAL_NUM decimal(18,5),
-- 	VALUEFLAG_CD varchar(50),
-- 	QUANTITY_NUM decimal(18,5),
-- 	UNITS_CD varchar(50),
-- 	END_DATE datetime NULL,
-- 	LOCATION_CD varchar(50),
-- 	OBSERVATION_BLOB text NULL,
-- 	CONFIDENCE_NUM decimal(18,5),
-- 	UPDATE_DATE datetime NULL,
-- 	DOWNLOAD_DATE datetime NULL,
-- 	IMPORT_DATE datetime NULL,
-- 	SOURCESYSTEM_CD varchar(50),
-- 	UPLOAD_ID int
-- )
-- ALTER TABLE DBO.DERIVED_FACT ADD PRIMARY KEY (CONCEPT_CD,PATIENT_NUM,ENCOUNTER_NUM,START_DATE,PROVIDER_ID,INSTANCE_NUM,MODIFIER_CD)
-- CREATE NONCLUSTERED INDEX DF_IDX_CONCEPT_DATE_PATIENT ON DBO.DERIVED_FACT  (CONCEPT_CD, START_DATE, PATIENT_NUM)
-- CREATE NONCLUSTERED INDEX DF_IDX_ENCOUNTER_PATIENT_CONCEPT_DATE ON DBO.DERIVED_FACT  (ENCOUNTER_NUM, PATIENT_NUM, CONCEPT_CD, START_DATE)
-- CREATE NONCLUSTERED INDEX DF_IDX_PATIENT_CONCEPT_DATE ON DBO.DERIVED_FACT  (PATIENT_NUM, CONCEPT_CD, START_DATE)



--------------------------------------------------------------------------------
-- Truncate tables.
--------------------------------------------------------------------------------

-- TRUNCATE TABLE DBO.DT_KOMAP_PHENOTYPE;
-- TRUNCATE TABLE DBO.DT_KOMAP_PHENOTYPE_FEATURE_DICT;
-- TRUNCATE TABLE DBO.DT_KOMAP_PATIENT_FEATURE;
-- TRUNCATE TABLE DBO.DT_KOMAP_BASE_COHORT;
-- TRUNCATE TABLE DBO.DT_KOMAP_PHENOTYPE_SAMPLE;
-- TRUNCATE TABLE DBO.DT_KOMAP_PHENOTYPE_SAMPLE_FEATURE;
-- TRUNCATE TABLE DBO.DT_KOMAP_PHENOTYPE_SAMPLE_FEATURE_TEMP;
-- TRUNCATE TABLE DBO.DT_KOMAP_PHENOTYPE_COVAR_INNER;
-- TRUNCATE TABLE DBO.DT_KOMAP_PHENOTYPE_COVAR;
-- TRUNCATE TABLE DBO.DT_KOMAP_PHENOTYPE_FEATURE_COEF;
-- TRUNCATE TABLE DBO.DT_KOMAP_PHENOTYPE_SAMPLE_RESULTS;
-- TRUNCATE TABLE DBO.DT_KOMAP_PHENOTYPE_GMM;
-- TRUNCATE TABLE DBO.DT_KOMAP_PHENOTYPE_GOLD_STANDARD;
-- TRUNCATE TABLE DBO.DT_KOMAP_PHENOTYPE_PATIENT;
-- --TRUNCATE TABLE DBO.DERIVED_FACT;


