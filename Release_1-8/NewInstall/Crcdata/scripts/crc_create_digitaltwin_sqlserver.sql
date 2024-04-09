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

-- Externally validated coefficients
INSERT INTO DT_LOYALTY_PSCOEFF (FIELD_NAME, COEFF)
VALUES ('MDVISIT_PNAME2',0.049)
,('MDVISIT_PNAME3',0.087)
,('MEDICAL_EXAM',0.078)
,('MAMMOGRAPHY',0.075)
,('PAP_TEST',0.009)
,('PSA_TEST',0.103)
,('COLONOSCOPY',0.064)
,('FECAL_OCCULT_TEST',0.034)
,('FLU_SHOT',0.102)
,('PNEUMOCOCCAL_VACCINE',0.031)
,('BMI',0.017)
,('A1C',0.018)
,('MED_USE1',0.002)
,('MED_USE2',0.074)
,('INP1_OPT1_VISIT',0.091)
,('OPT2_VISIT',0.050)
,('NUM_DX1',-0.026)
,('NUM_DX2',0.037)
,('ED_VISIT',0.078)
,('ROUTINE_CARE_2',0.049);

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

-- if OBJECT_ID(N'dbo.dt_keser_import_concept_feature', N'U') is not null drop table dbo.dt_keser_import_concept_feature;
-- if OBJECT_ID(N'dbo.dt_keser_feature', N'U') is not null drop table dbo.dt_keser_feature;
-- if OBJECT_ID(N'dbo.dt_keser_concept_feature', N'U') is not null drop table dbo.dt_keser_concept_feature;
-- if OBJECT_ID(N'dbo.dt_keser_concept_children', N'U') is not null drop table dbo.dt_keser_concept_children;
-- if OBJECT_ID(N'dbo.dt_keser_patient_partition', N'U') is not null drop table dbo.dt_keser_patient_partition;
-- if OBJECT_ID(N'dbo.dt_keser_patient_period_feature', N'U') is not null drop table dbo.dt_keser_patient_period_feature;
-- if OBJECT_ID(N'dbo.dt_keser_feature_count', N'U') is not null drop table dbo.dt_keser_feature_count;
-- if OBJECT_ID(N'dbo.dt_keser_feature_cooccur_temp', N'U') is not null drop table dbo.dt_keser_feature_cooccur_temp;
-- if OBJECT_ID(N'dbo.dt_keser_feature_cooccur', N'U') is not null drop table dbo.dt_keser_feature_cooccur;
-- if OBJECT_ID(N'dbo.dt_keser_embedding', N'U') is not null drop table dbo.dt_keser_embedding;
-- if OBJECT_ID(N'dbo.dt_keser_phenotype', N'U') is not null drop table dbo.dt_keser_phenotype;
-- if OBJECT_ID(N'dbo.dt_keser_phenotype_feature', N'U') is not null drop table dbo.dt_keser_phenotype_feature;


--------------------------------------------------------------------------------
-- Create tables for mapping features to local concepts.
--------------------------------------------------------------------------------

create table dbo.dt_keser_import_concept_feature (
	concept_cd varchar(50) not null,
	feature_cd varchar(50) not null,
	feature_name varchar(250) not null
);

create table dbo.dt_keser_feature (
	feature_num int not null,
	feature_cd varchar(50) not null,
	feature_name varchar(250) not null,
	primary key (feature_num)
);
create nonclustered index idx_feature_cd on dbo.dt_keser_feature(feature_cd);

create table dbo.dt_keser_concept_feature (
	concept_cd varchar(50) not null,
	feature_num int not null,
	primary key (concept_cd, feature_num)
);
create unique nonclustered index idx_feature_concept on dbo.dt_keser_concept_feature(feature_num, concept_cd);

create table dbo.dt_keser_concept_children (
	concept_cd varchar(50) not null,
	child_cd varchar(50) not null,
	primary key (concept_cd, child_cd)
)

--------------------------------------------------------------------------------
-- Create tables for patient data.
--------------------------------------------------------------------------------

create table dbo.dt_keser_patient_partition (
	patient_num int not null,
	patient_partition tinyint not null,
	primary key (patient_num)
);

create table dbo.dt_keser_patient_period_feature (
	patient_partition tinyint not null,
	patient_num int not null,
	time_period int not null,
	feature_num int not null,
	min_offset smallint not null,
	max_offset smallint not null,
	feature_dates smallint,
	concept_dates int,
	primary key (patient_partition, patient_num, time_period, feature_num)
);

create table dbo.dt_keser_feature_count (
	cohort tinyint not null,
	feature_num int not null,
	feature_cd varchar(50) not null,
	feature_name varchar(250) not null,
	feature_count int not null,
	primary key (cohort, feature_num)
);

create table dbo.dt_keser_feature_cooccur_temp (
	cohort tinyint not null,
	feature_num1 int not null,
	feature_num2 int not null,
	num_patients int not null
);

create table dbo.dt_keser_feature_cooccur (
	cohort tinyint not null,
	feature_num1 int not null,
	feature_num2 int not null,
	coocur_count int not null,
	primary key (cohort, feature_num1, feature_num2)
);

--------------------------------------------------------------------------------
-- Create table to store embeddings.
--------------------------------------------------------------------------------

create table dbo.dt_keser_embedding (
	cohort tinyint not null,
	feature_cd varchar(50) not null,
	dim int not null,
	val float not null,
	primary key (cohort, feature_cd, dim)
);

--------------------------------------------------------------------------------
-- Create tables for embedding regression (map phenotypes to features).
--------------------------------------------------------------------------------

create table dbo.dt_keser_phenotype (
	phenotype varchar(50) not null
	primary key (phenotype)
);

create table dbo.dt_keser_phenotype_feature (
	phenotype varchar(50) not null,
	feature_cd varchar(50) not null,
	feature_rank int,
	feature_beta float,
	feature_cosine float,
	primary key (phenotype, feature_cd)
);


--------------------------------------------------------------------------------
-- Truncate tables.
--------------------------------------------------------------------------------

/*
truncate table dbo.dt_keser_import_concept_feature;
truncate table dbo.dt_keser_feature;
truncate table dbo.dt_keser_concept_feature;
truncate table dbo.dt_keser_concept_children;
truncate table dbo.dt_keser_patient_partition;
truncate table dbo.dt_keser_patient_period_feature;
truncate table dbo.dt_keser_feature_count;
truncate table dbo.dt_keser_feature_cooccur_temp;
truncate table dbo.dt_keser_feature_cooccur;
truncate table dbo.dt_keser_embedding;
truncate table dbo.dt_keser_phenotype;
truncate table dbo.dt_keser_phenotype_feature;
*/



--##############################################################################
--##############################################################################
--### KOMAP - Create Tables
--### Date: September 1, 2023
--### Database: Microsoft SQL Server
--### Created By: Griffin Weber (weber@hms.harvard.edu)
--##############################################################################
--##############################################################################


--------------------------------------------------------------------------------
-- Drop existing tables.
--------------------------------------------------------------------------------

if OBJECT_ID(N'dbo.dt_komap_phenotype', N'U') is not null drop table dbo.dt_komap_phenotype;
if OBJECT_ID(N'dbo.dt_komap_phenotype_feature_dict', N'U') is not null drop table dbo.dt_komap_phenotype_feature_dict;
if OBJECT_ID(N'dbo.dt_komap_patient_feature', N'U') is not null drop table dbo.dt_komap_patient_feature;
if OBJECT_ID(N'dbo.dt_komap_base_cohort', N'U') is not null drop table dbo.dt_komap_base_cohort;
if OBJECT_ID(N'dbo.dt_komap_phenotype_sample', N'U') is not null drop table dbo.dt_komap_phenotype_sample;
if OBJECT_ID(N'dbo.dt_komap_phenotype_sample_feature', N'U') is not null drop table dbo.dt_komap_phenotype_sample_feature;
if OBJECT_ID(N'dbo.dt_komap_phenotype_covar_inner', N'U') is not null drop table dbo.dt_komap_phenotype_covar_inner;
if OBJECT_ID(N'dbo.dt_komap_phenotype_covar', N'U') is not null drop table dbo.dt_komap_phenotype_covar;
if OBJECT_ID(N'dbo.dt_komap_phenotype_feature_coef', N'U') is not null drop table dbo.dt_komap_phenotype_feature_coef;
if OBJECT_ID(N'dbo.dt_komap_phenotype_sample_results', N'U') is not null drop table dbo.dt_komap_phenotype_sample_results;
if OBJECT_ID(N'dbo.dt_komap_phenotype_gmm', N'U') is not null drop table dbo.dt_komap_phenotype_gmm;
if OBJECT_ID(N'dbo.dt_komap_phenotype_gold_standard', N'U') is not null drop table dbo.dt_komap_phenotype_gold_standard;
if OBJECT_ID(N'dbo.dt_komap_phenotype_patient', N'U') is not null drop table dbo.dt_komap_phenotype_patient;
--if OBJECT_ID(N'dbo.DERIVED_FACT', N'U') is not null drop table dbo.DERIVED_FACT;


--------------------------------------------------------------------------------
-- Create new tables to list the phenotypes and their features.
--------------------------------------------------------------------------------

create table dbo.dt_komap_phenotype (
	phenotype varchar(50) not null,
	phenotype_name varchar(50) not null,
	threshold float,
	gmm_mean1 float,
	gmm_mean2 float,
	gmm_stdev1 float,
	gmm_stdev2 float,
	ppv float,
	recall float,
	recall_base_cohort float,
	recall_has_feature float,
	frac_feature_in_base_cohort float,
	generate_facts int,
	primary key (phenotype)
);

create table dbo.dt_komap_phenotype_feature_dict (
	phenotype varchar(50) not null,
	feature_cd varchar(50) not null,
	feature_name varchar(250)
	primary key (phenotype, feature_cd)
);

--------------------------------------------------------------------------------
-- Create new tables to generate the input data for KOMAP.
--------------------------------------------------------------------------------

create table dbo.dt_komap_patient_feature (
	patient_num int not null,
	feature_cd varchar(50) not null,
	num_dates int not null,
	log_dates float not null,
	primary key (feature_cd, patient_num)
);

create table dbo.dt_komap_base_cohort (
	patient_num int not null,
	primary key (patient_num)
);

create table dbo.dt_komap_phenotype_sample (
	phenotype varchar(50) not null,
	patient_num int not null,
	primary key (phenotype, patient_num)
);

create table dbo.dt_komap_phenotype_sample_feature (
	phenotype varchar(50) not null,
	patient_num int not null,
	feature_cd varchar(50) not null,
	num_dates int not null,
	log_dates float not null,
	primary key (phenotype, feature_cd, patient_num)
);

create table dbo.dt_komap_phenotype_covar_inner (
	phenotype varchar(50) not null,
	feature_cd1 varchar(50) not null,
	feature_cd2 varchar(50) not null,
	num_patients int,
	sum_log_dates float,
	primary key (phenotype, feature_cd1, feature_cd2)
);

create table dbo.dt_komap_phenotype_covar (
	phenotype varchar(50) not null,
	feature_cd1 varchar(50) not null,
	feature_cd2 varchar(50) not null,
	covar float,
	primary key (phenotype, feature_cd1, feature_cd2)
);

create table dbo.dt_komap_phenotype_feature_coef (
	phenotype varchar(50) not null,
	feature_cd varchar(50) not null,
	coef float not null
	primary key (phenotype, feature_cd)
);

--------------------------------------------------------------------------------
-- Create new tables to store and process the results of KOMAP.
--------------------------------------------------------------------------------

create table dbo.dt_komap_phenotype_sample_results (
	phenotype varchar(50) not null,
	patient_num int not null,
	score float,
	phecode_dates int,
	utilization_dates int,
	phecode_score float,
	utilization_score float,
	other_positive_feature_score float,
	other_negative_feature_score float
	primary key (phenotype, patient_num)
);

create table dbo.dt_komap_phenotype_gmm (
	phenotype varchar(50) not null,
	score_percentile int not null,
	score float,
	m1 float,
	m2 float,
	s1 float,
	s2 float,
	g1 float,
	g2 float,
	p1 float,
	p2 float,
	primary key (phenotype, score_percentile)
);

create table dbo.dt_komap_phenotype_gold_standard (
	phenotype varchar(50) not null,
	patient_num int not null,
	has_phenotype int,
	score float null
	primary key (phenotype, patient_num)
);

create table dbo.dt_komap_phenotype_patient (
	phenotype varchar(50) not null,
	patient_num int not null,
	score float,
	primary key (phenotype, patient_num)
);

--------------------------------------------------------------------------------
-- Create a DERIVED_FACT table if one does not alreay exist.
--------------------------------------------------------------------------------

/*
create table dbo.DERIVED_FACT(
	ENCOUNTER_NUM int NOT NULL,
	PATIENT_NUM int NOT NULL,
	CONCEPT_CD varchar(50) NOT NULL,
	PROVIDER_ID varchar(50) NOT NULL,
	START_DATE datetime NOT NULL,
	MODIFIER_CD varchar(100) NOT NULL,
	INSTANCE_NUM int NOT NULL,
	VALTYPE_CD varchar(50),
	TVAL_CHAR varchar(255),
	NVAL_NUM decimal(18,5),
	VALUEFLAG_CD varchar(50),
	QUANTITY_NUM decimal(18,5),
	UNITS_CD varchar(50),
	END_DATE datetime NULL,
	LOCATION_CD varchar(50),
	OBSERVATION_BLOB text NULL,
	CONFIDENCE_NUM decimal(18,5),
	UPDATE_DATE datetime NULL,
	DOWNLOAD_DATE datetime NULL,
	IMPORT_DATE datetime NULL,
	SOURCESYSTEM_CD varchar(50),
	UPLOAD_ID int
)
alter table dbo.DERIVED_FACT add primary key (CONCEPT_CD,PATIENT_NUM,ENCOUNTER_NUM,START_DATE,PROVIDER_ID,INSTANCE_NUM,MODIFIER_CD)
create nonclustered index DF_IDX_CONCEPT_DATE_PATIENT on dbo.DERIVED_FACT  (CONCEPT_CD, START_DATE, PATIENT_NUM)
create nonclustered index DF_IDX_ENCOUNTER_PATIENT_CONCEPT_DATE on dbo.DERIVED_FACT  (ENCOUNTER_NUM, PATIENT_NUM, CONCEPT_CD, START_DATE)
create nonclustered index DF_IDX_PATIENT_CONCEPT_DATE on dbo.DERIVED_FACT  (PATIENT_NUM, CONCEPT_CD, START_DATE)
*/


--------------------------------------------------------------------------------
-- Truncate tables.
--------------------------------------------------------------------------------

/*
truncate table dbo.dt_komap_phenotype;
truncate table dbo.dt_komap_phenotype_feature_dict;
truncate table dbo.dt_komap_patient_feature;
truncate table dbo.dt_komap_base_cohort;
truncate table dbo.dt_komap_phenotype_sample;
truncate table dbo.dt_komap_phenotype_sample_feature;
truncate table dbo.dt_komap_phenotype_covar_inner;
truncate table dbo.dt_komap_phenotype_covar;
truncate table dbo.dt_komap_phenotype_feature_coef;
truncate table dbo.dt_komap_phenotype_sample_results;
truncate table dbo.dt_komap_phenotype_gmm;
truncate table dbo.dt_komap_phenotype_gold_standard;
truncate table dbo.dt_komap_phenotype_patient;
--truncate table dbo.DERIVED_FACT;
*/


