-- ********************************************************
-- * SQL Server preparation for running the loyalty cohort
-- * against an ACT-OMOP database.
-- *
-- * This script is intentionally named with a numeric prefix so the Ant
-- * procedure installer runs it before usp_dt_loyaltycohort.sql.
-- ********************************************************

SET NOCOUNT ON

-- Never replace a site's real i2b2 fact table.  On a conventional i2b2
-- installation no compatibility view is needed.
IF OBJECT_ID(N'dbo.OBSERVATION_FACT', N'U') IS NOT NULL
BEGIN
  PRINT N'dbo.OBSERVATION_FACT is a table; skipping the ACT-OMOP compatibility view.'
  RETURN
END

-- Refuse to replace an unexpected object such as a synonym or procedure.
IF OBJECT_ID(N'dbo.OBSERVATION_FACT') IS NOT NULL
   AND OBJECT_ID(N'dbo.OBSERVATION_FACT', N'V') IS NULL
BEGIN
  RAISERROR(N'dbo.OBSERVATION_FACT exists but is not a table or view. The ACT-OMOP compatibility view was not created.', 16, 1)
  RETURN
END

DECLARE @missing_views varchar(max) = ''

SELECT @missing_views = CONCAT_WS(', ', NULLIF(@missing_views, ''), required_view)
FROM (VALUES
  ('CONDITION_VIEW'),
  ('CONDITION_NS_VIEW'),
  ('DRUG_VIEW'),
  ('DRUG_NS_VIEW'),
  ('DEVICE_VIEW'),
  ('DEVICE_NS_VIEW'),
  ('MEASUREMENT_VIEW'),
  ('MEASUREMENT_NS_VIEW'),
  ('OBSERVATION_VIEW'),
  ('OBSERVATION_NS_VIEW'),
  ('PROCEDURE_VIEW'),
  ('PROCEDURE_NS_VIEW')
) required(required_view)
WHERE OBJECT_ID(N'dbo.' + required_view, N'V') IS NULL
  AND OBJECT_ID(N'dbo.' + required_view, N'SN') IS NULL

IF NULLIF(@missing_views, '') IS NOT NULL
BEGIN
  DECLARE @missing_message nvarchar(2048) =
    N'Cannot create dbo.OBSERVATION_FACT. Build or link the ACT-OMOP SQL Server views first. Missing views or synonyms: '
    + @missing_views
  RAISERROR(N'%s', 16, 1, @missing_message)
  RETURN
END

IF OBJECT_ID(N'dbo.OBSERVATION_FACT', N'V') IS NOT NULL
  EXEC(N'DROP VIEW [dbo].[OBSERVATION_FACT]')

-- The loyalty procedure reads only PATIENT_NUM, CONCEPT_CD, and START_DATE.
-- Explicit casts keep the UNION stable when OMOP implementations use slightly
-- different numeric or date types.  Both standard and source concepts are
-- included intentionally; duplicate rows do not change the loyalty flags and
-- date-threshold features calculated by the procedure.
--
-- Each source object may be either a local view or a synonym pointing to a view
-- in another schema or database. VISIT_NS_VIEW is deliberately excluded.
-- Visit-based loyalty variables use
-- VISIT_DIMENSION and the ACT_VISIT ontology rather than fact rows.
DECLARE @create_observation_fact nvarchar(max) = N'
CREATE VIEW [dbo].[OBSERVATION_FACT] ([PATIENT_NUM], [CONCEPT_CD], [START_DATE]) AS
  SELECT CONVERT(int, [PATIENT_NUM]), CONVERT(varchar(50), [CONCEPT_CD]), CONVERT(datetime2, [START_DATE]) FROM [dbo].[CONDITION_VIEW]
  UNION ALL
  SELECT CONVERT(int, [PATIENT_NUM]), CONVERT(varchar(50), [CONCEPT_CD]), CONVERT(datetime2, [START_DATE]) FROM [dbo].[CONDITION_NS_VIEW]
  UNION ALL
  SELECT CONVERT(int, [PATIENT_NUM]), CONVERT(varchar(50), [CONCEPT_CD]), CONVERT(datetime2, [START_DATE]) FROM [dbo].[DRUG_VIEW]
  UNION ALL
  SELECT CONVERT(int, [PATIENT_NUM]), CONVERT(varchar(50), [CONCEPT_CD]), CONVERT(datetime2, [START_DATE]) FROM [dbo].[DRUG_NS_VIEW]
  UNION ALL
  SELECT CONVERT(int, [PATIENT_NUM]), CONVERT(varchar(50), [CONCEPT_CD]), CONVERT(datetime2, [START_DATE]) FROM [dbo].[DEVICE_VIEW]
  UNION ALL
  SELECT CONVERT(int, [PATIENT_NUM]), CONVERT(varchar(50), [CONCEPT_CD]), CONVERT(datetime2, [START_DATE]) FROM [dbo].[DEVICE_NS_VIEW]
  UNION ALL
  SELECT CONVERT(int, [PATIENT_NUM]), CONVERT(varchar(50), [CONCEPT_CD]), CONVERT(datetime2, [START_DATE]) FROM [dbo].[MEASUREMENT_VIEW]
  UNION ALL
  SELECT CONVERT(int, [PATIENT_NUM]), CONVERT(varchar(50), [CONCEPT_CD]), CONVERT(datetime2, [START_DATE]) FROM [dbo].[MEASUREMENT_NS_VIEW]
  UNION ALL
  SELECT CONVERT(int, [PATIENT_NUM]), CONVERT(varchar(50), [CONCEPT_CD]), CONVERT(datetime2, [START_DATE]) FROM [dbo].[OBSERVATION_VIEW]
  UNION ALL
  SELECT CONVERT(int, [PATIENT_NUM]), CONVERT(varchar(50), [CONCEPT_CD]), CONVERT(datetime2, [START_DATE]) FROM [dbo].[OBSERVATION_NS_VIEW]
  UNION ALL
  SELECT CONVERT(int, [PATIENT_NUM]), CONVERT(varchar(50), [CONCEPT_CD]), CONVERT(datetime2, [START_DATE]) FROM [dbo].[PROCEDURE_VIEW]
  UNION ALL
  SELECT CONVERT(int, [PATIENT_NUM]), CONVERT(varchar(50), [CONCEPT_CD]), CONVERT(datetime2, [START_DATE]) FROM [dbo].[PROCEDURE_NS_VIEW]'

BEGIN TRY
  EXEC sys.sp_executesql @create_observation_fact
END TRY
BEGIN CATCH
  DECLARE @view_error nvarchar(2048) =
    N'Could not create dbo.OBSERVATION_FACT: ' + ERROR_MESSAGE()
  RAISERROR(N'%s', 16, 1, @view_error)
  RETURN
END CATCH

PRINT N'Created dbo.OBSERVATION_FACT compatibility view for the loyalty cohort.'

-- NOTICE: The current ACT-OMOP PATIENT_DIMENSION view returns NULL DEATH_DATE.
-- Loyalty output DEATH_DT will therefore remain NULL even when the OMOP DEATH
-- table contains a record. This prep intentionally leaves the shared ACT-OMOP
-- implementation unchanged; death mapping should be addressed separately.
