-- Count nonzero or populated cells in the Oracle loyalty result tables.
--
-- Numeric columns count values other than zero. Text and date columns count
-- nonnull values. TOTAL ROWS is included as the denominator for comparison.

--- === DT_LOYALTY_RESULT nonzero/populated cell counts ===

WITH counts AS (
    SELECT
        COUNT(*) AS total_rows,
        COUNT(CASE WHEN lookback_years <> 0 THEN 1 END) AS lookback_years,
        COUNT(CASE WHEN gender_denominators_yn IS NOT NULL THEN 1 END) AS gender_denominators_yn,
        COUNT(CASE WHEN site IS NOT NULL THEN 1 END) AS site,
        COUNT(CASE WHEN cohort_name IS NOT NULL THEN 1 END) AS cohort_name,
        COUNT(CASE WHEN patient_num <> 0 THEN 1 END) AS patient_num,
        COUNT(CASE WHEN death_dt IS NOT NULL THEN 1 END) AS death_dt,
        COUNT(CASE WHEN index_dt IS NOT NULL THEN 1 END) AS index_dt,
        COUNT(CASE WHEN sex IS NOT NULL THEN 1 END) AS sex,
        COUNT(CASE WHEN age <> 0 THEN 1 END) AS age,
        COUNT(CASE WHEN age_grp IS NOT NULL THEN 1 END) AS age_grp,
        COUNT(CASE WHEN num_dx1 <> 0 THEN 1 END) AS num_dx1,
        COUNT(CASE WHEN num_dx2 <> 0 THEN 1 END) AS num_dx2,
        COUNT(CASE WHEN med_use1 <> 0 THEN 1 END) AS med_use1,
        COUNT(CASE WHEN med_use2 <> 0 THEN 1 END) AS med_use2,
        COUNT(CASE WHEN mammography <> 0 THEN 1 END) AS mammography,
        COUNT(CASE WHEN pap_test <> 0 THEN 1 END) AS pap_test,
        COUNT(CASE WHEN psa_test <> 0 THEN 1 END) AS psa_test,
        COUNT(CASE WHEN colonoscopy <> 0 THEN 1 END) AS colonoscopy,
        COUNT(CASE WHEN fecal_occult_test <> 0 THEN 1 END) AS fecal_occult_test,
        COUNT(CASE WHEN flu_shot <> 0 THEN 1 END) AS flu_shot,
        COUNT(CASE WHEN pneumococcal_vaccine <> 0 THEN 1 END) AS pneumococcal_vaccine,
        COUNT(CASE WHEN bmi <> 0 THEN 1 END) AS bmi,
        COUNT(CASE WHEN a1c <> 0 THEN 1 END) AS a1c,
        COUNT(CASE WHEN medical_exam <> 0 THEN 1 END) AS medical_exam,
        COUNT(CASE WHEN inp1_opt1_visit <> 0 THEN 1 END) AS inp1_opt1_visit,
        COUNT(CASE WHEN opt2_visit <> 0 THEN 1 END) AS opt2_visit,
        COUNT(CASE WHEN ed_visit <> 0 THEN 1 END) AS ed_visit,
        COUNT(CASE WHEN mdvisit_pname2 <> 0 THEN 1 END) AS mdvisit_pname2,
        COUNT(CASE WHEN mdvisit_pname3 <> 0 THEN 1 END) AS mdvisit_pname3,
        COUNT(CASE WHEN routine_care_2 <> 0 THEN 1 END) AS routine_care_2,
        COUNT(CASE WHEN predicted_score <> 0 THEN 1 END) AS predicted_score
    FROM dt_loyalty_result
)
SELECT column_name, nonzero_or_populated_count
FROM counts
UNPIVOT (
    nonzero_or_populated_count FOR column_name IN (
        total_rows             AS 'TOTAL ROWS',
        lookback_years         AS 'LOOKBACK_YEARS',
        gender_denominators_yn AS 'GENDER_DENOMINATORS_YN',
        site                   AS 'SITE',
        cohort_name            AS 'COHORT_NAME',
        patient_num            AS 'PATIENT_NUM',
        death_dt               AS 'DEATH_DT',
        index_dt               AS 'INDEX_DT',
        sex                    AS 'SEX',
        age                    AS 'AGE',
        age_grp                AS 'AGE_GRP',
        num_dx1                AS 'NUM_DX1',
        num_dx2                AS 'NUM_DX2',
        med_use1               AS 'MED_USE1',
        med_use2               AS 'MED_USE2',
        mammography            AS 'MAMMOGRAPHY',
        pap_test               AS 'PAP_TEST',
        psa_test               AS 'PSA_TEST',
        colonoscopy            AS 'COLONOSCOPY',
        fecal_occult_test      AS 'FECAL_OCCULT_TEST',
        flu_shot               AS 'FLU_SHOT',
        pneumococcal_vaccine   AS 'PNEUMOCOCCAL_VACCINE',
        bmi                    AS 'BMI',
        a1c                    AS 'A1C',
        medical_exam           AS 'MEDICAL_EXAM',
        inp1_opt1_visit        AS 'INP1_OPT1_VISIT',
        opt2_visit             AS 'OPT2_VISIT',
        ed_visit               AS 'ED_VISIT',
        mdvisit_pname2         AS 'MDVISIT_PNAME2',
        mdvisit_pname3         AS 'MDVISIT_PNAME3',
        routine_care_2         AS 'ROUTINE_CARE_2',
        predicted_score        AS 'PREDICTED_SCORE'
    )
)
ORDER BY column_name;

--- === DT_LOYALTY_RESULT_CHARLSON nonzero/populated cell counts ===

WITH counts AS (
    SELECT
        COUNT(*) AS total_rows,
        COUNT(CASE WHEN lookback_years <> 0 THEN 1 END) AS lookback_years,
        COUNT(CASE WHEN gender_denominators_yn IS NOT NULL THEN 1 END) AS gender_denominators_yn,
        COUNT(CASE WHEN site IS NOT NULL THEN 1 END) AS site,
        COUNT(CASE WHEN cohort_name IS NOT NULL THEN 1 END) AS cohort_name,
        COUNT(CASE WHEN patient_num <> 0 THEN 1 END) AS patient_num,
        COUNT(CASE WHEN death_dt IS NOT NULL THEN 1 END) AS death_dt,
        COUNT(CASE WHEN last_visit IS NOT NULL THEN 1 END) AS last_visit,
        COUNT(CASE WHEN sex IS NOT NULL THEN 1 END) AS sex,
        COUNT(CASE WHEN age <> 0 THEN 1 END) AS age,
        COUNT(CASE WHEN age_grp IS NOT NULL THEN 1 END) AS age_grp,
        COUNT(CASE WHEN charlson_index <> 0 THEN 1 END) AS charlson_index,
        COUNT(CASE WHEN charlson_10yr_prob <> 0 THEN 1 END) AS charlson_10yr_prob,
        COUNT(CASE WHEN mi <> 0 THEN 1 END) AS mi,
        COUNT(CASE WHEN chf <> 0 THEN 1 END) AS chf,
        COUNT(CASE WHEN cvd <> 0 THEN 1 END) AS cvd,
        COUNT(CASE WHEN pvd <> 0 THEN 1 END) AS pvd,
        COUNT(CASE WHEN dementia <> 0 THEN 1 END) AS dementia,
        COUNT(CASE WHEN copd <> 0 THEN 1 END) AS copd,
        COUNT(CASE WHEN rheumdis <> 0 THEN 1 END) AS rheumdis,
        COUNT(CASE WHEN pepulcer <> 0 THEN 1 END) AS pepulcer,
        COUNT(CASE WHEN mildlivdis <> 0 THEN 1 END) AS mildlivdis,
        COUNT(CASE WHEN diabetes_nocc <> 0 THEN 1 END) AS diabetes_nocc,
        COUNT(CASE WHEN diabetes_wtcc <> 0 THEN 1 END) AS diabetes_wtcc,
        COUNT(CASE WHEN hemiparapleg <> 0 THEN 1 END) AS hemiparapleg,
        COUNT(CASE WHEN renaldis <> 0 THEN 1 END) AS renaldis,
        COUNT(CASE WHEN cancer <> 0 THEN 1 END) AS cancer,
        COUNT(CASE WHEN msvlivdis <> 0 THEN 1 END) AS msvlivdis,
        COUNT(CASE WHEN metastatic <> 0 THEN 1 END) AS metastatic,
        COUNT(CASE WHEN aidshiv <> 0 THEN 1 END) AS aidshiv
    FROM dt_loyalty_result_charlson
)
SELECT column_name, nonzero_or_populated_count
FROM counts
UNPIVOT (
    nonzero_or_populated_count FOR column_name IN (
        total_rows             AS 'TOTAL ROWS',
        lookback_years         AS 'LOOKBACK_YEARS',
        gender_denominators_yn AS 'GENDER_DENOMINATORS_YN',
        site                   AS 'SITE',
        cohort_name            AS 'COHORT_NAME',
        patient_num            AS 'PATIENT_NUM',
        death_dt               AS 'DEATH_DT',
        last_visit             AS 'LAST_VISIT',
        sex                    AS 'SEX',
        age                    AS 'AGE',
        age_grp                AS 'AGE_GRP',
        charlson_index         AS 'CHARLSON_INDEX',
        charlson_10yr_prob     AS 'CHARLSON_10YR_PROB',
        mi                     AS 'MI',
        chf                    AS 'CHF',
        cvd                    AS 'CVD',
        pvd                    AS 'PVD',
        dementia               AS 'DEMENTIA',
        copd                   AS 'COPD',
        rheumdis               AS 'RHEUMDIS',
        pepulcer               AS 'PEPULCER',
        mildlivdis             AS 'MILDLIVDIS',
        diabetes_nocc          AS 'DIABETES_NOCC',
        diabetes_wtcc          AS 'DIABETES_WTCC',
        hemiparapleg           AS 'HEMIPARAPLEG',
        renaldis               AS 'RENALDIS',
        cancer                 AS 'CANCER',
        msvlivdis              AS 'MSVLIVDIS',
        metastatic             AS 'METASTATIC',
        aidshiv                AS 'AIDSHIV'
    )
)
ORDER BY column_name;
