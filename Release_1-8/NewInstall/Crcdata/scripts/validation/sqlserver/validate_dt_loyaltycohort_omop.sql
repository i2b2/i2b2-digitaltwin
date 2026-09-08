-- Read-only preflight checks for SQL Server ACT-OMOP loyalty cohort support.
-- Run after the ACT-OMOP views, digital-twin tables/reference data, and
-- 00_dt_loyaltycohort_prep_omop.sql have been installed.

SET NOCOUNT ON

SELECT prerequisite, object_name, expected_type,
  CASE
    WHEN expected_type = 'VIEW' AND OBJECT_ID(object_name, 'V') IS NOT NULL THEN 'OK'
    WHEN expected_type = 'TABLE' AND OBJECT_ID(object_name, 'U') IS NOT NULL THEN 'OK'
    WHEN expected_type = 'TABLE OR VIEW' AND OBJECT_ID(object_name, 'U') IS NOT NULL THEN 'OK'
    WHEN expected_type = 'TABLE OR VIEW' AND OBJECT_ID(object_name, 'V') IS NOT NULL THEN 'OK'
    WHEN expected_type = 'TABLE, VIEW, OR SYNONYM' AND OBJECT_ID(object_name, 'U') IS NOT NULL THEN 'OK'
    WHEN expected_type = 'TABLE, VIEW, OR SYNONYM' AND OBJECT_ID(object_name, 'V') IS NOT NULL THEN 'OK'
    WHEN expected_type = 'TABLE, VIEW, OR SYNONYM' AND OBJECT_ID(object_name, 'SN') IS NOT NULL THEN 'OK'
    ELSE 'MISSING'
  END status
FROM (VALUES
  ('OMOP fact compatibility', 'dbo.OBSERVATION_FACT', 'VIEW'),
  ('OMOP patient compatibility', 'dbo.PATIENT_DIMENSION', 'VIEW'),
  ('OMOP visit compatibility', 'dbo.VISIT_DIMENSION', 'VIEW'),
  ('OMOP vocabulary', 'dbo.CONCEPT', 'TABLE, VIEW, OR SYNONYM'),
  ('Ontology registry', 'dbo.TABLE_ACCESS', 'TABLE, VIEW, OR SYNONYM'),
  ('Loyalty paths', 'dbo.DT_LOYALTY_PATHS', 'TABLE'),
  ('Loyalty coefficients', 'dbo.DT_LOYALTY_PSCOEFF', 'TABLE'),
  ('Charlson mappings', 'dbo.DT_LOYALTY_CHARLSON', 'TABLE')
) requirements(prerequisite, object_name, expected_type)
ORDER BY prerequisite

SELECT
  COUNT_BIG(*) fact_rows,
  COUNT_BIG(DISTINCT PATIENT_NUM) patients,
  SUM(CASE WHEN PATIENT_NUM IS NULL THEN 1 ELSE 0 END) null_patient_num,
  SUM(CASE WHEN NULLIF(CONCEPT_CD, '') IS NULL THEN 1 ELSE 0 END) null_concept_cd,
  SUM(CASE WHEN START_DATE IS NULL THEN 1 ELSE 0 END) null_start_date,
  MIN(START_DATE) earliest_start_date,
  MAX(START_DATE) latest_start_date
FROM dbo.OBSERVATION_FACT

SELECT
  COUNT_BIG(*) patients,
  SUM(CASE WHEN TRY_CONVERT(date, BIRTH_DATE) IS NULL THEN 1 ELSE 0 END) missing_or_invalid_birth_date,
  SUM(CASE WHEN LTRIM(RTRIM(CONVERT(varchar(50), SEX_CD))) IN ('F', 'DEM|SEX:F', '8532') THEN 1 ELSE 0 END) recognized_female,
  SUM(CASE WHEN LTRIM(RTRIM(CONVERT(varchar(50), SEX_CD))) IN ('M', 'DEM|SEX:M', '8507') THEN 1 ELSE 0 END) recognized_male,
  SUM(CASE WHEN DEATH_DATE IS NOT NULL THEN 1 ELSE 0 END) nonnull_death_date
FROM dbo.PATIENT_DIMENSION

-- Each returned row is a configured path with no matching active ontology row.
-- Dynamic SQL is emitted because ACT-OMOP stores concepts in multiple tables.
DROP TABLE IF EXISTS #DT_LOYALTY_PATH_MATCH
CREATE TABLE #DT_LOYALTY_PATH_MATCH (CONCEPT_PATH varchar(500) PRIMARY KEY)

DECLARE @table_name varchar(400), @object_name nvarchar(1035), @sql nvarchar(max)
DECLARE ontology_cursor CURSOR LOCAL FAST_FORWARD FOR
  SELECT DISTINCT C_TABLE_NAME FROM dbo.TABLE_ACCESS
  WHERE NULLIF(C_TABLE_NAME, '') IS NOT NULL AND C_VISUALATTRIBUTES LIKE '%A%'

OPEN ontology_cursor
FETCH NEXT FROM ontology_cursor INTO @table_name
WHILE @@FETCH_STATUS = 0
BEGIN
  SET @object_name = CASE
    WHEN PARSENAME(@table_name, 4) IS NOT NULL THEN QUOTENAME(PARSENAME(@table_name, 4)) + '.' + QUOTENAME(PARSENAME(@table_name, 3)) + '.' + QUOTENAME(PARSENAME(@table_name, 2)) + '.' + QUOTENAME(PARSENAME(@table_name, 1))
    WHEN PARSENAME(@table_name, 3) IS NOT NULL THEN QUOTENAME(PARSENAME(@table_name, 3)) + '.' + QUOTENAME(PARSENAME(@table_name, 2)) + '.' + QUOTENAME(PARSENAME(@table_name, 1))
    WHEN PARSENAME(@table_name, 2) IS NOT NULL THEN QUOTENAME(PARSENAME(@table_name, 2)) + '.' + QUOTENAME(PARSENAME(@table_name, 1))
    ELSE 'dbo.' + QUOTENAME(PARSENAME(@table_name, 1)) END

  SET @sql = N'INSERT INTO #DT_LOYALTY_PATH_MATCH (CONCEPT_PATH)
    SELECT DISTINCT L.CONCEPT_PATH
    FROM dbo.DT_LOYALTY_PATHS L
    WHERE L.CONCEPT_PATH IS NOT NULL AND L.CONCEPT_PATH <> ''**Not Found''
      AND EXISTS (SELECT 1 FROM ' + @object_name + N' O WHERE O.C_FULLNAME LIKE L.CONCEPT_PATH + ''%'')
      AND NOT EXISTS (SELECT 1 FROM #DT_LOYALTY_PATH_MATCH M WHERE M.CONCEPT_PATH = L.CONCEPT_PATH)'
  EXEC sys.sp_executesql @sql
  FETCH NEXT FROM ontology_cursor INTO @table_name
END
CLOSE ontology_cursor
DEALLOCATE ontology_cursor

SELECT L.FEATURE_NAME, L.CODE_TYPE, L.CONCEPT_PATH, L.SITE_SPECIFIC_CODE
FROM dbo.DT_LOYALTY_PATHS L
WHERE L.CONCEPT_PATH IS NOT NULL
  AND L.CONCEPT_PATH <> '**Not Found'
  AND NOT EXISTS (SELECT 1 FROM #DT_LOYALTY_PATH_MATCH M WHERE M.CONCEPT_PATH = L.CONCEPT_PATH)
ORDER BY L.FEATURE_NAME, L.CONCEPT_PATH

-- These should all be nonzero before relying on the corresponding results.
SELECT 'visit path matches' check_name, COUNT_BIG(*) match_count
FROM #DT_LOYALTY_PATH_MATCH M
JOIN dbo.DT_LOYALTY_PATHS L ON L.CONCEPT_PATH = M.CONCEPT_PATH
WHERE L.CODE_TYPE = 'VISIT'
UNION ALL
SELECT 'fact feature path matches', COUNT_BIG(*)
FROM #DT_LOYALTY_PATH_MATCH M
JOIN dbo.DT_LOYALTY_PATHS L ON L.CONCEPT_PATH = M.CONCEPT_PATH
WHERE L.CODE_TYPE IN ('DX', 'PX', 'LAB', 'MEDS', 'SITE')

-- NOTICE: ACT-OMOP currently exposes NULL DEATH_DATE in PATIENT_DIMENSION.
-- A zero nonnull_death_date count is expected until death mapping is added.
