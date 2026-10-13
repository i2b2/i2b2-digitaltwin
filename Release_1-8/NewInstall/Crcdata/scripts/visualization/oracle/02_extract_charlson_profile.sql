-- Aggregate Oracle Charlson-condition extract for loyalty-burden-atlas.html.
-- Save the result grid as charlson_profile.csv with column headers.
-- No patient identifiers are returned. Groups smaller than MIN_CELL_SIZE
-- are omitted; use the disclosure threshold required by your institution.
--
-- Edit the constants in PARAMS. A typed NULL includes every value.

WITH PARAMS AS (
    SELECT
        CAST(NULL AS VARCHAR2(100)) AS SITE_FILTER,
        CAST(NULL AS VARCHAR2(100)) AS COHORT_FILTER,
        CAST(NULL AS NUMBER) AS LOOKBACK_FILTER,
        CAST(NULL AS CHAR(1)) AS GENDERED_FILTER,
        10 AS MIN_CELL_SIZE
    FROM DUAL
), MATCHED AS (
    SELECT
        R.SITE,
        R.COHORT_NAME,
        R.LOOKBACK_YEARS,
        R.GENDER_DENOMINATORS_YN,
        R.PATIENT_NUM,
        NVL(TRIM(R.AGE_GRP), 'Unknown') AS AGE_GRP,
        NVL(TRIM(R.SEX), 'Unknown') AS SEX,
        R.PREDICTED_SCORE,
        C.MI, C.CHF, C.CVD, C.PVD, C.DEMENTIA, C.COPD, C.RHEUMDIS,
        C.PEPULCER, C.MILDLIVDIS, C.DIABETES_NOCC, C.DIABETES_WTCC,
        C.HEMIPARAPLEG, C.RENALDIS, C.CANCER, C.MSVLIVDIS,
        C.METASTATIC, C.AIDSHIV
    FROM DT_LOYALTY_RESULT R
    JOIN DT_LOYALTY_RESULT_CHARLSON C
      ON C.SITE = R.SITE
     AND C.COHORT_NAME = R.COHORT_NAME
     AND C.PATIENT_NUM = R.PATIENT_NUM
     AND C.LOOKBACK_YEARS = R.LOOKBACK_YEARS
     AND C.GENDER_DENOMINATORS_YN = R.GENDER_DENOMINATORS_YN
    CROSS JOIN PARAMS P
    WHERE (P.SITE_FILTER IS NULL OR R.SITE = P.SITE_FILTER)
      AND (P.COHORT_FILTER IS NULL OR R.COHORT_NAME = P.COHORT_FILTER)
      AND (P.LOOKBACK_FILTER IS NULL OR R.LOOKBACK_YEARS = P.LOOKBACK_FILTER)
      AND (P.GENDERED_FILTER IS NULL OR R.GENDER_DENOMINATORS_YN = P.GENDERED_FILTER)
), TIERED AS (
    SELECT M.*,
        NTILE(3) OVER (
            PARTITION BY SITE, COHORT_NAME, LOOKBACK_YEARS, GENDER_DENOMINATORS_YN
            ORDER BY PREDICTED_SCORE, PATIENT_NUM
        ) AS LOYALTY_TIER_NUMBER
    FROM MATCHED M
), LONG_FORM AS (
    SELECT
        SITE, COHORT_NAME, LOOKBACK_YEARS, GENDER_DENOMINATORS_YN,
        AGE_GRP, SEX,
        CASE LOYALTY_TIER_NUMBER
            WHEN 1 THEN 'Lower'
            WHEN 2 THEN 'Middle'
            ELSE 'Upper'
        END AS LOYALTY_GROUP,
        CHARLSON_CATEGORY,
        CASE WHEN NVL(WEIGHT, 0) > 0 THEN 1 ELSE 0 END AS HAS_CONDITION
    FROM TIERED
    UNPIVOT INCLUDE NULLS (
        WEIGHT FOR CHARLSON_CATEGORY IN (
            MI AS 'Myocardial infarction',
            CHF AS 'Congestive heart failure',
            CVD AS 'Cerebrovascular disease',
            PVD AS 'Peripheral vascular disease',
            DEMENTIA AS 'Dementia',
            COPD AS 'Chronic pulmonary disease',
            RHEUMDIS AS 'Rheumatic disease',
            PEPULCER AS 'Peptic ulcer disease',
            MILDLIVDIS AS 'Mild liver disease',
            DIABETES_NOCC AS 'Diabetes without complications',
            DIABETES_WTCC AS 'Diabetes with complications',
            HEMIPARAPLEG AS 'Hemiplegia or paraplegia',
            RENALDIS AS 'Renal disease',
            CANCER AS 'Cancer',
            MSVLIVDIS AS 'Moderate or severe liver disease',
            METASTATIC AS 'Metastatic cancer',
            AIDSHIV AS 'AIDS/HIV'
        )
    )
), AGGREGATED AS (
    SELECT
        SITE, COHORT_NAME, LOOKBACK_YEARS, GENDER_DENOMINATORS_YN,
        AGE_GRP, SEX, LOYALTY_GROUP, CHARLSON_CATEGORY,
        COUNT(*) AS PATIENT_COUNT,
        SUM(HAS_CONDITION) AS CONDITION_COUNT,
        100.0 * SUM(HAS_CONDITION) / NULLIF(COUNT(*), 0) AS PREVALENCE_PERCENT
    FROM LONG_FORM
    GROUP BY SITE, COHORT_NAME, LOOKBACK_YEARS, GENDER_DENOMINATORS_YN,
        AGE_GRP, SEX, LOYALTY_GROUP, CHARLSON_CATEGORY
)
SELECT A.*
FROM AGGREGATED A
CROSS JOIN PARAMS P
WHERE A.PATIENT_COUNT >= P.MIN_CELL_SIZE
ORDER BY A.SITE, A.COHORT_NAME, A.LOOKBACK_YEARS,
    A.GENDER_DENOMINATORS_YN, A.AGE_GRP, A.SEX, A.CHARLSON_CATEGORY,
    CASE A.LOYALTY_GROUP
        WHEN 'Lower' THEN 1
        WHEN 'Middle' THEN 2
        ELSE 3
    END;
