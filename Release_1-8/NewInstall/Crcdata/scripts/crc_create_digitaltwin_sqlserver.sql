/*********************************************************
*           SQL SERVER SCRIPT TO CREATE DATA TABLES 
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



CREATE TABLE [DBO].[DT_LOYALTY_PATHS]( -- Was XREF_LOYALTYCODE_PATHS
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


CREATE TABLE [DBO].[DT_LOYALTY_CHARLSON]( -- Was XREF_LOYALTYCODE_CHARLSON
	[CHARLSON_CATGRY] [varchar](50) NULL,
	[CHARLSON_WT] INT NULL,
	[DIAGPATTERN] [varchar](50) NULL
) ON [PRIMARY];

CREATE TABLE [DBO].[DT_LOYALTY_PSCOEFF] ( -- Was XREF_LOYALTYCODE_PSCOEFF
  FIELD_NAME VARCHAR(50),
  COEFF NUMERIC(4,3)
);

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

