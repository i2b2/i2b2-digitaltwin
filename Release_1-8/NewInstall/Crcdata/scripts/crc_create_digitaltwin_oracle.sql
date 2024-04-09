/*********************************************************
*           ORACLE SCRIPT TO CREATE DATA TABLES 
*            FOR "DIGITAL TWIN" DERIVED FACT TOOLS
*               Last updated 02/2024
**********************************************************/

/*********************************************************
*           LOYALTY COHORT - See this publication:
* Klann JG, Henderson DW, Morris M, et al. A broadly applicable approach to enrich 
* electronic-health-record cohorts by identifying patients with complete data: a 
* multisite evaluation. J Am Med Inform Assoc Published Online First: 25 August 2023. 
* doi:10.1093/jamia/ocad166
**********************************************************/

 CREATE TABLE DT_LOYALTY_PATHS -- was LOYALTY_XREF_CODE_PATHS
   (	"FEATURE_NAME" VARCHAR2(26 BYTE), 
	"CODE_TYPE" VARCHAR2(26 BYTE), 
	"CONCEPT_PATH" VARCHAR2(256 BYTE), 
	"SITESPECIFICCODE" VARCHAR2(26 BYTE), 
	"PATH_COMMENT" VARCHAR2(200 BYTE)
   ) ;

CREATE TABLE LOYALTY_XREF_CHARLSON
   (	"CHARLSON_CATGRY" VARCHAR2(50 BYTE), 
	"CHARLSON_WT" NUMBER(5,0), 
	"CONCEPT_CD" VARCHAR2(50 BYTE)
   );

 CREATE TABLE DT_LOYALTY_PSCOEFF -- was LOYALTY_XREF_CODE_PSCOEFF
   (	"FIELD_NAME" VARCHAR2(50 BYTE), 
	"COEFF" NUMBER(4,3)
   );

-- Externally validated coefficients
--ASSIGN COEFFICIENTS FOR EACH FEATURE USED TO COMPUTE THE LOYALTY SCORE
Insert into DT_LOYALTY_PSCOEFF (FIELD_NAME,COEFF) values ('MDVisit_pname2',0.049);
Insert into DT_LOYALTY_PSCOEFF (FIELD_NAME,COEFF) values ('MDVisit_pname3',0.087);
Insert into DT_LOYALTY_PSCOEFF (FIELD_NAME,COEFF) values ('PapTest',0.009);
Insert into DT_LOYALTY_PSCOEFF (FIELD_NAME,COEFF) values ('PSATest',0.103);
Insert into DT_LOYALTY_PSCOEFF (FIELD_NAME,COEFF) values ('Colonoscopy',0.064);
Insert into DT_LOYALTY_PSCOEFF (FIELD_NAME,COEFF) values ('FecalOccultTest',0.034);
Insert into DT_LOYALTY_PSCOEFF (FIELD_NAME,COEFF) values ('FluShot',0.102);
Insert into DT_LOYALTY_PSCOEFF (FIELD_NAME,COEFF) values ('PneumococcalVaccine',0.031);
Insert into DT_LOYALTY_PSCOEFF (FIELD_NAME,COEFF) values ('BMI',0.017);
Insert into DT_LOYALTY_PSCOEFF (FIELD_NAME,COEFF) values ('A1C',0.018);
Insert into DT_LOYALTY_PSCOEFF (FIELD_NAME,COEFF) values ('MedUse1',0.002);
Insert into DT_LOYALTY_PSCOEFF (FIELD_NAME,COEFF) values ('MedUse2',0.074);
Insert into DT_LOYALTY_PSCOEFF (FIELD_NAME,COEFF) values ('INP1_OPT1_Visit',0.091);
Insert into DT_LOYALTY_PSCOEFF (FIELD_NAME,COEFF) values ('OPT2_Visit',0.05);
Insert into DT_LOYALTY_PSCOEFF (FIELD_NAME,COEFF) values ('Num_DX1',-0.026);
Insert into DT_LOYALTY_PSCOEFF (FIELD_NAME,COEFF) values ('Num_DX2',0.037);
Insert into DT_LOYALTY_PSCOEFF (FIELD_NAME,COEFF) values ('ED_Visit',0.078);
Insert into DT_LOYALTY_PSCOEFF (FIELD_NAME,COEFF) values ('MedicalExam',0.078);
Insert into DT_LOYALTY_PSCOEFF (FIELD_NAME,COEFF) values ('Mammography',0.075);
Insert into DT_LOYALTY_PSCOEFF (FIELD_NAME,COEFF) values ('Routine_Care_2',0.049);
Insert into DT_LOYALTY_PSCOEFF (FIELD_NAME,COEFF) values ('Demographics',0);
COMMIT;

--##############################################################################
--##############################################################################
--### KESER - Create Tables
--### Date: September 1, 2023
--### Database: Oracle
--### Created By: Griffin Weber (weber@hms.harvard.edu)
--##############################################################################
--##############################################################################


--------------------------------------------------------------------------------
-- Drop existing tables.
--------------------------------------------------------------------------------

-- BEGIN EXECUTE IMMEDIATE 'DROP TABLE dt_keser_import_concept_feature'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
-- BEGIN EXECUTE IMMEDIATE 'DROP TABLE dt_keser_feature'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
-- BEGIN EXECUTE IMMEDIATE 'DROP TABLE dt_keser_concept_feature'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
-- BEGIN EXECUTE IMMEDIATE 'DROP TABLE dt_keser_concept_children'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
-- BEGIN EXECUTE IMMEDIATE 'DROP TABLE dt_keser_patient_partition'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
-- BEGIN EXECUTE IMMEDIATE 'DROP TABLE dt_keser_patient_period_feature'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
-- BEGIN EXECUTE IMMEDIATE 'DROP TABLE dt_keser_feature_count'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
-- BEGIN EXECUTE IMMEDIATE 'DROP TABLE dt_keser_feature_cooccur_temp'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
-- BEGIN EXECUTE IMMEDIATE 'DROP TABLE dt_keser_feature_cooccur'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
-- BEGIN EXECUTE IMMEDIATE 'DROP TABLE dt_keser_embedding'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
-- BEGIN EXECUTE IMMEDIATE 'DROP TABLE dt_keser_phenotype'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
-- BEGIN EXECUTE IMMEDIATE 'DROP TABLE dt_keser_phenotype_feature'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;

--------------------------------------------------------------------------------
-- Create tables for mapping features to local concepts.
--------------------------------------------------------------------------------

create table dt_keser_import_concept_feature (
	concept_cd varchar(50) not null,
	feature_cd varchar(50) not null,
	feature_name varchar(250) not null
);

create table dt_keser_feature (
	feature_num int not null,
	feature_cd varchar(50) not null,
	feature_name varchar(250) not null,
	primary key (feature_num)
);
create index idx_feature_cd on dt_keser_feature(feature_cd);

create table dt_keser_concept_feature (
	concept_cd varchar(50) not null,
	feature_num int not null,
	primary key (concept_cd, feature_num)
);
create unique index idx_feature_concept on dt_keser_concept_feature(feature_num, concept_cd);

create table dt_keser_concept_children (
	concept_cd varchar(50) not null,
	child_cd varchar(50) not null,
	primary key (concept_cd, child_cd)
);

--------------------------------------------------------------------------------
-- Create tables for patient data.
--------------------------------------------------------------------------------

create table dt_keser_patient_partition (
	patient_num int not null,
	patient_partition number(3,0) not null,
	primary key (patient_num)
);

create table dt_keser_patient_period_feature (
	patient_partition number(3,0) not null,
	patient_num int not null,
	time_period int not null,
	feature_num int not null,
	min_offset smallint not null,
	max_offset smallint not null,
	feature_dates smallint,
	concept_dates int,
	primary key (patient_partition, patient_num, time_period, feature_num)
);

create table dt_keser_feature_count (
	cohort number(3,0) not null,
	feature_num int not null,
	feature_cd varchar(50) not null,
	feature_name varchar(250) not null,
	feature_count int not null,
	primary key (cohort, feature_num)
);

create table dt_keser_feature_cooccur_temp (
	cohort number(3,0) not null,
	feature_num1 int not null,
	feature_num2 int not null,
	num_patients int not null
);

create table dt_keser_feature_cooccur (
	cohort number(3,0) not null,
	feature_num1 int not null,
	feature_num2 int not null,
	coocur_count int not null,
	primary key (cohort, feature_num1, feature_num2)
);

--------------------------------------------------------------------------------
-- Create table to store embeddings.
--------------------------------------------------------------------------------

create table dt_keser_embedding (
	cohort number(3,0) not null,
	feature_cd varchar(50) not null,
	dim int not null,
	val float not null,
	primary key (cohort, feature_cd, dim)
);

--------------------------------------------------------------------------------
-- Create tables for embedding regression (map phenotypes to features).
--------------------------------------------------------------------------------

create table dt_keser_phenotype (
	phenotype varchar(50) not null,
	primary key (phenotype)
);

create table dt_keser_phenotype_feature (
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

-- truncate table dt_keser_import_concept_feature;
-- truncate table dt_keser_feature;
-- truncate table dt_keser_concept_feature;
-- truncate table dt_keser_concept_children;
-- truncate table dt_keser_patient_partition;
-- truncate table dt_keser_patient_period_feature;
-- truncate table dt_keser_feature_count;
-- truncate table dt_keser_feature_cooccur_temp;
-- truncate table dt_keser_feature_cooccur;
-- truncate table dt_keser_embedding;
-- truncate table dt_keser_phenotype;
-- truncate table dt_keser_phenotype_feature;


--##############################################################################
--##############################################################################
--### KOMAP - Create Tables
--### Date: September 1, 2023
--### Database: Oracle
--### Created By: Griffin Weber (weber@hms.harvard.edu)
--##############################################################################
--##############################################################################


--------------------------------------------------------------------------------
-- Drop existing tables.
--------------------------------------------------------------------------------

BEGIN EXECUTE IMMEDIATE 'DROP TABLE dt_komap_phenotype'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
BEGIN EXECUTE IMMEDIATE 'DROP TABLE dt_komap_phenotype_feature_dict'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
BEGIN EXECUTE IMMEDIATE 'DROP TABLE dt_komap_patient_feature'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
BEGIN EXECUTE IMMEDIATE 'DROP TABLE dt_komap_base_cohort'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
BEGIN EXECUTE IMMEDIATE 'DROP TABLE dt_komap_phenotype_sample'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
BEGIN EXECUTE IMMEDIATE 'DROP TABLE dt_komap_phenotype_sample_feature'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
BEGIN EXECUTE IMMEDIATE 'DROP TABLE dt_komap_phenotype_covar_inner'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
BEGIN EXECUTE IMMEDIATE 'DROP TABLE dt_komap_phenotype_covar'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
BEGIN EXECUTE IMMEDIATE 'DROP TABLE dt_komap_phenotype_feature_coef'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
BEGIN EXECUTE IMMEDIATE 'DROP TABLE dt_komap_phenotype_sample_results'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
BEGIN EXECUTE IMMEDIATE 'DROP TABLE dt_komap_phenotype_gmm'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
BEGIN EXECUTE IMMEDIATE 'DROP TABLE dt_komap_phenotype_gold_standard'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
BEGIN EXECUTE IMMEDIATE 'DROP TABLE dt_komap_phenotype_patient'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
BEGIN EXECUTE IMMEDIATE 'DROP TABLE DERIVED_FACT'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;


--------------------------------------------------------------------------------
-- Create new tables to list the phenotypes and their features.
--------------------------------------------------------------------------------

create table dt_komap_phenotype (
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

create table dt_komap_phenotype_feature_dict (
	phenotype varchar(50) not null,
	feature_cd varchar(50) not null,
	feature_name varchar(250),
	primary key (phenotype, feature_cd)
);

--------------------------------------------------------------------------------
-- Create new tables to generate the input data for KOMAP.
--------------------------------------------------------------------------------

create table dt_komap_patient_feature (
	patient_num int not null,
	feature_cd varchar(50) not null,
	num_dates int not null,
	log_dates float not null,
	primary key (feature_cd, patient_num)
);

create table dt_komap_base_cohort (
	patient_num int not null,
	primary key (patient_num)
);

create table dt_komap_phenotype_sample (
	phenotype varchar(50) not null,
	patient_num int not null,
	primary key (phenotype, patient_num)
);

create table dt_komap_phenotype_sample_feature (
	phenotype varchar(50) not null,
	patient_num int not null,
	feature_cd varchar(50) not null,
	num_dates int not null,
	log_dates float not null,
	primary key (phenotype, feature_cd, patient_num)
);

create table dt_komap_phenotype_covar_inner (
	phenotype varchar(50) not null,
	feature_cd1 varchar(50) not null,
	feature_cd2 varchar(50) not null,
	num_patients int,
	sum_log_dates float,
	primary key (phenotype, feature_cd1, feature_cd2)
);

create table dt_komap_phenotype_covar (
	phenotype varchar(50) not null,
	feature_cd1 varchar(50) not null,
	feature_cd2 varchar(50) not null,
	covar float,
	primary key (phenotype, feature_cd1, feature_cd2)
);

create table dt_komap_phenotype_feature_coef (
	phenotype varchar(50) not null,
	feature_cd varchar(50) not null,
	coef float not null,
	primary key (phenotype, feature_cd)
);

--------------------------------------------------------------------------------
-- Create new tables to store and process the results of KOMAP.
--------------------------------------------------------------------------------

create table dt_komap_phenotype_sample_results (
	phenotype varchar(50) not null,
	patient_num int not null,
	score float,
	phecode_dates int,
	utilization_dates int,
	phecode_score float,
	utilization_score float,
	other_positive_feature_score float,
	other_negative_feature_score float,
	primary key (phenotype, patient_num)
);

create table dt_komap_phenotype_gmm (
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

create table dt_komap_phenotype_gold_standard (
	phenotype varchar(50) not null,
	patient_num int not null,
	has_phenotype int,
	score float null,
	primary key (phenotype, patient_num)
);

create table dt_komap_phenotype_patient (
	phenotype varchar(50) not null,
	patient_num int not null,
	score float,
	primary key (phenotype, patient_num)
);

--------------------------------------------------------------------------------
-- Create a DERIVED_FACT table if one does not alreay exist.
--------------------------------------------------------------------------------


create table DERIVED_FACT(
	ENCOUNTER_NUM int NOT NULL,
	PATIENT_NUM int NOT NULL,
	CONCEPT_CD varchar(50) NOT NULL,
	PROVIDER_ID varchar(50) NOT NULL,
	START_DATE date NOT NULL,
	MODIFIER_CD varchar(100) NOT NULL,
	INSTANCE_NUM int NOT NULL,
	VALTYPE_CD varchar(50),
	TVAL_CHAR varchar(255),
	NVAL_NUM number(18,5),
	VALUEFLAG_CD varchar(50),
	QUANTITY_NUM number(18,5),
	UNITS_CD varchar(50),
	END_DATE date NULL,
	LOCATION_CD varchar(50),
	OBSERVATION_BLOB clob NULL,
	CONFIDENCE_NUM number(18,5),
	UPDATE_DATE date NULL,
	DOWNLOAD_DATE date NULL,
	IMPORT_DATE date NULL,
	SOURCESYSTEM_CD varchar(50),
	UPLOAD_ID int
);
alter table DERIVED_FACT add primary key (CONCEPT_CD,PATIENT_NUM,ENCOUNTER_NUM,START_DATE,PROVIDER_ID,INSTANCE_NUM,MODIFIER_CD);
create index DF_IDX_CONCEPT_DATE_PATIENT on DERIVED_FACT  (CONCEPT_CD, START_DATE, PATIENT_NUM);
create index DF_IDX_ENCOUNTER_PATIENT_CONCEPT_DATE on DERIVED_FACT  (ENCOUNTER_NUM, PATIENT_NUM, CONCEPT_CD, START_DATE);
create index DF_IDX_PATIENT_CONCEPT_DATE on DERIVED_FACT  (PATIENT_NUM, CONCEPT_CD, START_DATE);



--------------------------------------------------------------------------------
-- Truncate tables.
--------------------------------------------------------------------------------

-- truncate table dt_komap_phenotype;
-- truncate table dt_komap_phenotype_feature_dict;
-- truncate table dt_komap_patient_feature;
-- truncate table dt_komap_base_cohort;
-- truncate table dt_komap_phenotype_sample;
-- truncate table dt_komap_phenotype_sample_feature;
-- truncate table dt_komap_phenotype_covar_inner;
-- truncate table dt_komap_phenotype_covar;
-- truncate table dt_komap_phenotype_feature_coef;
-- truncate table dt_komap_phenotype_sample_results;
-- truncate table dt_komap_phenotype_gmm;
-- truncate table dt_komap_phenotype_gold_standard;
-- truncate table dt_komap_phenotype_patient;
-- truncate table DERIVED_FACT;
