-- Count nonzero or populated cells in the SQL Server loyalty result tables.
--
-- Numeric columns count values other than zero. Text columns count nonnull,
-- nonblank values, and date columns count nonnull values. TOTAL ROWS is
-- included as the denominator for comparison.

SET NOCOUNT ON;

PRINT '=== DT_LOYALTY_RESULT nonzero/populated cell counts ===';

WITH counts AS (
    SELECT
        COUNT_BIG(*) AS total_rows,
        COUNT_BIG(CASE WHEN lookback_years <> 0 THEN 1 END) AS lookback_years,
        COUNT_BIG(CASE WHEN NULLIF(LTRIM(RTRIM(gender_denominators_yn)), '') IS NOT NULL THEN 1 END) AS gender_denominators_yn,
        COUNT_BIG(CASE WHEN NULLIF(LTRIM(RTRIM(site)), '') IS NOT NULL THEN 1 END) AS site,
        COUNT_BIG(CASE WHEN NULLIF(LTRIM(RTRIM(cohort_name)), '') IS NOT NULL THEN 1 END) AS cohort_name,
        COUNT_BIG(CASE WHEN patient_num <> 0 THEN 1 END) AS patient_num,
        COUNT_BIG(CASE WHEN death_dt IS NOT NULL THEN 1 END) AS death_dt,
        COUNT_BIG(CASE WHEN index_dt IS NOT NULL THEN 1 END) AS index_dt,
        COUNT_BIG(CASE WHEN NULLIF(LTRIM(RTRIM(sex)), '') IS NOT NULL THEN 1 END) AS sex,
        COUNT_BIG(CASE WHEN age <> 0 THEN 1 END) AS age,
        COUNT_BIG(CASE WHEN NULLIF(LTRIM(RTRIM(age_grp)), '') IS NOT NULL THEN 1 END) AS age_grp,
        COUNT_BIG(CASE WHEN num_dx1 <> 0 THEN 1 END) AS num_dx1,
        COUNT_BIG(CASE WHEN num_dx2 <> 0 THEN 1 END) AS num_dx2,
        COUNT_BIG(CASE WHEN med_use1 <> 0 THEN 1 END) AS med_use1,
        COUNT_BIG(CASE WHEN med_use2 <> 0 THEN 1 END) AS med_use2,
        COUNT_BIG(CASE WHEN mammography <> 0 THEN 1 END) AS mammography,
        COUNT_BIG(CASE WHEN pap_test <> 0 THEN 1 END) AS pap_test,
        COUNT_BIG(CASE WHEN psa_test <> 0 THEN 1 END) AS psa_test,
        COUNT_BIG(CASE WHEN colonoscopy <> 0 THEN 1 END) AS colonoscopy,
        COUNT_BIG(CASE WHEN fecal_occult_test <> 0 THEN 1 END) AS fecal_occult_test,
        COUNT_BIG(CASE WHEN flu_shot <> 0 THEN 1 END) AS flu_shot,
        COUNT_BIG(CASE WHEN pneumococcal_vaccine <> 0 THEN 1 END) AS pneumococcal_vaccine,
        COUNT_BIG(CASE WHEN bmi <> 0 THEN 1 END) AS bmi,
        COUNT_BIG(CASE WHEN a1c <> 0 THEN 1 END) AS a1c,
        COUNT_BIG(CASE WHEN medical_exam <> 0 THEN 1 END) AS medical_exam,
        COUNT_BIG(CASE WHEN inp1_opt1_visit <> 0 THEN 1 END) AS inp1_opt1_visit,
        COUNT_BIG(CASE WHEN opt2_visit <> 0 THEN 1 END) AS opt2_visit,
        COUNT_BIG(CASE WHEN ed_visit <> 0 THEN 1 END) AS ed_visit,
        COUNT_BIG(CASE WHEN mdvisit_pname2 <> 0 THEN 1 END) AS mdvisit_pname2,
        COUNT_BIG(CASE WHEN mdvisit_pname3 <> 0 THEN 1 END) AS mdvisit_pname3,
        COUNT_BIG(CASE WHEN routine_care_2 <> 0 THEN 1 END) AS routine_care_2,
        COUNT_BIG(CASE WHEN predicted_score <> 0 THEN 1 END) AS predicted_score
    FROM dbo.dt_loyalty_result
)
SELECT v.column_name, v.nonzero_or_populated_count
FROM counts c
CROSS APPLY (VALUES
    (N'TOTAL ROWS', c.total_rows),
    (N'LOOKBACK_YEARS', c.lookback_years),
    (N'GENDER_DENOMINATORS_YN', c.gender_denominators_yn),
    (N'SITE', c.site),
    (N'COHORT_NAME', c.cohort_name),
    (N'PATIENT_NUM', c.patient_num),
    (N'DEATH_DT', c.death_dt),
    (N'INDEX_DT', c.index_dt),
    (N'SEX', c.sex),
    (N'AGE', c.age),
    (N'AGE_GRP', c.age_grp),
    (N'NUM_DX1', c.num_dx1),
    (N'NUM_DX2', c.num_dx2),
    (N'MED_USE1', c.med_use1),
    (N'MED_USE2', c.med_use2),
    (N'MAMMOGRAPHY', c.mammography),
    (N'PAP_TEST', c.pap_test),
    (N'PSA_TEST', c.psa_test),
    (N'COLONOSCOPY', c.colonoscopy),
    (N'FECAL_OCCULT_TEST', c.fecal_occult_test),
    (N'FLU_SHOT', c.flu_shot),
    (N'PNEUMOCOCCAL_VACCINE', c.pneumococcal_vaccine),
    (N'BMI', c.bmi),
    (N'A1C', c.a1c),
    (N'MEDICAL_EXAM', c.medical_exam),
    (N'INP1_OPT1_VISIT', c.inp1_opt1_visit),
    (N'OPT2_VISIT', c.opt2_visit),
    (N'ED_VISIT', c.ed_visit),
    (N'MDVISIT_PNAME2', c.mdvisit_pname2),
    (N'MDVISIT_PNAME3', c.mdvisit_pname3),
    (N'ROUTINE_CARE_2', c.routine_care_2),
    (N'PREDICTED_SCORE', c.predicted_score)
) v(column_name, nonzero_or_populated_count)
ORDER BY v.column_name;

PRINT '=== DT_LOYALTY_RESULT_CHARLSON nonzero/populated cell counts ===';

WITH counts AS (
    SELECT
        COUNT_BIG(*) AS total_rows,
        COUNT_BIG(CASE WHEN lookback_years <> 0 THEN 1 END) AS lookback_years,
        COUNT_BIG(CASE WHEN NULLIF(LTRIM(RTRIM(gender_denominators_yn)), '') IS NOT NULL THEN 1 END) AS gender_denominators_yn,
        COUNT_BIG(CASE WHEN NULLIF(LTRIM(RTRIM(site)), '') IS NOT NULL THEN 1 END) AS site,
        COUNT_BIG(CASE WHEN NULLIF(LTRIM(RTRIM(cohort_name)), '') IS NOT NULL THEN 1 END) AS cohort_name,
        COUNT_BIG(CASE WHEN patient_num <> 0 THEN 1 END) AS patient_num,
        COUNT_BIG(CASE WHEN death_dt IS NOT NULL THEN 1 END) AS death_dt,
        COUNT_BIG(CASE WHEN last_visit IS NOT NULL THEN 1 END) AS last_visit,
        COUNT_BIG(CASE WHEN NULLIF(LTRIM(RTRIM(sex)), '') IS NOT NULL THEN 1 END) AS sex,
        COUNT_BIG(CASE WHEN age <> 0 THEN 1 END) AS age,
        COUNT_BIG(CASE WHEN NULLIF(LTRIM(RTRIM(age_grp)), '') IS NOT NULL THEN 1 END) AS age_grp,
        COUNT_BIG(CASE WHEN charlson_index <> 0 THEN 1 END) AS charlson_index,
        COUNT_BIG(CASE WHEN charlson_10yr_prob <> 0 THEN 1 END) AS charlson_10yr_prob,
        COUNT_BIG(CASE WHEN mi <> 0 THEN 1 END) AS mi,
        COUNT_BIG(CASE WHEN chf <> 0 THEN 1 END) AS chf,
        COUNT_BIG(CASE WHEN cvd <> 0 THEN 1 END) AS cvd,
        COUNT_BIG(CASE WHEN pvd <> 0 THEN 1 END) AS pvd,
        COUNT_BIG(CASE WHEN dementia <> 0 THEN 1 END) AS dementia,
        COUNT_BIG(CASE WHEN copd <> 0 THEN 1 END) AS copd,
        COUNT_BIG(CASE WHEN rheumdis <> 0 THEN 1 END) AS rheumdis,
        COUNT_BIG(CASE WHEN pepulcer <> 0 THEN 1 END) AS pepulcer,
        COUNT_BIG(CASE WHEN mildlivdis <> 0 THEN 1 END) AS mildlivdis,
        COUNT_BIG(CASE WHEN diabetes_nocc <> 0 THEN 1 END) AS diabetes_nocc,
        COUNT_BIG(CASE WHEN diabetes_wtcc <> 0 THEN 1 END) AS diabetes_wtcc,
        COUNT_BIG(CASE WHEN hemiparapleg <> 0 THEN 1 END) AS hemiparapleg,
        COUNT_BIG(CASE WHEN renaldis <> 0 THEN 1 END) AS renaldis,
        COUNT_BIG(CASE WHEN cancer <> 0 THEN 1 END) AS cancer,
        COUNT_BIG(CASE WHEN msvlivdis <> 0 THEN 1 END) AS msvlivdis,
        COUNT_BIG(CASE WHEN metastatic <> 0 THEN 1 END) AS metastatic,
        COUNT_BIG(CASE WHEN aidshiv <> 0 THEN 1 END) AS aidshiv
    FROM dbo.dt_loyalty_result_charlson
)
SELECT v.column_name, v.nonzero_or_populated_count
FROM counts c
CROSS APPLY (VALUES
    (N'TOTAL ROWS', c.total_rows),
    (N'LOOKBACK_YEARS', c.lookback_years),
    (N'GENDER_DENOMINATORS_YN', c.gender_denominators_yn),
    (N'SITE', c.site),
    (N'COHORT_NAME', c.cohort_name),
    (N'PATIENT_NUM', c.patient_num),
    (N'DEATH_DT', c.death_dt),
    (N'LAST_VISIT', c.last_visit),
    (N'SEX', c.sex),
    (N'AGE', c.age),
    (N'AGE_GRP', c.age_grp),
    (N'CHARLSON_INDEX', c.charlson_index),
    (N'CHARLSON_10YR_PROB', c.charlson_10yr_prob),
    (N'MI', c.mi),
    (N'CHF', c.chf),
    (N'CVD', c.cvd),
    (N'PVD', c.pvd),
    (N'DEMENTIA', c.dementia),
    (N'COPD', c.copd),
    (N'RHEUMDIS', c.rheumdis),
    (N'PEPULCER', c.pepulcer),
    (N'MILDLIVDIS', c.mildlivdis),
    (N'DIABETES_NOCC', c.diabetes_nocc),
    (N'DIABETES_WTCC', c.diabetes_wtcc),
    (N'HEMIPARAPLEG', c.hemiparapleg),
    (N'RENALDIS', c.renaldis),
    (N'CANCER', c.cancer),
    (N'MSVLIVDIS', c.msvlivdis),
    (N'METASTATIC', c.metastatic),
    (N'AIDSHIV', c.aidshiv)
) v(column_name, nonzero_or_populated_count)
ORDER BY v.column_name;
