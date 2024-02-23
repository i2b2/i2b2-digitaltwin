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
