-- ********************************************************
-- *           LOYALTY COHORT - See this publication:
-- * Klann JG, Henderson DW, Morris M, et al. A broadly applicable approach to enrich 
-- * electronic-health-record cohorts by identifying patients with complete data: a 
-- * multisite evaluation. J Am Med Inform Assoc Published Online First: 25 August 2023. 
-- * doi:10.1093/jamia/ocad166
-- **********************************************************/
--
-- Implements a loyalty cohort algorithm with the same general design defined in 
--   "External Validation of an Algorithm to Identify Patients with High Data-Completeness in Electronic Health Records for Comparative Effectiveness Research" by Lin et al.
-- Written primarily by Darren Henderson with contributions FROM: Jeff Klann, PhD; Andrew Cagan; Barbara Benoit
-- 
-- Calculates 20 variables over the baseline period and computes an overall score, the highest scoring individuals are an approximation of those most likely present for future follow-up
-- This script accepts an index_date and looks back n years previous to that date (baseline period). 
-- 
-- To run:
--   1. Populate DT_LOYALTY_COHORTFILTER with patient cohort to be included:
--      INSERT INTO DT_LOYALTY_COHORTFILTER (PATIENT_NUM, COHORT_NAME, INDEX_DT)
--      SELECT psc.PATIENT_NUM, 'TEST', to_date('2021-02-01', 'YYYY-MM-DD')
--      FROM (
--         SELECT PSC.PATIENT_NUM
--         FROM QT_QUERY_MASTER QM
--             INNER JOIN QT_QUERY_INSTANCE QI ON QI.QUERY_MASTER_ID=QM.QUERY_MASTER_ID
--             INNER JOIN QT_QUERY_RESULT_INSTANCE QRI ON QRI.QUERY_INSTANCE_ID=RESULT.QUERY_INSTANCE_ID
--             INNER JOIN QT_PATIENT_SET_COLLECTION PSC ON PSC.RESULT_INSTANCE_ID=QRI.RESULT_INSTANCE_ID
--         WHERE QM.NAME='patient set test1' AND QM.USER_ID='demouser') X;
--   2. Execute USP_DT_LOYALTYCOHORT stored procedure
--      BEGIN USP_DT_LOYALTYCOHORT('TEST', 1, 0, 0, 0); END;
-- This will create two tables on your db, DT_LOYALTY_RESULT (line level data with variables and score presented for each patient) and DT_LOYALTY_RESULT_SUMMARY (summary table).
-- 
-- Exporting this is compatible with most SHRINE IRBs: select * FROM DT_LOYALTY_RESULT_SUMMARY where SUMMARY_DESCRIPTION='PERCENT SUBJECTS'
-- It is percentages, a predictive score, and an obfuscated count of total patients.
-- 
-- ***** Standard i2b2 table naming conventions are used - Observation_fact, concept_dimension, patient_dimension.
-- ***** Follow the README for more information on installing and running.
-- 
-- Though attempts were made to make this query as generally applicable as possible throughout, you may need to review "POSSIBLE EDITS". 
-- We left comments about throughout the body of the script. 
-- Please utilize CTRL-F and search for <PE. to go through the possible edits that might require your site to intervene.
-- 

-- BEGIN EXECUTE IMMEDIATE 'DROP PROCEDURE USP_DT_LOYALTYCOHORT'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -4043 THEN RAISE; END IF; END;

CREATE OR REPLACE PROCEDURE USP_DT_LOYALTYCOHORT(
    P_SITE VARCHAR,
    P_LOOKBACK_YEARS INT DEFAULT 1, -- DEFAULT TO 1 YEAR
    P_DEMOGRAPHIC_FACTS NUMBER DEFAULT 0,-- DEFAULT FALSE -- IF YOUR SITE STORES DEMOGRAPHIC FACTS IN OBSERVATION_FACT ALTER THIS PARAMETER TO TRUE
    P_GENDERED NUMBER DEFAULT 0, -- DEFAULT TO NON GENDER VERSION
    P_OUTPUT NUMBER DEFAULT 1 -- DEFAULT TO SHOW FINAL OUTPUT
)
AS
    V_COHORT_N INT;
    V_GENDER_YN CHAR(1);
    V_OUTPUT_YN CHAR(1);
    V_START_TS TIMESTAMP;
    V_STEP_TS TIMESTAMP;
    V_ENDRUNTIME_MS INT;
    V_STEPRUNTIME_MS INT;
    V_ROWS INT;
    V_RESULT SYS_REFCURSOR;
    V_ONTOLOGY_CURSOR SYS_REFCURSOR;
    V_ONTOLOGY_TABLE VARCHAR2(400);
    V_ONTOLOGY_OBJECT VARCHAR2(500);
    V_ONTOLOGY_SQL VARCHAR2(32767);
    V_HAS_CONCEPT_DIM NUMBER := 0;
    V_HAS_TABLE_ACCESS NUMBER := 0;
    V_ONTOLOGY_TABLE_COUNT NUMBER := 0;
    V_UNMATCHED_PATHS NUMBER := 0;
    V_CHARLSON_CODE_COUNT NUMBER := 0;
    V_CHARLSON_CATEGORY_COUNT NUMBER := 0;
    V_CHARLSON_PATTERN_COUNT NUMBER := 0;
    V_CHARLSON_FLAG_PATIENTS NUMBER := 0;
    V_INP1_OPT1_PATIENTS NUMBER := 0;
    V_OPT2_PATIENTS NUMBER := 0;
    V_ED_PATIENTS NUMBER := 0;

    PROCEDURE CLOSE_CURSOR_IF_OPEN(P_CURSOR IN OUT SYS_REFCURSOR) IS
    BEGIN
        IF P_CURSOR%ISOPEN THEN
            CLOSE P_CURSOR;
        END IF;
    EXCEPTION
        WHEN INVALID_CURSOR THEN NULL;
    END;
BEGIN
    -- CHECK ANY CUSTOM LOCAL CODES ADDED TO DT_LOYALTY_PATHS AT <PE.1> AND <PE.2> - PLEASE SEE COMMENTS

    -- ENSURE TEMP IS CLEAR FROM PREVIOUS RUNS
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DT_TMP_AGE_GRP_PSC';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DT_TMP_COHORT_FILTER';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DT_TMP_DEMCONCEPT';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DT_TMP_LOY_CONCEPT';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DT_TMP_INCLPAT';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DT_TMP_COHORT';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DT_TMP_COHORT_FLAGS_PSC';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DT_TMP_COHORT_AGE_GRP';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DT_TMP_CHARLSON_VISIT_BASE';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DT_TMP_CHARLSON_DX';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DT_TMP_COHORT_CHARLSON';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DT_TMP_CHARLSON_STATS';

    -- Build a private unified concept map. Conventional i2b2 exposes one
    -- CONCEPT_DIMENSION, while ACT-OMOP distributes metadata across the active
    -- ontology tables registered in TABLE_ACCESS. Both are loaded when present.
    BEGIN
        EXECUTE IMMEDIATE q'~
            INSERT INTO DT_TMP_LOY_CONCEPT (CONCEPT_PATH, CONCEPT_CD)
            SELECT DISTINCT CAST(CONCEPT_PATH AS VARCHAR2(700)), CAST(CONCEPT_CD AS VARCHAR2(50))
            FROM CONCEPT_DIMENSION
            WHERE CONCEPT_PATH IS NOT NULL AND CONCEPT_CD IS NOT NULL
        ~';
        V_HAS_CONCEPT_DIM := 1;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -942 THEN
                RAISE_APPLICATION_ERROR(-20002,
                    'Unable to read CONCEPT_DIMENSION: ' || SQLERRM);
            END IF;
    END;

    BEGIN
        OPEN V_ONTOLOGY_CURSOR FOR
            'SELECT DISTINCT C_TABLE_NAME FROM TABLE_ACCESS ' ||
            'WHERE C_TABLE_NAME IS NOT NULL AND C_VISUALATTRIBUTES LIKE ''%A%''';
        V_HAS_TABLE_ACCESS := 1;

        LOOP
            FETCH V_ONTOLOGY_CURSOR INTO V_ONTOLOGY_TABLE;
            EXIT WHEN V_ONTOLOGY_CURSOR%NOTFOUND;

            IF INSTR(V_ONTOLOGY_TABLE, '@') > 0 THEN
                RAISE_APPLICATION_ERROR(-20003,
                    'Database-link ontology objects are not supported: ' || V_ONTOLOGY_TABLE);
            END IF;

            BEGIN
                V_ONTOLOGY_OBJECT := DBMS_ASSERT.SQL_OBJECT_NAME(V_ONTOLOGY_TABLE);
            EXCEPTION
                WHEN OTHERS THEN
                    RAISE_APPLICATION_ERROR(-20004,
                        'TABLE_ACCESS contains an invalid or inaccessible C_TABLE_NAME: ' || V_ONTOLOGY_TABLE);
            END;

            V_ONTOLOGY_SQL :=
                'INSERT INTO DT_TMP_LOY_CONCEPT (CONCEPT_PATH, CONCEPT_CD) ' ||
                'SELECT DISTINCT CAST(C_FULLNAME AS VARCHAR2(700)), CAST(C_BASECODE AS VARCHAR2(50)) ' ||
                'FROM ' || V_ONTOLOGY_OBJECT || ' O ' ||
                'WHERE O.C_FULLNAME IS NOT NULL AND O.C_BASECODE IS NOT NULL AND (' ||
                'O.C_FULLNAME LIKE ''\ACT\Demographics%'' OR ' ||
                'O.C_FULLNAME LIKE ''\ACT\Diagnosis\ICD10%'' OR ' ||
                'O.C_FULLNAME LIKE ''\ACT\Diagnosis\ICD9%'' OR ' ||
                'EXISTS (SELECT 1 FROM DT_LOYALTY_PATHS L ' ||
                'WHERE L.CONCEPT_PATH IS NOT NULL AND L.CONCEPT_PATH <> ''**Not Found'' ' ||
                'AND O.C_FULLNAME LIKE L.CONCEPT_PATH || ''%''))';

            BEGIN
                EXECUTE IMMEDIATE V_ONTOLOGY_SQL;
            EXCEPTION
                WHEN OTHERS THEN
                    CLOSE_CURSOR_IF_OPEN(V_ONTOLOGY_CURSOR);
                    RAISE_APPLICATION_ERROR(-20005,
                        'Unable to read ontology table ' || V_ONTOLOGY_TABLE || ': ' || SQLERRM);
            END;

            V_ONTOLOGY_TABLE_COUNT := V_ONTOLOGY_TABLE_COUNT + 1;
        END LOOP;
        CLOSE V_ONTOLOGY_CURSOR;
    EXCEPTION
        WHEN OTHERS THEN
            CLOSE_CURSOR_IF_OPEN(V_ONTOLOGY_CURSOR);
            IF SQLCODE = -942 THEN
                V_HAS_TABLE_ACCESS := 0;
            ELSE
                RAISE;
            END IF;
    END;

    IF V_HAS_CONCEPT_DIM = 0 AND V_HAS_TABLE_ACCESS = 0 THEN
        RAISE_APPLICATION_ERROR(-20006,
            'Loyalty cohort requires CONCEPT_DIMENSION or ACT-OMOP TABLE_ACCESS metadata.');
    END IF;

    SELECT COUNT(*) INTO V_ROWS
    FROM DT_LOYALTY_PATHS L
    WHERE L.CONCEPT_PATH IS NOT NULL
      AND L.CONCEPT_PATH <> '**Not Found'
      AND EXISTS (
          SELECT 1 FROM DT_TMP_LOY_CONCEPT C
          WHERE C.CONCEPT_PATH LIKE L.CONCEPT_PATH || '%'
      );

    IF V_ROWS = 0 THEN
        RAISE_APPLICATION_ERROR(-20007,
            'No DT_LOYALTY_PATHS entries matched the installed ontology. Check TABLE_ACCESS and the installed ACT ontology version.');
    END IF;

    SELECT COUNT(*) INTO V_UNMATCHED_PATHS
    FROM DT_LOYALTY_PATHS L
    WHERE L.CONCEPT_PATH IS NOT NULL
      AND L.CONCEPT_PATH <> '**Not Found'
      AND NOT EXISTS (
          SELECT 1 FROM DT_TMP_LOY_CONCEPT C
          WHERE C.CONCEPT_PATH LIKE L.CONCEPT_PATH || '%'
      );

    IF V_UNMATCHED_PATHS > 0 THEN
        DBMS_OUTPUT.PUT_LINE('Warning: ' || TO_CHAR(V_UNMATCHED_PATHS) ||
            ' DT_LOYALTY_PATHS rows did not match the installed ontology. Run the Oracle OMOP validation script for details.');
    END IF;

    -- CONVERT UDT TABLE VARIABLE PARAMETER TO TEMP TABLE AND CREATE INDEXES
    BEGIN EXECUTE IMMEDIATE 'DROP INDEX IDX_DT_TMP_COHORT_FILTER'; EXCEPTION WHEN OTHERS THEN NULL; END;
    INSERT INTO DT_TMP_COHORT_FILTER SELECT * FROM DT_LOYALTY_COHORTFILTER;
    EXECUTE IMMEDIATE 'CREATE INDEX IDX_DT_TMP_COHORT_FILTER ON DT_TMP_COHORT_FILTER (PATIENT_NUM, INDEX_DT, COHORT_NAME)';

    SELECT COUNT(*) INTO V_COHORT_N FROM DT_TMP_COHORT_FILTER;

    -- START PROCESSING
    V_GENDER_YN := CASE WHEN P_GENDERED = 0 THEN 'N' ELSE 'Y' END;
    V_OUTPUT_YN := CASE WHEN P_OUTPUT = 0 THEN 'N' ELSE 'Y' END;

    DBMS_OUTPUT.PUT_LINE('i2b2 Loyalty Cohort. See doi:10.1093/jamia/ocad166.');
    DBMS_OUTPUT.PUT_LINE('Please be prepared to share these debug messages if your site runs INTO any issues.');
    DBMS_OUTPUT.PUT_LINE('STARTING ANALYSIS (COHORT_FILTER RECORDS=' || TO_CHAR(V_COHORT_N) || ', SITE=' || p_site || ', LOOKBACK_YR=' || TO_CHAR(p_lookback_years) || ', GENDER_DENOMINATORS=' || v_gender_yn || ', output=' || v_output_yn);

    V_START_TS := LOCALTIMESTAMP;

    IF P_DEMOGRAPHIC_FACTS=1 THEN -- THE SITE STORES SOME KIND OF DEMOGRAPHIC FACT IN OBSERVATION_FACT -- WE WANT TO MAKE SURE THESE ARE EXCLUDED
        DBMS_OUTPUT.PUT_LINE('Starting DT_TMP_INCLPAT phase - p_demographic_facts=1');

        -- EXTRACT DEMOGRAPHIC CONCEPTS
        INSERT INTO DT_TMP_DEMCONCEPT
        SELECT DISTINCT CONCEPT_CD, SUBSTR(CONCEPT_CD,1, INSTR(CONCEPT_CD, ':')-1) AS CONCEPT_PREFIX
        FROM DT_TMP_LOY_CONCEPT
        WHERE CONCEPT_PATH LIKE '\ACT\Demographics%' and nvl(concept_cd, '') is not null;

        INSERT INTO DT_TMP_INCLPAT (PATIENT_NUM)
        SELECT DISTINCT A.PATIENT_NUM
        -- DISTINCT list of patients left over FROM except operation would be patient-concept_cd key pairs for any other fact type
        FROM (
                -- all patient-concept_cd key pairs during measure period
                SELECT DISTINCT F.PATIENT_NUM, F.CONCEPT_CD
                FROM DT_TMP_COHORT_FILTER CF
                    INNER JOIN OBSERVATION_FACT F 
                        ON CF.PATIENT_NUM = F.PATIENT_NUM
                WHERE F.START_DATE >= ADD_MONTHS(CF.INDEX_DT, -12 * P_LOOKBACK_YEARS)
                    AND F.START_DATE < CF.INDEX_DT + 1
            ) A -- altered oct2022 - base non-demographic fact lookup on measure period
            -- exclude patient-concept_cd demographic pairs
            LEFT JOIN (
                SELECT DISTINCT F.PATIENT_NUM, F.CONCEPT_CD
                FROM DT_TMP_COHORT_FILTER CF
                    INNER JOIN OBSERVATION_FACT F 
                        ON CF.PATIENT_NUM = F.PATIENT_NUM
                    INNER JOIN DT_TMP_DEMCONCEPT D 
                        ON F.CONCEPT_CD = D.CONCEPT_CD
                WHERE F.START_DATE >= ADD_MONTHS(CF.INDEX_DT, -12 * P_LOOKBACK_YEARS) AND F.START_DATE < CF.INDEX_DT + 1 -- ALTERED OCT2022 - BASE NON-DEMOGRAPHIC FACT LOOKUP ON MEASURE PERIOD
                ) B ON B.PATIENT_NUM = A.PATIENT_NUM AND B.CONCEPT_CD = A.CONCEPT_CD
        WHERE B.PATIENT_NUM IS NULL;
        
        V_ROWS := SQL%ROWCOUNT;

    ELSE -- THE SITE DOES NOT STORE DEMOGRAPHIC FACTS OF ANY KIND IN OBSERVATION_FACT -- JUST NEED TO CONFIRM A FACT EXISTS DURING THE MEASURE PERIOD
        DBMS_OUTPUT.PUT_LINE('Starting DT_TMP_INCLPAT phase - p_demographic_facts=0');

        INSERT INTO DT_TMP_INCLPAT (PATIENT_NUM)
        SELECT DISTINCT F.PATIENT_NUM
        FROM DT_TMP_COHORT_FILTER CF
            INNER JOIN OBSERVATION_FACT F ON CF.PATIENT_NUM = F.PATIENT_NUM
        WHERE F.START_DATE >= ADD_MONTHS(CF.INDEX_DT, -12 * P_LOOKBACK_YEARS) AND F.START_DATE < CF.INDEX_DT + 1; -- ALTERED OCT2022 - BASE NON-DEMOGRAPHIC FACT LOOKUP ON MEASURE PERIOD
        
        V_ROWS := SQL%ROWCOUNT;
    END if;

    V_ENDRUNTIME_MS := EXTRACT (DAY FROM (LOCALTIMESTAMP - V_START_TS))*24*60*60 +
        EXTRACT (HOUR FROM (LOCALTIMESTAMP - V_START_TS))*60*60+
        EXTRACT (MINUTE FROM (LOCALTIMESTAMP - V_START_TS))*60+
        ROUND(EXTRACT(SECOND FROM (LOCALTIMESTAMP - V_START_TS))*1000);
    V_STEPRUNTIME_MS := EXTRACT (DAY FROM (LOCALTIMESTAMP - V_STEP_TS))*24*60*60 +
        EXTRACT (HOUR FROM (LOCALTIMESTAMP - V_STEP_TS))*60*60+
        EXTRACT (MINUTE FROM (LOCALTIMESTAMP - V_STEP_TS))*60+
        ROUND(EXTRACT(SECOND FROM (LOCALTIMESTAMP - V_STEP_TS))*1000);
    DBMS_OUTPUT.PUT_LINE('Finish DT_TMP_INCLPAT - Rows: ' || TO_CHAR(v_rows) || '- Total Execution (ms)' || TO_CHAR(v_endruntime_ms) || ' - Step Runtime (ms): ' || TO_CHAR(v_stepruntime_ms));

    -- FINISH PRE-BUILD ACT MODEL
    -- EXTRACT COHORT AND VISIT TYPE FLAGS
    V_STEP_TS := LOCALTIMESTAMP;

    INSERT INTO DT_TMP_COHORT (COHORT_NAME, PATIENT_NUM, AGE, SEX, INP1_OPT1_VISIT, OPT2_VISIT, ED_VISIT, LAST_VISIT, INDEX_DT)
    SELECT COHORT_NAME, C.PATIENT_NUM,
        TRUNC((INDEX_DT-TRUNC(P.BIRTH_DATE))/365.25) AGE,
        P.SEX,
        MAX(INP1_OPT1_VISIT) AS INP1_OPT1_VISIT, MAX(OPT2_VISIT) OPT2_VISIT, MAX(ED_VISIT) ED_VISIT, MAX(LAST_VISIT) LAST_VISIT, INDEX_DT
    FROM (
            -- 1 INPATIENT OR 1 OUTPATIENT VISIT DURING THE MEASURED LOOKBACK PERIOD
            SELECT CF.COHORT_NAME, P.PATIENT_NUM, 1 AS INP1_OPT1_VISIT, 0 AS OPT2_VISIT, 0 AS ED_VISIT, NULL AS LAST_VISIT, CF.INDEX_DT
            FROM DT_TMP_INCLPAT P
                INNER JOIN DT_TMP_COHORT_FILTER CF
                    ON P.PATIENT_NUM = CF.PATIENT_NUM
                INNER JOIN VISIT_DIMENSION V
                    ON P.PATIENT_NUM = V.PATIENT_NUM
                        AND V.START_DATE >= add_months(cf.index_dt, -12 * p_lookback_years) AND V.START_DATE < cf.index_dt + 1 -- ALTERED OCT2022 - BASE NON-DEMOGRAPHIC FACT LOOKUP ON MEASURE PERIOD
                        AND TRIM(TO_CHAR(V.INOUT_CD)) IN (
                            SELECT TRIM(VD.CONCEPT_CD)
                            FROM DT_TMP_LOY_CONCEPT VD
                                INNER JOIN DT_LOYALTY_PATHS LCP
                                    ON VD.CONCEPT_PATH LIKE LCP.CONCEPT_PATH || '%'
                                        AND LCP.FEATURE_NAME = 'INP1_OPT1_VISIT'
                            UNION
                            SELECT TRIM(SITE_SPECIFIC_CODE)
                            FROM DT_LOYALTY_PATHS
                            WHERE FEATURE_NAME = 'INP1_OPT1_VISIT'
                                AND CODE_TYPE = 'SITE'
                                AND nvl(SITE_SPECIFIC_CODE, '') is not null)
            GROUP BY CF.COHORT_NAME, P.PATIENT_NUM, CF.INDEX_DT
            UNION ALL
            -- AT LEAST 2 OUTPATIENT VISITS DURING THE MEASURED LOOKBACK PERIOD
            SELECT CF.COHORT_NAME, P.PATIENT_NUM, 0, 1 AS OPT2_VISIT, 0, NULL, CF.INDEX_DT
            FROM DT_TMP_INCLPAT P
                INNER JOIN DT_TMP_COHORT_FILTER CF ON P.PATIENT_NUM = CF.PATIENT_NUM
                INNER JOIN VISIT_DIMENSION V ON P.PATIENT_NUM = V.PATIENT_NUM
                    AND V.START_DATE >= add_months(cf.index_dt, -12 * p_lookback_years) AND V.START_DATE < cf.index_dt + 1 -- ALTERED OCT2022 - BASE NON-DEMOGRAPHIC FACT LOOKUP ON MEASURE PERIOD
                    AND TRIM(TO_CHAR(V.INOUT_CD)) IN (
                        SELECT TRIM(VD.CONCEPT_CD)
                        FROM DT_TMP_LOY_CONCEPT VD
                            INNER JOIN DT_LOYALTY_PATHS LCP ON VD.CONCEPT_PATH LIKE LCP.CONCEPT_PATH || '%' AND LCP.FEATURE_NAME = 'OPT2_VISIT'
                        UNION
                        SELECT TRIM(SITE_SPECIFIC_CODE)
                        FROM DT_LOYALTY_PATHS
                        WHERE FEATURE_NAME = 'OPT2_VISIT' AND CODE_TYPE = 'SITE' AND nvl(SITE_SPECIFIC_CODE, '') is not null)
            GROUP BY CF.COHORT_NAME, P.PATIENT_NUM, CF.INDEX_DT
            HAVING COUNT(*) >= 2
            UNION ALL
            -- AT LEAST 1 ED VISIT DURING THE MEASURED LOOKBACK PERIOD
            SELECT CF.COHORT_NAME, P.PATIENT_NUM, 0, 0, 1 AS ED_VISIT, NULL, CF.INDEX_DT
            FROM DT_TMP_INCLPAT P
                INNER JOIN DT_TMP_COHORT_FILTER CF ON P.PATIENT_NUM = CF.PATIENT_NUM
                INNER JOIN VISIT_DIMENSION V ON P.PATIENT_NUM = V.PATIENT_NUM
                    AND V.START_DATE >= add_months(cf.index_dt, -12 * p_lookback_years) AND V.START_DATE < cf.index_dt + 1 -- ALTERED OCT2022 - BASE NON-DEMOGRAPHIC FACT LOOKUP ON MEASURE PERIOD
                    AND TRIM(TO_CHAR(V.INOUT_CD)) IN (
                        SELECT TRIM(VD.CONCEPT_CD)
                        FROM DT_TMP_LOY_CONCEPT VD
                            INNER JOIN DT_LOYALTY_PATHS LCP ON VD.CONCEPT_PATH LIKE LCP.CONCEPT_PATH || '%' AND LCP.FEATURE_NAME = 'ED_VISIT'
                            UNION
                            SELECT TRIM(SITE_SPECIFIC_CODE)
                            FROM DT_LOYALTY_PATHS
                            WHERE FEATURE_NAME = 'ED_VISIT' AND CODE_TYPE = 'SITE' AND nvl(SITE_SPECIFIC_CODE,'') is not null)
            GROUP BY CF.COHORT_NAME, P.PATIENT_NUM, CF.INDEX_DT
            UNION ALL
            -- LAST VISIT
            SELECT CF.COHORT_NAME, P.PATIENT_NUM, 0, 0, 0, MAX(V.START_DATE) AS LAST_VISIT, CF.INDEX_DT
            FROM DT_TMP_INCLPAT P
                INNER JOIN DT_TMP_COHORT_FILTER CF ON P.PATIENT_NUM = CF.PATIENT_NUM
                INNER JOIN VISIT_DIMENSION V ON P.PATIENT_NUM = V.PATIENT_NUM
                    AND V.START_DATE >= add_months(cf.index_dt, -12 * p_lookback_years) AND V.START_DATE < cf.index_dt + 1 -- ALTERED OCT2022 - BASE NON-DEMOGRAPHIC FACT LOOKUP ON MEASURE PERIOD
            GROUP BY CF.COHORT_NAME, P.PATIENT_NUM, CF.INDEX_DT
        ) C
        INNER JOIN (
            SELECT PATIENT_NUM, BIRTH_DATE,
                CASE UPPER(TRIM(TO_CHAR(SEX_CD)))
                    WHEN 'DEM|SEX:F' THEN 'F'
                    WHEN 'F' THEN 'F'
                    WHEN '8532' THEN 'F'
                    WHEN 'DEM|SEX:M' THEN 'M'
                    WHEN 'M' THEN 'M'
                    WHEN '8507' THEN 'M'
                    ELSE REPLACE(UPPER(TRIM(TO_CHAR(SEX_CD))), 'DEM|SEX:', '')
                END AS SEX
            FROM PATIENT_DIMENSION
        ) P ON C.PATIENT_NUM = P.PATIENT_NUM
    GROUP BY COHORT_NAME, C.PATIENT_NUM, P.SEX,
        TRUNC((INDEX_DT-TRUNC(P.BIRTH_DATE))/365.25), INDEX_DT;
    V_ROWS := SQL%ROWCOUNT;

    SELECT NVL(SUM(INP1_OPT1_VISIT), 0), NVL(SUM(OPT2_VISIT), 0), NVL(SUM(ED_VISIT), 0)
    INTO V_INP1_OPT1_PATIENTS, V_OPT2_PATIENTS, V_ED_PATIENTS
    FROM DT_TMP_COHORT;

    DBMS_OUTPUT.PUT_LINE('Visit flag checkpoint - INP1_OPT1 patients=' ||
        TO_CHAR(V_INP1_OPT1_PATIENTS) || ', OPT2 patients=' ||
        TO_CHAR(V_OPT2_PATIENTS) || ', ED patients=' || TO_CHAR(V_ED_PATIENTS));

    -- FINISH COHORT VISIT TYPE PREP
    V_ENDRUNTIME_MS := EXTRACT (DAY FROM (LOCALTIMESTAMP - V_START_TS))*24*60*60 +
        EXTRACT (HOUR FROM (LOCALTIMESTAMP - V_START_TS))*60*60+
        EXTRACT (MINUTE FROM (LOCALTIMESTAMP - V_START_TS))*60+
        ROUND(EXTRACT(SECOND FROM (LOCALTIMESTAMP - V_START_TS))*1000);
    V_STEPRUNTIME_MS := EXTRACT (DAY FROM (LOCALTIMESTAMP - V_STEP_TS))*24*60*60 +
        EXTRACT (HOUR FROM (LOCALTIMESTAMP - V_STEP_TS))*60*60+
        EXTRACT (MINUTE FROM (LOCALTIMESTAMP - V_STEP_TS))*60+
        ROUND(EXTRACT(SECOND FROM (LOCALTIMESTAMP - V_STEP_TS))*1000);
    DBMS_OUTPUT.PUT_LINE('Cohort and Visit Type variables - Rows: ' || TO_CHAR(v_rows) || '- Total Execution (ms)' || TO_CHAR(v_endruntime_ms) || ' - Step Runtime (ms): ' || TO_CHAR(v_stepruntime_ms));

    -- HAVE TO CENSOR BAD BIRTH_DATE DATA FOR AGE_GRP STEPS LATER
    DELETE FROM DT_TMP_COHORT WHERE AGE IS NULL;
    V_ROWS := SQL%ROWCOUNT;

    IF V_ROWS > 0 THEN
        DBMS_OUTPUT.PUT_LINE('Dropping patients with null birth_date - Rows: ' || TO_CHAR(v_rows));
    END IF;

    -- DROP PEDIATRIC CASES - THE LOYALTY COHORT IS BASED OFF WORK BASED ON A MEDICARE POPULATION AND WE CURRENTLY LACK GOOD PROXIES FOR PEDIATRIC CASES FOR SOME OF THE VARIABLES/COEFFICIENTS
    DELETE FROM DT_TMP_COHORT WHERE AGE <= 18;
    V_ROWS := SQL%ROWCOUNT;

    IF V_ROWS > 0 THEN
        DBMS_OUTPUT.PUT_LINE('Dropping pediatric cases - The script is not currently designed for Age<=18 - Rows: ' || TO_CHAR(v_rows));
    END IF;

    -- COHORT FLAGS PSC BLOCK
    V_STEP_TS := LOCALTIMESTAMP;

    INSERT INTO DT_TMP_COHORT_FLAGS_PSC
    WITH
        CTE_PARAMS AS (
            SELECT DISTINCT FEATURE_NAME, CONCEPT_CD, CODE_TYPE --[CONCEPT_PATH],
            FROM DT_LOYALTY_PATHS L, DT_TMP_LOY_CONCEPT C
            WHERE C.CONCEPT_PATH LIKE L.CONCEPT_PATH|| '%'  --JGK: MUST SUPPORT LOCAL CHILDREN
            AND CODE_TYPE IN ('DX','PX','LAB','MEDS','SITE') -- <PE.1> IF YOUR SITE IS MANAGING ANY SITE SPECIFIC CODES FOR THE FOLLOWING DOMAINS SET THEIR CODE_TYPE = 'SITE' IN DT_LOYALTY_PATHS </PE.1>
            AND (L.CONCEPT_PATH <> '**Not Found' AND L.CONCEPT_PATH IS NOT NULL)
        ),
        CTE_FEATURE_OCCUR AS (
            SELECT C.COHORT_NAME, O.PATIENT_NUM, C.INDEX_DT, P.FEATURE_NAME
              -- ALTERED THE MD visit variables to ignore DISTINCT provider_id to allow it to count at least DISTINCT visit dates at sites that only load '@' for PROVIDER_ID
              , CASE
                     WHEN FEATURE_NAME IN ('MDVISIT_PNAME2','MDVISIT_PNAME3','NUM_DX1','NUM_DX2','MED_USE1','MED_USE2') THEN COUNT(DISTINCT cast(O.START_DATE as date)) -- FOR THE MD VISIT, NUM_DX, AND MEDUSE DOMAINS - WE COUNT DISTINCT VISIT DATES
                     ELSE COUNT(*) END OCCUR -- FOR OTHER DOMAINS WE COUNT RAW FACT OCCURRENCE IN FACT TABLE
              , CASE WHEN FEATURE_NAME IN ('MDVISIT_PNAME2','MDVISIT_PNAME3','NUM_DX1','NUM_DX2','MED_USE1','MED_USE2')
                     THEN REPLACE(REPLACE(REPLACE(FEATURE_NAME,'MDVISIT_PNAME',''),'NUM_DX',''),'MED_USE','') ELSE NULL END AS THRESHOLD
            FROM DT_TMP_COHORT C
              INNER JOIN OBSERVATION_FACT O
                ON C.PATIENT_NUM = O.PATIENT_NUM
              INNER JOIN CTE_PARAMS p
                ON O.CONCEPT_CD = P.CONCEPT_CD
            WHERE O.START_DATE >= add_months(C.index_dt, -12 * p_lookback_years) AND O.START_DATE < C.index_dt + 1 -- ALTERED OCT2022 - BASE NON-DEMOGRAPHIC FACT LOOKUP ON MEASURE PERIOD
            GROUP BY C.COHORT_NAME, O.PATIENT_NUM, C.INDEX_DT, P.FEATURE_NAME
        ),
        CTE_PSC AS (
            SELECT VE.COHORT_NAME, VE.PATIENT_NUM, INDEX_DT, VE.VARIABLE_NAME, VE.OCCUR
              , PSC.COEFF
              , -0.010+SUM(PSC.COEFF*VE.OCCUR) OVER (PARTITION BY VE.PATIENT_NUM,VE.COHORT_NAME,VE.INDEX_DT ORDER BY (SELECT 1 from dual)) Predicted_Score
            FROM (
              -- THE VARIABLES MDVISIT_PNAME2, NumDX1, and MED_USE1 variables were designed to be equality comparisons
              SELECT FO.COHORT_NAME, FO.PATIENT_NUM, INDEX_DT, FO.FEATURE_NAME AS VARIABLE_NAME, case when FO.OCCUR=FO.THRESHOLD then 1 else 0 end OCCUR
              FROM CTE_FEATURE_OCCUR FO
              WHERE FEATURE_NAME IN ('MDVISIT_PNAME2','NUM_DX1','MED_USE1')
              UNION ALL
              -- THE VARIABLES MDVISIT_PNAME3, NumDX2, and MED_USE2 variables were designed to be greater than or equal to comparisons
              SELECT FO.COHORT_NAME, FO.PATIENT_NUM, INDEX_DT, FO.FEATURE_NAME AS VARIABLE_NAME, case when FO.OCCUR>=FO.THRESHOLD then 1 else 0 end OCCUR
              FROM CTE_FEATURE_OCCUR FO
              WHERE FEATURE_NAME IN ('MDVISIT_PNAME3','NUM_DX2','MED_USE2')
              UNION ALL
              -- All other variables were simply if present then true
              SELECT FO.COHORT_NAME, FO.PATIENT_NUM, INDEX_DT, FO.FEATURE_NAMe AS VARIABLE_NAME, case when FO.OCCUR>0 then 1 else 0 end OCCUR
              FROM CTE_FEATURE_OCCUR FO
              WHERE FEATURE_NAME NOT IN ('MDVISIT_PNAME2','MDVISIT_PNAME3','NUM_DX1','NUM_DX2','MED_USE1','MED_USE2')
              UNION ALL
              SELECT COHORT_NAME, PATIENT_NUM, INDEX_DT, 'ROUTINE_CARE_2' as VARIABLE_NAME, 1 AS OCCUR
              FROM CTE_FEATURE_OCCUR FO
              WHERE FEATURE_NAME IN ('MEDICAL_EXAM','MAMMOGRAPHY','PSA_TEST','COLONOSCOPY','FECAL_OCCULT_TEST','FLU_SHOT','PNEUMOCOCCAL_VACCINE','A1C','BMI')
              GROUP BY COHORT_NAME, PATIENT_NUM, INDEX_DT
              HAVING SUM(case when FO.OCCUR>0 then 1 else 0 end) >= 2
              UNION ALL
              SELECT COHORT_NAME, PATIENT_NUM, INDEX_DT, 'INP1_OPT1_VISIT' AS VARIABLE_NAME, INP1_OPT1_VISIT FROM DT_TMP_COHORT WHERE INP1_OPT1_VISIT != 0
              UNION ALL
              SELECT COHORT_NAME, PATIENT_NUM, INDEX_DT, 'OPT2_VISIT' AS VARIABLE_NAME, OPT2_VISIT FROM DT_TMP_COHORT WHERE OPT2_VISIT != 0
              UNION ALL
              SELECT COHORT_NAME, PATIENT_NUM, INDEX_DT, 'ED_VISIT' AS VARIABLE_NAME, ED_VISIT FROM DT_TMP_COHORT WHERE ED_VISIT != 0
            )VE INNER JOIN DT_LOYALTY_PSCOEFF PSC
              on VE.VARIABLE_NAME = PSC.FIELD_NAME
        )
    SELECT COHORT_NAME, PATIENT_NUM,
        MAX(SEX) AS SEX,
        MAX(AGE) AS AGE,
        MAX(NUM_DX1) AS NUM_DX1,
        MAX(NUM_DX2) AS NUM_DX2,
        MAX(MED_USE1) AS MED_USE1,
        MAX(MED_USE2) AS MED_USE2,
        MAX(MAMMOGRAPHY) AS MAMMOGRAPHY,
        MAX(PAP_TEST) AS PAP_TEST,
        MAX(PSA_TEST) AS PSA_TEST,
        MAX(COLONOSCOPY) AS COLONOSCOPY,
        MAX(FECAL_OCCULT_TEST) AS FECAL_OCCULT_TEST,
        MAX(FLU_SHOT) AS FLU_SHOT,
        MAX(PNEUMOCOCCAL_VACCINE) AS PNEUMOCOCCAL_VACCINE,
        MAX(BMI) AS BMI,
        MAX(A1C) AS A1C,
        MAX(MEDICAL_EXAM) AS MEDICAL_EXAM,
        MAX(INP1_OPT1_VISIT) AS INP1_OPT1_VISIT,
        MAX(OPT2_VISIT) AS OPT2_VISIT,
        MAX(ED_VISIT) AS ED_VISIT,
        MAX(MDVISIT_PNAME2) AS MDVISIT_PNAME2,
        MAX(MDVISIT_PNAME3) AS MDVISIT_PNAME3,
        MAX(ROUTINE_CARE_2) AS ROUTINE_CARE_2,
        MAX(PREDICTED_SCORE) AS PREDICTED_SCORE,
        MAX(LAST_VISIT) AS LAST_VISIT,
        INDEX_DT
    FROM (
            SELECT COHORT_NAME, PATIENT_NUM, SEX, AGE, NUM_DX1, NUM_DX2, MED_USE1, MED_USE2, MAMMOGRAPHY, PAP_TEST, PSA_TEST, COLONOSCOPY
              , FECAL_OCCULT_TEST, FLU_SHOT, PNEUMOCOCCAL_VACCINE
              , BMI, A1C, MEDICAL_EXAM, INP1_OPT1_VISIT, OPT2_VISIT, ED_VISIT, MDVISIT_PNAME2, MDVISIT_PNAME3
              , ROUTINE_CARE_2
              , PREDICTED_SCORE
              , LAST_VISIT
              , INDEX_DT
            FROM DT_TMP_COHORT
            UNION ALL
            SELECT COHORT_NAME, PATIENT_NUM, NULL AS SEX, NULL AS AGE
              , NUM_DX1, NUM_DX2, MED_USE1, MED_USE2, MAMMOGRAPHY, PAP_TEST, PSA_TEST, COLONOSCOPY, FECAL_OCCULT_TEST, FLU_SHOT, PNEUMOCOCCAL_VACCINE
              , BMI, A1C, MEDICAL_EXAM, INP1_OPT1_VISIT, OPT2_VISIT, ED_VISIT, MDVISIT_PNAME2, MDVISIT_PNAME3
              , ROUTINE_CARE_2, PREDICTED_SCORE
              , NULL AS LAST_VISIT
              , INDEX_DT
            FROM (
                    SELECT *
                    FROM CTE_PSC
                ) U
                PIVOT (MAX(OCCUR) FOR VARIABLE_NAME IN (
                    'NUM_DX1' NUM_DX1, 'NUM_DX2' NUM_DX2, 'MED_USE1' MED_USE1, 'MED_USE2' MED_USE2,
                    'MAMMOGRAPHY' MAMMOGRAPHY, 'PAP_TEST' PAP_TEST, 'PSA_TEST' PSA_TEST, 'COLONOSCOPY' COLONOSCOPY,
                    'FECAL_OCCULT_TEST' FECAL_OCCULT_TEST, 'FLU_SHOT' FLU_SHOT, 'PNEUMOCOCCAL_VACCINE' PNEUMOCOCCAL_VACCINE,
                    'BMI' BMI, 'A1C' A1C, 'MEDICAL_EXAM' MEDICAL_EXAM, 'INP1_OPT1_VISIT' INP1_OPT1_VISIT,
                    'OPT2_VISIT' OPT2_VISIT, 'ED_VISIT' ED_VISIT, 'MDVISIT_PNAME2' MDVISIT_PNAME2,
                    'MDVISIT_PNAME3' MDVISIT_PNAME3, 'ROUTINE_CARE_2' ROUTINE_CARE_2)
                ) P
        ) COHORT_FLAGS
    GROUP BY COHORT_NAME, PATIENT_NUM, INDEX_DT;

    EXECUTE IMMEDIATE 'TRUNCATE TABLE DT_TMP_COHORT';

    INSERT INTO DT_TMP_COHORT (COHORT_NAME, PATIENT_NUM, DEATH_DT, SEX, AGE, NUM_DX1, NUM_DX2, MED_USE1, MED_USE2,
        MAMMOGRAPHY, PAP_TEST, PSA_TEST, COLONOSCOPY, FECAL_OCCULT_TEST, FLU_SHOT, PNEUMOCOCCAL_VACCINE, BMI, A1C,
        MEDICAL_EXAM, INP1_OPT1_VISIT, OPT2_VISIT, ED_VISIT, MDVISIT_PNAME2, MDVISIT_PNAME3, ROUTINE_CARE_2,
        PREDICTED_SCORE , LAST_VISIT, INDEX_DT)
    SELECT COHORT_NAME, CF.PATIENT_NUM, P.DEATH_DATE, SEX, AGE, NUM_DX1, NUM_DX2, MED_USE1, MED_USE2,
        MAMMOGRAPHY,  PAP_TEST, PSA_TEST, COLONOSCOPY, FECAL_OCCULT_TEST, FLU_SHOT, PNEUMOCOCCAL_VACCINE, BMI, A1C,
        MEDICAL_EXAM, INP1_OPT1_VISIT, OPT2_VISIT, ED_VISIT, MDVISIT_PNAME2, MDVISIT_PNAME3, ROUTINE_CARE_2,
        PREDICTED_SCORE, LAST_VISIT, INDEX_DT
    FROM DT_TMP_COHORT_FLAGS_PSC CF
        INNER JOIN PATIENT_DIMENSION P ON CF.PATIENT_NUM = P.PATIENT_NUM;

    V_ROWS := SQL%ROWCOUNT;
    V_ENDRUNTIME_MS := EXTRACT (DAY FROM (LOCALTIMESTAMP - V_START_TS))*24*60*60 +
        EXTRACT (HOUR FROM (LOCALTIMESTAMP - V_START_TS))*60*60+
        EXTRACT (MINUTE FROM (LOCALTIMESTAMP - V_START_TS))*60+
        ROUND(EXTRACT(SECOND FROM (LOCALTIMESTAMP - V_START_TS))*1000);
    V_STEPRUNTIME_MS := EXTRACT (DAY FROM (LOCALTIMESTAMP - V_STEP_TS))*24*60*60 +
        EXTRACT (HOUR FROM (LOCALTIMESTAMP - V_STEP_TS))*60*60+
        EXTRACT (MINUTE FROM (LOCALTIMESTAMP - V_STEP_TS))*60+
        ROUND(EXTRACT(SECOND FROM (LOCALTIMESTAMP - V_STEP_TS))*1000);
    DBMS_OUTPUT.PUT_LINE('Cohort Flags - Rows: ' || TO_CHAR(v_rows) || '- Total Execution (ms)' || TO_CHAR(v_endruntime_ms) || ' - Step Runtime (ms): ' || TO_CHAR(v_stepruntime_ms));

    -- Cohort Agegrp - Makes Predictive Score filtering easier in final step if pre-calculated
    V_STEP_TS := LOCALTIMESTAMP;

    INSERT INTO DT_TMP_COHORT_AGE_GRP
    SELECT *
    FROM (
            select p_SITE as SITE
                ,COHORT_NAME
                ,PATIENT_NUM
                ,DEATH_DT
                ,INDEX_DT
                ,SEX
                ,AGE
                ,CAST(case when nvl(AGE, 0) < 65 then 'UNDER 65' when AGE >= 65 then 'OVER 65' else null end AS VARCHAR(20)) as AGE_GRP
                ,NUM_DX1
                ,NUM_DX2
                ,MED_USE1
                ,MED_USE2
                ,MAMMOGRAPHY
                ,PAP_TEST
                ,PSA_TEST
                ,COLONOSCOPY
                ,FECAL_OCCULT_TEST
                ,FLU_SHOT
                ,PNEUMOCOCCAL_VACCINE
                ,BMI
                ,A1C
                ,MEDICAL_EXAM
                ,INP1_OPT1_VISIT
                ,OPT2_VISIT
                ,ED_VISIT
                ,MDVISIT_PNAME2
                ,MDVISIT_PNAME3
                ,ROUTINE_CARE_2
                ,PREDICTED_SCORE
            FROM DT_TMP_COHORT
            UNION
            select p_SITE as SITE
                ,COHORT_NAME
                ,PATIENT_NUM
                ,DEATH_DT
                ,INDEX_DT
                ,SEX
                ,AGE
                ,'ALL PATIENTS' AS AGE_GRP
                ,NUM_DX1
                ,NUM_DX2
                ,MED_USE1
                ,MED_USE2
                ,MAMMOGRAPHY
                ,PAP_TEST
                ,PSA_TEST
                ,COLONOSCOPY
                ,FECAL_OCCULT_TEST
                ,FLU_SHOT
                ,PNEUMOCOCCAL_VACCINE
                ,BMI
                ,A1C
                ,MEDICAL_EXAM
                ,INP1_OPT1_VISIT
                ,OPT2_VISIT
                ,ED_VISIT
                ,MDVISIT_PNAME2
                ,MDVISIT_PNAME3
                ,ROUTINE_CARE_2
                ,PREDICTED_SCORE
            FROM DT_TMP_COHORT
        ) CAG;

    V_ROWS := SQL%ROWCOUNT;
    V_ENDRUNTIME_MS := EXTRACT (DAY FROM (LOCALTIMESTAMP - V_START_TS))*24*60*60 +
        EXTRACT (HOUR FROM (LOCALTIMESTAMP - V_START_TS))*60*60+
        EXTRACT (MINUTE FROM (LOCALTIMESTAMP - V_START_TS))*60+
        ROUND(EXTRACT(SECOND FROM (LOCALTIMESTAMP - V_START_TS))*1000);
    V_STEPRUNTIME_MS := EXTRACT (DAY FROM (LOCALTIMESTAMP - V_STEP_TS))*24*60*60 +
        EXTRACT (HOUR FROM (LOCALTIMESTAMP - V_STEP_TS))*60*60+
        EXTRACT (MINUTE FROM (LOCALTIMESTAMP - V_STEP_TS))*60+
        ROUND(EXTRACT(SECOND FROM (LOCALTIMESTAMP - V_STEP_TS))*1000);
    DBMS_OUTPUT.PUT_LINE('Prepare DT_TMP_COHORT_AGE_GRP - Rows: ' || TO_CHAR(v_rows) || '- Total Execution (ms)' || TO_CHAR(v_endruntime_ms) || ' - Step Runtime (ms): ' || TO_CHAR(v_stepruntime_ms));

    -- Calculate Predictive Score Cutoff by over Agegroups
    V_STEP_TS := LOCALTIMESTAMP;

    INSERT INTO DT_TMP_AGE_GRP_PSC
    SELECT COHORT_NAME, AGE_GRP, MIN(PREDICTED_SCORE) PREDICTIVE_SCORE_CUTOFF
    FROM (
            SELECT COHORT_NAME, AGE_GRP, PREDICTED_SCORE, NTILE(5) OVER (PARTITION BY COHORT_NAME, AGE_GRP ORDER BY PREDICTED_SCORE DESC) AS SCORE_RANK
            FROM (
                    SELECT COHORT_NAME, AGE_GRP, predicted_score
                    FROM DT_TMP_COHORT_AGE_GRP
                ) SCORES
        ) M
    WHERE SCORE_RANK=1
    GROUP BY COHORT_NAME, AGE_GRP;

    V_ROWS := SQL%ROWCOUNT;
    V_ENDRUNTIME_MS := EXTRACT (DAY FROM (LOCALTIMESTAMP - V_START_TS))*24*60*60 +
        EXTRACT (HOUR FROM (LOCALTIMESTAMP - V_START_TS))*60*60+
        EXTRACT (MINUTE FROM (LOCALTIMESTAMP - V_START_TS))*60+
        ROUND(EXTRACT(SECOND FROM (LOCALTIMESTAMP - V_START_TS))*1000);
    V_STEPRUNTIME_MS := EXTRACT (DAY FROM (LOCALTIMESTAMP - V_STEP_TS))*24*60*60 +
        EXTRACT (HOUR FROM (LOCALTIMESTAMP - V_STEP_TS))*60*60+
        EXTRACT (MINUTE FROM (LOCALTIMESTAMP - V_STEP_TS))*60+
        ROUND(EXTRACT(SECOND FROM (LOCALTIMESTAMP - V_STEP_TS))*1000);
    DBMS_OUTPUT.PUT_LINE('Prepare DT_TMP_AGE_GRP_PSC - Rows: ' || TO_CHAR(v_rows) || '- Total Execution (ms)' || TO_CHAR(v_endruntime_ms) || ' - Step Runtime (ms): ' || TO_CHAR(v_stepruntime_ms));

    -- OPTIONAL CHARLSON COMORBIDITY INDEX -- ADDS APPROX. 1m in UKY environment.
    --    REQUIRES SITE TO LOAD DT_LOYALTY_CHARLSON FROM REPO

    V_STEP_TS := LOCALTIMESTAMP;

    -- ACT-OMOP stores the ICD string in I2B2_ACT_BASECODE and the fact-facing
    -- standard/source IDs in OMOP_S_CONCEPT_ID and OMOP_NS_CONCEPT_ID.
    -- Discover the registered diagnosis tables dynamically so synonyms and
    -- schema-qualified local objects work without requiring an OMOP CONCEPT
    -- table in the procedure schema.
    V_ONTOLOGY_TABLE_COUNT := 0;

    IF V_HAS_TABLE_ACCESS = 1 THEN
        BEGIN
            OPEN V_ONTOLOGY_CURSOR FOR
                'SELECT DISTINCT C_TABLE_NAME FROM TABLE_ACCESS ' ||
                'WHERE C_TABLE_NAME IS NOT NULL AND C_VISUALATTRIBUTES LIKE ''%A%'' ' ||
                'AND (C_FULLNAME LIKE ''\ACT\Diagnosis\ICD10%'' ' ||
                'OR C_FULLNAME LIKE ''\ACT\Diagnosis\ICD9%'')';

            LOOP
                FETCH V_ONTOLOGY_CURSOR INTO V_ONTOLOGY_TABLE;
                EXIT WHEN V_ONTOLOGY_CURSOR%NOTFOUND;

                V_ONTOLOGY_OBJECT := DBMS_ASSERT.SQL_OBJECT_NAME(V_ONTOLOGY_TABLE);
                V_ONTOLOGY_TABLE_COUNT := V_ONTOLOGY_TABLE_COUNT + 1;

                V_ONTOLOGY_SQL :=
                    'INSERT INTO DT_TMP_CHARLSON_DX (CHARLSON_CATGRY, CHARLSON_WT, CONCEPT_CD) ' ||
                    'SELECT DISTINCT C.CHARLSON_CATGRY, C.CHARLSON_WT, X.CONCEPT_CD ' ||
                    'FROM DT_LOYALTY_CHARLSON C JOIN (' ||
                    'SELECT CAST(I2B2_ACT_BASECODE AS VARCHAR2(100)) ACT_CODE, ' ||
                    'CAST(OMOP_S_CONCEPT_ID AS VARCHAR2(50)) CONCEPT_CD FROM ' || V_ONTOLOGY_OBJECT ||
                    ' UNION ALL SELECT CAST(I2B2_ACT_BASECODE AS VARCHAR2(100)), ' ||
                    'CAST(OMOP_NS_CONCEPT_ID AS VARCHAR2(50)) FROM ' || V_ONTOLOGY_OBJECT ||
                    ') X ON X.ACT_CODE LIKE C.DIAGPATTERN ' ||
                    'WHERE X.CONCEPT_CD IS NOT NULL AND X.ACT_CODE NOT LIKE ''%-%''';

                BEGIN
                    EXECUTE IMMEDIATE V_ONTOLOGY_SQL;
                EXCEPTION
                    WHEN OTHERS THEN
                        -- A conventional i2b2 ontology table has no OMOP mapping
                        -- columns; allow the classic fallback below in that case.
                        IF SQLCODE != -904 THEN
                            CLOSE_CURSOR_IF_OPEN(V_ONTOLOGY_CURSOR);
                            RAISE_APPLICATION_ERROR(-20008,
                                'Unable to build Charlson mappings from ' ||
                                V_ONTOLOGY_TABLE || ': ' || SQLERRM);
                        END IF;
                END;
            END LOOP;
            CLOSE V_ONTOLOGY_CURSOR;
        EXCEPTION
            WHEN OTHERS THEN
                CLOSE_CURSOR_IF_OPEN(V_ONTOLOGY_CURSOR);
                RAISE;
        END;
    END IF;

    SELECT COUNT(*) INTO V_CHARLSON_CODE_COUNT FROM DT_TMP_CHARLSON_DX;

    IF V_CHARLSON_CODE_COUNT = 0 THEN
        -- Conventional i2b2 stores vocabulary-prefixed ICD codes directly.
        INSERT INTO DT_TMP_CHARLSON_DX (CHARLSON_CATGRY, CHARLSON_WT, CONCEPT_CD)
        SELECT DISTINCT C.CHARLSON_CATGRY, C.CHARLSON_WT, DX.CONCEPT_CD
        FROM DT_LOYALTY_CHARLSON C
        INNER JOIN DT_TMP_LOY_CONCEPT DX
            ON (DX.CONCEPT_PATH LIKE '\ACT\Diagnosis\ICD10%'
                OR DX.CONCEPT_PATH LIKE '\ACT\Diagnosis\ICD9%')
           AND DX.CONCEPT_CD LIKE C.DIAGPATTERN
           AND DX.CONCEPT_CD NOT LIKE '%-%';
    END IF;

    SELECT COUNT(DISTINCT CONCEPT_CD), COUNT(DISTINCT CHARLSON_CATGRY)
    INTO V_CHARLSON_CODE_COUNT, V_CHARLSON_CATEGORY_COUNT
    FROM DT_TMP_CHARLSON_DX;

    SELECT COUNT(*) INTO V_CHARLSON_PATTERN_COUNT FROM DT_LOYALTY_CHARLSON;

    DBMS_OUTPUT.PUT_LINE('Charlson metadata discovery - Diagnosis ontology tables: ' ||
        TO_CHAR(V_ONTOLOGY_TABLE_COUNT));
    DBMS_OUTPUT.PUT_LINE('Charlson diagnosis map - Reference patterns: ' ||
        TO_CHAR(V_CHARLSON_PATTERN_COUNT) || ' - Fact concept IDs: ' ||
        TO_CHAR(V_CHARLSON_CODE_COUNT) || ' - Categories: ' ||
        TO_CHAR(V_CHARLSON_CATEGORY_COUNT));

    IF V_CHARLSON_CODE_COUNT = 0 THEN
        DBMS_OUTPUT.PUT_LINE('Warning: no Charlson diagnosis concepts matched the installed ontology; feature flags will be zero and CHARLSON_INDEX will contain age points only.');
    END IF;

    INSERT INTO DT_TMP_CHARLSON_VISIT_BASE
    WITH
        CTE_VISIT_BASE AS (
            SELECT COHORT_NAME, PATIENT_NUM, SEX, AGE, LAST_VISIT,
                CASE
                    WHEN AGE < 50 THEN 0
                    WHEN AGE BETWEEN 50 AND 59 THEN 1
                    WHEN AGE BETWEEN 60 AND 69 THEN 2
                    WHEN AGE >= 70 THEN 3
                END AS CHARLSON_AGE_BASE
            FROM (
                    SELECT COHORT_NAME, V.PATIENT_NUM
                        , SEX
                        , V.AGE
                        , LAST_VISIT
                    FROM DT_TMP_COHORT V
                ) VISITS
        )
    SELECT COHORT_NAME, PATIENT_NUM, SEX, AGE, LAST_VISIT, CHARLSON_AGE_BASE
    FROM CTE_VISIT_BASE;

    INSERT INTO DT_TMP_COHORT_CHARLSON
    SELECT P_SITE as SITE, COHORT_NAME, PATIENT_NUM,
        LAST_VISIT,
        SEX,
        AGE,
        CAST(CASE WHEN AGE < 65 THEN 'UNDER 65' WHEN AGE>=65 THEN 'OVER 65' ELSE '-' END AS VARCHAR(20)) AS AGE_GRP,
        CHARLSON_INDEX,
        POWER( 0.983,
               POWER(2.71828, (CASE WHEN CHARLSON_INDEX > 7 THEN 7 ELSE CHARLSON_INDEX END) * 0.9)
            ) * 100.0 AS CHARLSON_10YR_PROB,
        MI, CHF, CVD, PVD, DEMENTIA, COPD, RHEUMDIS, PEPULCER, MILDLIVDIS, DIABETES_NOCC, DIABETES_WTCC, HEMIPARAPLEG, RENALDIS, CANCER, MSVLIVDIS, METASTATIC, AIDSHIV
    FROM (
            SELECT COHORT_NAME, PATIENT_NUM, LAST_VISIT, SEX, AGE,
                CHARLSON_AGE_BASE
                    + MI + CHF + CVD + PVD + DEMENTIA + COPD + RHEUMDIS + PEPULCER
                    + (CASE WHEN MSVLIVDIS > 0 THEN 0 ELSE MILDLIVDIS END)
                    + (CASE WHEN DIABETES_WTCC > 0 THEN 0 ELSE DIABETES_NOCC END)
                    + DIABETES_WTCC + HEMIPARAPLEG + RENALDIS + CANCER + MSVLIVDIS + METASTATIC + AIDSHIV AS CHARLSON_INDEX,
                MI, CHF, CVD, PVD, DEMENTIA, COPD, RHEUMDIS, PEPULCER, MILDLIVDIS, DIABETES_NOCC, DIABETES_WTCC, HEMIPARAPLEG, RENALDIS, CANCER, MSVLIVDIS, METASTATIC, AIDSHIV
            FROM (
            SELECT COHORT_NAME, PATIENT_NUM, SEX, AGE, LAST_VISIT, CHARLSON_AGE_BASE
              , MAX(CASE WHEN CHARLSON_CATGRY = 'MI'            THEN CHARLSON_WT ELSE 0 END) AS MI
              , MAX(CASE WHEN CHARLSON_CATGRY = 'CHF'           THEN CHARLSON_WT ELSE 0 END) AS CHF
              , MAX(CASE WHEN CHARLSON_CATGRY = 'CVD'           THEN CHARLSON_WT ELSE 0 END) AS CVD
              , MAX(CASE WHEN CHARLSON_CATGRY = 'PVD'           THEN CHARLSON_WT ELSE 0 END) AS PVD
              , MAX(CASE WHEN CHARLSON_CATGRY = 'DEMENTIA'      THEN CHARLSON_WT ELSE 0 END) AS DEMENTIA
              , MAX(CASE WHEN CHARLSON_CATGRY = 'COPD'          THEN CHARLSON_WT ELSE 0 END) AS COPD
              , MAX(CASE WHEN CHARLSON_CATGRY = 'RHEUMDIS'      THEN CHARLSON_WT ELSE 0 END) AS RHEUMDIS
              , MAX(CASE WHEN CHARLSON_CATGRY = 'PEPULCER'      THEN CHARLSON_WT ELSE 0 END) AS PEPULCER
              , MAX(CASE WHEN CHARLSON_CATGRY = 'MILDLIVDIS'    THEN CHARLSON_WT ELSE 0 END) AS MILDLIVDIS
              , MAX(CASE WHEN CHARLSON_CATGRY = 'DIABETES_NOCC' THEN CHARLSON_WT ELSE 0 END) AS DIABETES_NOCC
              , MAX(CASE WHEN CHARLSON_CATGRY = 'DIABETES_WTCC' THEN CHARLSON_WT ELSE 0 END) AS DIABETES_WTCC
              , MAX(CASE WHEN CHARLSON_CATGRY = 'HEMIPARAPLEG'  THEN CHARLSON_WT ELSE 0 END) AS HEMIPARAPLEG
              , MAX(CASE WHEN CHARLSON_CATGRY = 'RENALDIS'      THEN CHARLSON_WT ELSE 0 END) AS RENALDIS
              , MAX(CASE WHEN CHARLSON_CATGRY = 'CANCER'        THEN CHARLSON_WT ELSE 0 END) AS CANCER
              , MAX(CASE WHEN CHARLSON_CATGRY = 'MSVLIVDIS'     THEN CHARLSON_WT ELSE 0 END) AS MSVLIVDIS
              , MAX(CASE WHEN CHARLSON_CATGRY = 'METASTATIC'    THEN CHARLSON_WT ELSE 0 END) AS METASTATIC
              , MAX(CASE WHEN CHARLSON_CATGRY = 'AIDSHIV'       THEN CHARLSON_WT ELSE 0 END) AS AIDSHIV
            FROM (
              -- FOR EACH VISIT - PULL PREVIOUS YEAR OF DIAGNOSIS FACTS JOINED TO CHARLSON CATEGORIES - EXTRACTING CHARLSON CATGRY/WT
              SELECT COHORT_NAME, O.PATIENT_NUM, O.SEX, O.AGE, O.LAST_VISIT, O.CHARLSON_AGE_BASE, C.CHARLSON_CATGRY, C.CHARLSON_WT
              FROM (SELECT DISTINCT COHORT_NAME, F.PATIENT_NUM, CONCEPT_CD, V.SEX, V.AGE, V.LAST_VISIT, V.CHARLSON_AGE_BASE
                    FROM OBSERVATION_FACT F
                      INNER JOIN DT_TMP_CHARLSON_VISIT_BASE V
                        ON F.PATIENT_NUM = V.PATIENT_NUM
                            AND F.START_DATE >= add_months(V.LAST_VISIT, -12) AND F.START_DATE < V.LAST_VISIT + 1  -- CHARLSON IS TYPICALLY CALCULATED ON THE PREVIOUS YEAR - DEPENDING ON HOW THE COHORT IS DEFINED THIS MAY NOT EQUAL INDEX_DT
                   )O
                INNER JOIN DT_TMP_CHARLSON_DX C
                  ON O.CONCEPT_CD = C.CONCEPT_CD
              GROUP BY COHORT_NAME, O.PATIENT_NUM, O.SEX, O.AGE, O.LAST_VISIT, O.CHARLSON_AGE_BASE, C.CHARLSON_CATGRY, C.CHARLSON_WT
              UNION -- IF NO CHARLSON DX FOUND IN ABOVE INNER JOINS WE CAN UNION TO JUST THE ENCOUNTER+AGE_BASE RECORD WITH CHARLSON FIELDS NULLED OUT
            --            THIS IS MORE PERFORMANT (SHORTCUT) THAN A LEFT JOIN IN THE OBSERVATION-CHARLSON INNER JOIN ABOVE
              SELECT COHORT_NAME, V2.PATIENT_NUM, V2.SEX, V2.AGE, V2.LAST_VISIT, V2.CHARLSON_AGE_BASE, NULL, NULL
              FROM DT_TMP_CHARLSON_VISIT_BASE V2
              )DXU
              GROUP BY COHORT_NAME, PATIENT_NUM, SEX, AGE, LAST_VISIT, CHARLSON_AGE_BASE
            )CCI
        )CCISUM;

    V_ROWS := SQL%ROWCOUNT;
    V_ENDRUNTIME_MS := EXTRACT (DAY FROM (LOCALTIMESTAMP - V_START_TS))*24*60*60 +
        EXTRACT (HOUR FROM (LOCALTIMESTAMP - V_START_TS))*60*60+
        EXTRACT (MINUTE FROM (LOCALTIMESTAMP - V_START_TS))*60+
        ROUND(EXTRACT(SECOND FROM (LOCALTIMESTAMP - V_START_TS))*1000);
    V_STEPRUNTIME_MS := EXTRACT (DAY FROM (LOCALTIMESTAMP - V_STEP_TS))*24*60*60 +
        EXTRACT (HOUR FROM (LOCALTIMESTAMP - V_STEP_TS))*60*60+
        EXTRACT (MINUTE FROM (LOCALTIMESTAMP - V_STEP_TS))*60+
        ROUND(EXTRACT(SECOND FROM (LOCALTIMESTAMP - V_STEP_TS))*1000);
    DBMS_OUTPUT.PUT_LINE('Charlson Index and weighted flags - Rows: ' || TO_CHAR(v_rows) || '- Total Execution (ms)' || TO_CHAR(v_endruntime_ms) || ' - Step Runtime (ms): ' || TO_CHAR(v_stepruntime_ms));

    SELECT COUNT(*) INTO V_CHARLSON_FLAG_PATIENTS
    FROM DT_TMP_COHORT_CHARLSON
    WHERE MI + CHF + CVD + PVD + DEMENTIA + COPD + RHEUMDIS + PEPULCER
        + MILDLIVDIS + DIABETES_NOCC + DIABETES_WTCC + HEMIPARAPLEG
        + RENALDIS + CANCER + MSVLIVDIS + METASTATIC + AIDSHIV > 0;

    DBMS_OUTPUT.PUT_LINE('Charlson diagnosis matches - Patients with one or more feature flags: ' ||
        TO_CHAR(V_CHARLSON_FLAG_PATIENTS));

    -- CHARLSON 10YR PROB MEDIAN/MEAN/MODE/STDEV
    V_STEP_TS := LOCALTIMESTAMP;

    -- UNFILTERED BY PSC
    INSERT INTO DT_TMP_CHARLSON_STATS
    WITH
        CTE_MODE AS (
            SELECT COHORT_NAME, nvl(A.AGE_GRP,'ALL PATIENTS') AGE_GRP
              , CHARLSON_10YR_PROB
              , RANK() OVER (PARTITION BY COHORT_NAME, nvl(A.AGE_GRP,'ALL PATIENTS') ORDER BY N DESC) MR_AG
            FROM (
                    SELECT COHORT_NAME, AGE_GRP, CHARLSON_10YR_PROB, COUNT(*) N
                    FROM DT_TMP_COHORT_CHARLSON
                    GROUP BY GROUPING SETS ((COHORT_NAME, AGE_GRP, CHARLSON_10YR_PROB),(COHORT_NAME, CHARLSON_10YR_PROB))
                )A
            GROUP BY COHORT_NAME, nvl(A.AGE_GRP,'ALL PATIENTS'), CHARLSON_10YR_PROB, N
        ),
        CTE_MEAN_STDEV_MODE AS (
            SELECT GS.COHORT_NAME, nvl(GS.AGE_GRP,'ALL PATIENTS') AGE_GRP, MEAN_10YR_PROB, STDEV_10YR_PROB
                , AVG(CHARLSON_10YR_PROB) AS MODE_10YR_PROB -- ONLY MEANINGFUL WHEN THERE IS A TIE FOR MODE
            FROM (
                    SELECT COHORT_NAME, AGE_GRP, AVG(CHARLSON_10YR_PROB) MEAN_10YR_PROB, STDDEV(CHARLSON_10YR_PROB) STDEV_10YR_PROB
                    FROM DT_TMP_COHORT_CHARLSON
                    GROUP BY GROUPING SETS ((COHORT_NAME, AGE_GRP),(COHORT_NAME))
                )GS
                INNER JOIN CTE_MODE M ON GS.COHORT_NAME = M.COHORT_NAME AND nvl(GS.AGE_GRP,'ALL PATIENTS') = M.AGE_GRP AND M.MR_AG = 1
            GROUP BY GS.COHORT_NAME, nvl(GS.AGE_GRP,'ALL PATIENTS'), MEAN_10YR_PROB, STDEV_10YR_PROB
        )
    SELECT MS.COHORT_NAME, MS.AGE_GRP
        , CAST('N' AS CHAR(1)) CUTOFF_FILTER_YN
        , MEDIAN_10YR_PROB
        , S.MEAN_10YR_PROB
        , S.STDEV_10YR_PROB
        , S.MODE_10YR_PROB
    FROM (
            SELECT COHORT_NAME, AGE_GRP, CHARLSON_10YR_PROB
                , PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CHARLSON_10YR_PROB) OVER (PARTITION BY COHORT_NAME, AGE_GRP) AS MEDIAN_10YR_PROB
            FROM DT_TMP_COHORT_CHARLSON
            WHERE AGE_GRP != '-'
            UNION ALL
            SELECT COHORT_NAME, 'ALL PATIENTS' as AGE_GRP, CHARLSON_10YR_PROB
                , PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CHARLSON_10YR_PROB) OVER (PARTITION BY COHORT_NAME) AS MEDIAN_10YR_PROB
            FROM DT_TMP_COHORT_CHARLSON
            WHERE AGE_GRP != '-'
        )MS
        INNER JOIN CTE_MEAN_STDEV_MODE S ON MS.AGE_GRP = S.AGE_GRP AND MS.COHORT_NAME = S.COHORT_NAME
    GROUP BY MS.COHORT_NAME, MS.AGE_GRP, MEDIAN_10YR_PROB, S.MODE_10YR_PROB, S.STDEV_10YR_PROB, S.MEAN_10YR_PROB;

    -- FILTERED BY PSC
    INSERT INTO DT_TMP_CHARLSON_STATS(COHORT_NAME, AGE_GRP,CUTOFF_FILTER_YN,MEDIAN_10YR_PROB,MEAN_10YR_PROB,STDEV_10YR_PROB,MODE_10YR_PROB)
    WITH
        CTE_MODE AS (
            SELECT COHORT_NAME
                , AGE_GRP
                , CHARLSON_10YR_PROB
                , RANK() OVER (PARTITION BY COHORT_NAME, nvl(A.AGE_GRP,'ALL PATIENTS') ORDER BY N DESC) MR_AG
            FROM (
                    SELECT CC.COHORT_NAME, C.AGE_GRP, CHARLSON_10YR_PROB, COUNT(*) N
                    FROM DT_TMP_COHORT_CHARLSON CC
                        INNER JOIN DT_TMP_COHORT_AGE_GRP C
                            ON CC.PATIENT_NUM = C.PATIENT_NUM
                                AND CC.COHORT_NAME = C.COHORT_NAME
                        INNER JOIN DT_TMP_AGE_GRP_PSC PSC
                            ON C.AGE_GRP = PSC.AGE_GRP
                                AND C.PREDICTED_SCORE >= PSC.PREDICTIVE_SCORE_CUTOFF
                                AND C.COHORT_NAME = PSC.COHORT_NAME
                    GROUP BY CC.COHORT_NAME, C.AGE_GRP,CHARLSON_10YR_PROB
                )A
            GROUP BY COHORT_NAME, AGE_GRP, CHARLSON_10YR_PROB, N
        ),
        CTE_MEAN_STDEV_MODE AS (
            SELECT GS.COHORT_NAME, nvl(GS.AGE_GRP,'ALL PATIENTS') AS AGE_GRP, MEAN_10YR_PROB, STDEV_10YR_PROB
                , AVG(CHARLSON_10YR_PROB) AS MODE_10YR_PROB
            FROM (
                    SELECT CC.COHORT_NAME, C.AGE_GRP, AVG(CHARLSON_10YR_PROB) MEAN_10YR_PROB, STDDEV(CHARLSON_10YR_PROB) STDEV_10YR_PROB
                    FROM DT_TMP_COHORT_CHARLSON CC
                        INNER JOIN DT_TMP_COHORT_AGE_GRP C
                            ON CC.PATIENT_NUM = C.PATIENT_NUM
                                AND CC.COHORT_NAME = C.COHORT_NAME
                        INNER JOIN DT_TMP_AGE_GRP_PSC PSC
                            ON C.AGE_GRP = PSC.AGE_GRP
                                AND C.PREDICTED_SCORE >= PSC.PREDICTIVE_SCORE_CUTOFF
                                AND C.COHORT_NAME = C.COHORT_NAME
                    GROUP BY CC.COHORT_NAME, C.AGE_GRP
                )GS
                INNER JOIN CTE_MODE M
              ON GS.COHORT_NAME = M.COHORT_NAME
              AND nvl(GS.AGE_GRP,'ALL PATIENTS') = M.AGE_GRP
              AND M.MR_AG = 1
            GROUP BY GS.COHORT_NAME, nvl(GS.AGE_GRP,'ALL PATIENTS'), MEAN_10YR_PROB, STDEV_10YR_PROB
        )
    SELECT MS.COHORT_NAME, MS.AGE_GRP
        , CAST('Y' AS CHAR(1)) AS CUTOFF_FILTER_YN
        , MEDIAN_10YR_PROB
        , S.MEAN_10YR_PROB
        , S.STDEV_10YR_PROB
        , S.MODE_10YR_PROB
    FROM (
            SELECT CC.COHORT_NAME, C.AGE_GRP, CHARLSON_10YR_PROB
                , PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CHARLSON_10YR_PROB) OVER (PARTITION BY CC.COHORT_NAME, C.AGE_GRP) AS MEDIAN_10YR_PROB
            FROM DT_TMP_COHORT_CHARLSON CC
                INNER JOIN DT_TMP_COHORT_AGE_GRP C
                    ON CC.PATIENT_NUM = C.PATIENT_NUM
                        AND CC.COHORT_NAME = C.COHORT_NAME
                INNER JOIN DT_TMP_AGE_GRP_PSC PSC
                    ON C.AGE_GRP = PSC.AGE_GRP
                        AND C.PREDICTED_SCORE >= PSC.PREDICTIVE_SCORE_CUTOFF
                        AND CC.COHORT_NAME = PSC.COHORT_NAME
            WHERE CC.AGE_GRP != '-'
        )MS
        INNER JOIN CTE_MEAN_STDEV_MODE S
            ON MS.AGE_GRP = S.AGE_GRP
                AND MS.COHORT_NAME = S.COHORT_NAME
    GROUP BY MS.COHORT_NAME, MS.AGE_GRP, MEDIAN_10YR_PROB, S.MODE_10YR_PROB, S.STDEV_10YR_PROB, S.MEAN_10YR_PROB;

    V_ROWS := SQL%ROWCOUNT;
    v_endruntime_ms := extract (day from (localtimestamp - v_start_ts))*24*60*60 +
        extract (hour from (localtimestamp - v_start_ts))*60*60+
        extract (minute from (localtimestamp - v_start_ts))*60+
        ROUND(EXTRACT(SECOND FROM (LOCALTIMESTAMP - V_START_TS))*1000);
    v_stepruntime_ms := extract (day from (localtimestamp - v_step_ts))*24*60*60 +
        extract (hour from (localtimestamp - v_step_ts))*60*60+
        extract (minute from (localtimestamp - v_step_ts))*60+
        ROUND(EXTRACT(SECOND FROM (LOCALTIMESTAMP - V_STEP_TS))*1000);
    DBMS_OUTPUT.PUT_LINE('Charlson Stats - Rows: ' || TO_CHAR(v_rows) || '- Total Execution (ms)' || TO_CHAR(v_endruntime_ms) || ' - Step Runtime (ms): ' || TO_CHAR(v_stepruntime_ms));

    -- FINAL SUMMARIZATION OF RESULTS
    -- clear out last run of lookback
    DELETE FROM DT_LOYALTY_RESULT_SUMMARY
    WHERE LOOKBACK_YR = p_lookback_years
        AND GENDER_DENOMINATORS_YN = v_gender_yn
        AND SITE = p_site
        AND COHORT_NAME IN (SELECT COHORT_NAME FROM DT_TMP_COHORT_FILTER);

    -- FINAL SUMMARIZATION OF RESULTS
    V_STEP_TS := LOCALTIMESTAMP;

    INSERT INTO DT_LOYALTY_RESULT_SUMMARY (COHORT_NAME, SITE, LOOKBACK_YR, GENDER_DENOMINATORS_YN, CUTOFF_FILTER_YN, SUMMARY_DESCRIPTION, TABLE_NAME, NUM_DX1, NUM_DX2, MED_USE1, MED_USE2
        , MAMMOGRAPHY, PAP_TEST, PSA_TEST, COLONOSCOPY, FECAL_OCCULT_TEST, FLU_SHOT, PNEUMOCOCCAL_VACCINE, BMI, A1C, MEDICAL_EXAM, INP1_OPT1_VISIT, OPT2_VISIT, ED_VISIT
        , MDVISIT_PNAME2, MDVISIT_PNAME3, ROUTINE_CARE_2, SUBJECTS_NOCRITERIA, PREDICTIVE_SCORE_CUTOFF
        , MEAN_10YR_PROB, MEDIAN_10YR_PROB, MODE_10YR_PROB, STDEV_10YR_PROB, TOTAL_SUBJECTS
        , TOTAL_SUBJECTS_FEMALE, TOTAL_SUBJECTS_MALE, PERCENT_SUBJECTS_FEMALE, PERCENT_SUBJECTS_MALE, AVERAGE_FACT_COUNT)
    SELECT DISTINCT COHORTAGG.COHORT_NAME, p_site, p_lookback_years,
        v_gender_yn as GENDER_DENOMINATORS_YN, COHORTAGG.CUTOFF_FILTER_YN,
        SUMMARY_DESCRIPTION, COHORTAGG.AGE_GRP as TABLE_NAME,
        NUM_DX1, NUM_DX2, MED_USE1, MED_USE2, MAMMOGRAPHY,
        PAP_TEST, PSA_TEST, COLONOSCOPY, FECAL_OCCULT_TEST,
        FLU_SHOT, PNEUMOCOCCAL_VACCINE, BMI, A1C, MEDICAL_EXAM,
        INP1_OPT1_VISIT, OPT2_VISIT, ED_VISIT, MDVISIT_PNAME2,
        MDVISIT_PNAME3, Routine_care_2, SUBJECTS_NOCRITERIA,
        CASE WHEN COHORTAGG.CUTOFF_FILTER_YN = 'Y' THEN CP.PREDICTIVE_SCORE_CUTOFF ELSE NULL END AS PREDICTIVE_SCORE_CUTOFF,
        CS.MEAN_10YR_PROB, CS.MEDIAN_10YR_PROB, CS.MODE_10YR_PROB,
        CS.STDEV_10YR_PROB, TOTAL_SUBJECTS, TOTAL_SUBJECTS_FEMALE,
        TOTAL_SUBJECTS_MALE, PERCENT_SUBJECTS_FEMALE, PERCENT_SUBJECTS_MALE,
        0 --FC.AVG_FACT_COUNT as AVERAGE_FACT_COUNT
    FROM (
            -- FILTERED BY PREDICTIVE CUTOFF
            SELECT CAG.COHORT_NAME,
                'Y' AS CUTOFF_FILTER_YN,
                'PATIENT COUNTS' as SUMMARY_DESCRIPTION,
                CAG.AGE_GRP,
                COUNT(PATIENT_NUM) AS TOTAL_SUBJECTS,
                SUM(CAST(NUM_DX1 AS INT)) AS NUM_DX1,
                SUM(CAST(NUM_DX2 AS INT)) AS NUM_DX2,
                SUM(CAST(MED_USE1 AS INT))  AS MED_USE1,
                SUM(CAST(MED_USE2 AS INT)) AS MED_USE2,
                SUM(CAST(case when p_gendered=0 or SEX='F' then MAMMOGRAPHY else NULL end AS INT)) AS MAMMOGRAPHY,
                SUM(CAST(case when p_gendered=0 or SEX='F' then PAP_TEST else NULL end AS INT)) AS PAP_TEST,
                SUM(CAST(case when p_gendered=0 or SEX='M' then PSA_TEST else NULL end AS INT)) AS PSA_TEST,
                SUM(CAST(COLONOSCOPY AS INT)) AS COLONOSCOPY,
                SUM(CAST(FECAL_OCCULT_TEST AS INT)) AS FECAL_OCCULT_TEST,
                SUM(CAST(FLU_SHOT AS INT)) AS  FLU_SHOT,
                SUM(CAST(PNEUMOCOCCAL_VACCINE AS INT)) AS PNEUMOCOCCAL_VACCINE,
                SUM(CAST(BMI AS INT))  AS BMI,
                SUM(CAST(A1C AS INT)) AS A1C,
                SUM(CAST(MEDICAL_EXAM AS INT)) AS MEDICAL_EXAM,
                SUM(CAST(INP1_OPT1_VISIT AS INT)) AS INP1_OPT1_VISIT,
                SUM(CAST(OPT2_VISIT AS INT)) AS OPT2_VISIT,
                SUM(CAST(ED_VISIT AS INT))  AS ED_VISIT,
                SUM(CAST(MDVISIT_PNAME2 AS INT)) AS MDVISIT_PNAME2,
                SUM(CAST(MDVISIT_PNAME3 AS INT)) AS MDVISIT_PNAME3,
                SUM(CAST(ROUTINE_CARE_2 AS INT)) AS ROUTINE_CARE_2,
                sum(case when NUM_DX1+NUM_DX2+MED_USE1+MAMMOGRAPHY+PAP_TEST+PSA_TEST+COLONOSCOPY+FECAL_OCCULT_TEST+FLU_SHOT+PNEUMOCOCCAL_VACCINE+BMI+
                  A1C+MEDICAL_EXAM+INP1_OPT1_VISIT+OPT2_VISIT+ED_VISIT+MDVISIT_PNAME2+MDVISIT_PNAME3+ROUTINE_CARE_2 > 0 then 0 else 1 end) as SUBJECTS_NOCRITERIA, -- inverted bitwise OR of all bit flags
                SUM(case when SEX='F' then 1.0 else 0.0 end) AS TOTAL_SUBJECTS_FEMALE,
                SUM(case when SEX='M' then 1.0 else 0.0 end) AS TOTAL_SUBJECTS_MALE,
                NULL AS PERCENT_SUBJECTS_FEMALE,
                NULL AS PERCENT_SUBJECTS_MALE
            FROM DT_TMP_COHORT_AGE_GRP CAG
                INNER JOIN DT_TMP_AGE_GRP_PSC P
                    ON CAG.AGE_GRP = P.AGE_GRP
                        AND CAG.PREDICTED_SCORE >= P.PREDICTIVE_SCORE_CUTOFF
                        AND CAG.COHORT_NAME = P.COHORT_NAME
            GROUP BY CAG.COHORT_NAME, CAG.AGE_GRP
            UNION ALL
            SELECT CAG.COHORT_NAME,
                'Y' AS CUTOFF_FILTER_YN,
                'PERCENT SUBJECTS' as SUMMARY_DESCRIPTION,
                CAG.AGE_GRP,
                COUNT(PATIENT_NUM) as TOTAL_SUBJECTS,
                100*AVG(CAST(NUM_DX1 as NUMERIC(2,1))) as NUM_DX1,
                100*AVG(CAST(NUM_DX2 as NUMERIC(2,1))) as NUM_DX2,
                100*AVG(CAST(MED_USE1 as NUMERIC(2,1)))  as MED_USE1,
                100*AVG(CAST(MED_USE2 as NUMERIC(2,1))) as MED_USE2,
                100*AVG(CAST(case when p_gendered=0 or SEX='F' then MAMMOGRAPHY else null end AS NUMERIC(2,1))) as MAMMOGRAPHY,
                100*AVG(CAST(case when p_gendered=0 or SEX='F' then PAP_TEST else null end AS NUMERIC(2,1))) as PAP_TEST,
                100*AVG(CAST(case when p_gendered=0 or SEX='M' then PSA_TEST else null end AS NUMERIC(2,1))) as PSA_TEST,
                100*AVG(CAST(COLONOSCOPY as NUMERIC(2,1))) as COLONOSCOPY,
                100*AVG(CAST(FECAL_OCCULT_TEST as NUMERIC(2,1))) as FECAL_OCCULT_TEST,
                100*AVG(CAST(FLU_SHOT as NUMERIC(2,1))) as  FLU_SHOT,
                100*AVG(CAST(PNEUMOCOCCAL_VACCINE as NUMERIC(2,1))) as PNEUMOCOCCAL_VACCINE,
                100*AVG(CAST(BMI as NUMERIC(2,1)))  as BMI,
                100*AVG(CAST(A1C as NUMERIC(2,1))) as A1C,
                100*AVG(CAST(MEDICAL_EXAM as NUMERIC(2,1))) as MEDICAL_EXAM,
                100*AVG(CAST(INP1_OPT1_VISIT as NUMERIC(2,1))) as INP1_OPT1_VISIT,
                100*AVG(CAST(OPT2_VISIT as NUMERIC(2,1))) as OPT2_VISIT,
                100*AVG(CAST(ED_VISIT as NUMERIC(2,1)))  as ED_VISIT,
                100*AVG(CAST(MDVISIT_PNAME2 as NUMERIC(2,1))) as MDVISIT_PNAME2,
                100*AVG(CAST(MDVISIT_PNAME3 as NUMERIC(2,1))) as MDVISIT_PNAME3,
                100*AVG(CAST(ROUTINE_CARE_2 as NUMERIC(2,1))) as Routine_care_2,
                100*avg(case when NUM_DX1+NUM_DX2+MED_USE1+MAMMOGRAPHY+PAP_TEST+PSA_TEST+COLONOSCOPY+FECAL_OCCULT_TEST+FLU_SHOT+PNEUMOCOCCAL_VACCINE+BMI+
                    A1C+MEDICAL_EXAM+INP1_OPT1_VISIT+OPT2_VISIT+ED_VISIT+MDVISIT_PNAME2+MDVISIT_PNAME3+ROUTINE_CARE_2 > 0 then 0 else 1 end) as SUBJECTS_NOCRITERIA, -- inverted bitwise OR of all bit flags
                NULL AS TOTAL_SUBJECTS_FEMALE,
                NULL AS TOTAL_SUBJECTS_MALE,
                100*AVG(case when SEX='F' then 1.0 else 0.0 end) AS PERCENT_SUBJECTS_FEMALE,
                100*AVG(case when SEX='M' then 1.0 else 0.0 end) AS PERCENT_SUBJECTS_MALE
            FROM DT_TMP_COHORT_AGE_GRP CAG
                INNER JOIN DT_TMP_AGE_GRP_PSC P
                    ON CAG.AGE_GRP = P.AGE_GRP
                    AND CAG.PREDICTED_SCORE >= P.PREDICTIVE_SCORE_CUTOFF
                    AND CAG.COHORT_NAME = P.COHORT_NAME
            GROUP BY CAG.COHORT_NAME, CAG.AGE_GRP
            UNION ALL
            -- UNFILTERED -- ALL QUINTILES
            SELECT CAG.COHORT_NAME,
                'N' AS CUTOFF_FILTER_YN,
                'PATIENT COUNTS' as SUMMARY_DESCRIPTION,
                CAG.AGE_GRP,
                COUNT(PATIENT_NUM) as TOTAL_SUBJECTS,
                SUM(CAST(NUM_DX1 as int)) as NUM_DX1,
                SUM(CAST(NUM_DX2 as int)) as NUM_DX2,
                SUM(CAST(MED_USE1 as int))  as MED_USE1,
                SUM(CAST(MED_USE2 as int)) as MED_USE2,
                SUM(CAST(case when p_gendered=0 or SEX='F' then MAMMOGRAPHY else null end as int)) as MAMMOGRAPHY,
                SUM(CAST(case when p_gendered=0 or SEX='F' then PAP_TEST else null end as int)) as PAP_TEST,
                SUM(CAST(case when p_gendered=0 or SEX='M' then PSA_TEST else null end as int)) as PSA_TEST,
                SUM(CAST(COLONOSCOPY as int)) as COLONOSCOPY,
                SUM(CAST(FECAL_OCCULT_TEST as int)) as FECAL_OCCULT_TEST,
                SUM(CAST(FLU_SHOT as int)) as  FLU_SHOT,
                SUM(CAST(PNEUMOCOCCAL_VACCINE as int)) as PNEUMOCOCCAL_VACCINE,
                SUM(CAST(BMI as int))  as BMI,
                SUM(CAST(A1C as int)) as A1C,
                SUM(CAST(MEDICAL_EXAM as int)) as MEDICAL_EXAM,
                SUM(CAST(INP1_OPT1_VISIT as int)) as INP1_OPT1_VISIT,
                SUM(CAST(OPT2_VISIT as int)) as OPT2_VISIT,
                SUM(CAST(ED_VISIT as int))  as ED_VISIT,
                SUM(CAST(MDVISIT_PNAME2 as int)) as MDVISIT_PNAME2,
                SUM(CAST(MDVISIT_PNAME3 as int)) as MDVISIT_PNAME3,
                SUM(CAST(ROUTINE_CARE_2 as int)) as Routine_care_2,
                sum(case when NUM_DX1+NUM_DX2+MED_USE1+MAMMOGRAPHY+PAP_TEST+PSA_TEST+COLONOSCOPY+FECAL_OCCULT_TEST+FLU_SHOT+PNEUMOCOCCAL_VACCINE+BMI+
                    A1C+MEDICAL_EXAM+INP1_OPT1_VISIT+OPT2_VISIT+ED_VISIT+MDVISIT_PNAME2+MDVISIT_PNAME3+ROUTINE_CARE_2 > 0 then 0 else 1 end) as SUBJECTS_NOCRITERIA, -- inverted bitwise OR of all bit flags
                SUM(case when SEX='F' then 1.0 else 0.0 end) AS TOTAL_SUBJECTS_FEMALE,
                SUM(case when SEX='M' then 1.0 else 0.0 end) AS TOTAL_SUBJECTS_MALE,
                NULL AS PERCENT_SUBJECTS_FEMALE,
                NULL AS PERCENT_SUBJECTS_MALE
                FROM DT_TMP_COHORT_AGE_GRP CAG
                GROUP BY CAG.COHORT_NAME, CAG.AGE_GRP
                UNION ALL
                SELECT CAG.COHORT_NAME,
                'N' AS PREDICTIVE_CUTOFF_FILTER_YN,
                'PERCENT SUBJECTS' as SUMMARY_DESCRIPTION,
                CAG.AGE_GRP,
                COUNT(PATIENT_NUM) as TOTAL_SUBJECTS,
                100*AVG(CAST(NUM_DX1 as NUMERIC(2,1))) as NUM_DX1,
                100*AVG(CAST(NUM_DX2 as NUMERIC(2,1))) as NUM_DX2,
                100*AVG(CAST(MED_USE1 as NUMERIC(2,1)))  as MED_USE1,
                100*AVG(CAST(MED_USE2 as NUMERIC(2,1))) as MED_USE2,
                100*AVG(CAST(case when p_gendered=0 or SEX='F' then MAMMOGRAPHY else NULL end AS NUMERIC(2,1))) as MAMMOGRAPHY,
                100*AVG(CAST(case when p_gendered=0 or SEX='F' then PAP_TEST else NULL end AS NUMERIC(2,1))) as PAP_TEST,
                100*AVG(CAST(case when p_gendered=0 or SEX='M' then PSA_TEST else NULL end AS NUMERIC(2,1))) as PSA_TEST,
                100*AVG(CAST(COLONOSCOPY as NUMERIC(2,1))) as COLONOSCOPY,
                100*AVG(CAST(FECAL_OCCULT_TEST as NUMERIC(2,1))) as FECAL_OCCULT_TEST,
                100*AVG(CAST(FLU_SHOT as NUMERIC(2,1))) as  FLU_SHOT,
                100*AVG(CAST(PNEUMOCOCCAL_VACCINE as NUMERIC(2,1))) as PNEUMOCOCCAL_VACCINE,
                100*AVG(CAST(BMI as NUMERIC(2,1)))  as BMI,
                100*AVG(CAST(A1C as NUMERIC(2,1))) as A1C,
                100*AVG(CAST(MEDICAL_EXAM as NUMERIC(2,1))) as MEDICAL_EXAM,
                100*AVG(CAST(INP1_OPT1_VISIT as NUMERIC(2,1))) as INP1_OPT1_VISIT,
                100*AVG(CAST(OPT2_VISIT as NUMERIC(2,1))) as OPT2_VISIT,
                100*AVG(CAST(ED_VISIT as NUMERIC(2,1))) as ED_VISIT,
                100*AVG(CAST(MDVISIT_PNAME2 as NUMERIC(2,1))) as MDVISIT_PNAME2,
                100*AVG(CAST(MDVISIT_PNAME3 as NUMERIC(2,1))) as MDVISIT_PNAME3,
                100*AVG(CAST(ROUTINE_CARE_2 as NUMERIC(2,1))) as Routine_care_2,
                100*avg(case when NUM_DX1+NUM_DX2+MED_USE1+MAMMOGRAPHY+PAP_TEST+PSA_TEST+COLONOSCOPY+FECAL_OCCULT_TEST+FLU_SHOT+PNEUMOCOCCAL_VACCINE+BMI+
                    A1C+MEDICAL_EXAM+INP1_OPT1_VISIT+OPT2_VISIT+ED_VISIT+MDVISIT_PNAME2+MDVISIT_PNAME3+ROUTINE_CARE_2 > 0 then 0 else 1 end) as SUBJECTS_NOCRITERIA, -- inverted bitwise OR of all bit flags
                NULL AS TOTAL_SUBJECTS_FEMALE,
                NULL AS TOTAL_SUBJECTS_MALE,
                100*AVG(case when SEX='F' then 1.0 else 0.0 end) AS PERCENT_SUBJECTS_FEMALE,
                100*AVG(case when SEX='M' then 1.0 else 0.0 end) AS PERCENT_SUBJECTS_MALE
            FROM DT_TMP_COHORT_AGE_GRP CAG
            GROUP BY CAG.COHORT_NAME, CAG.AGE_GRP
        ) COHORTAGG
        INNER JOIN DT_TMP_AGE_GRP_PSC CP
            ON COHORTAGG.AGE_GRP = CP.AGE_GRP
            AND COHORTAGG.COHORT_NAME = CP.COHORT_NAME
        INNER JOIN DT_TMP_CHARLSON_STATS CS
            ON COHORTAGG.AGE_GRP = CS.AGE_GRP
                AND COHORTAGG.CUTOFF_FILTER_YN = CS.CUTOFF_FILTER_YN
                AND COHORTAGG.COHORT_NAME = CS.COHORT_NAME;

    V_ROWS := SQL%ROWCOUNT;
    V_ENDRUNTIME_MS := EXTRACT (DAY FROM (LOCALTIMESTAMP - V_START_TS))*24*60*60 +
        EXTRACT (HOUR FROM (LOCALTIMESTAMP - V_START_TS))*60*60+
        EXTRACT (MINUTE FROM (LOCALTIMESTAMP - V_START_TS))*60+
        ROUND(EXTRACT(SECOND FROM (LOCALTIMESTAMP - V_START_TS))*1000);
    V_STEPRUNTIME_MS := EXTRACT (DAY FROM (LOCALTIMESTAMP - V_STEP_TS))*24*60*60 +
        EXTRACT (HOUR FROM (LOCALTIMESTAMP - V_STEP_TS))*60*60+
        EXTRACT (MINUTE FROM (LOCALTIMESTAMP - V_STEP_TS))*60+
        ROUND(EXTRACT(SECOND FROM (LOCALTIMESTAMP - V_STEP_TS))*1000);
    DBMS_OUTPUT.PUT_LINE('Final Summary Table - Rows: ' || TO_CHAR(v_rows) || '- Total Execution (ms)' || TO_CHAR(v_endruntime_ms) || ' - Step Runtime (ms): ' || TO_CHAR(v_stepruntime_ms));

    -- Populate slice PERCENT_POPULATION
    UPDATE DT_LOYALTY_RESULT_SUMMARY LDS
    SET PERCENT_POPULATION = (
        with
            PERC_POPULATION as (
                select LDS.COHORT_NAME, LDS.LOOKBACK_YR, LDS.GENDER_DENOMINATORS_YN, LDS.CUTOFF_FILTER_YN, LDS.TABLE_NAME,
                    100 * CASE
                        WHEN TABLE_NAME = 'ALL PATIENTS' THEN 1.0
                        WHEN TABLE_NAME = 'OVER 65' THEN 1.0*TOTAL_SUBJECTS/LAG(TOTAL_SUBJECTS,1,NULL) OVER (ORDER BY LDS.COHORT_NAME, LDS.LOOKBACK_YR, LDS.GENDER_DENOMINATORS_YN, LDS.CUTOFF_FILTER_YN, LDS.TABLE_NAME)
                        WHEN TABLE_NAME = 'UNDER 65' THEN 1.0*TOTAL_SUBJECTS/LAG(TOTAL_SUBJECTS,2,NULL) OVER (ORDER BY LDS.COHORT_NAME, LDS.LOOKBACK_YR, LDS.GENDER_DENOMINATORS_YN, LDS.CUTOFF_FILTER_YN, LDS.TABLE_NAME)
                    END as PercPopulation
                FROM DT_LOYALTY_RESULT_SUMMARY LDS
                WHERE LDS.SUMMARY_DESCRIPTION = 'PERCENT SUBJECTS'
                    AND LDS.LOOKBACK_YR = p_lookback_years
                    AND LDS.GENDER_DENOMINATORS_YN =  v_gender_yn
                    AND LDS.SITE = p_site
                    AND LDS.COHORT_NAME IN (SELECT COHORT_NAME FROM DT_TMP_COHORT_FILTER)
            )
        SELECT P.PERCPOPULATION
        FROM PERC_POPULATION P
        where LDS.LOOKBACK_YR = P.LOOKBACK_YR
            AND LDS.GENDER_DENOMINATORS_YN = P.GENDER_DENOMINATORS_YN
            AND LDS.CUTOFF_FILTER_YN = P.CUTOFF_FILTER_YN
            AND LDS.COHORT_NAME = P.COHORT_NAME
            AND LDS.TABLE_NAME = P.TABLE_NAME
    )
    WHERE LDS.SUMMARY_DESCRIPTION = 'PERCENT SUBJECTS'
        AND LDS.LOOKBACK_YR = p_lookback_years
        AND LDS.GENDER_DENOMINATORS_YN =  v_gender_yn
        AND LDS.SITE = p_site
        AND LDS.COHORT_NAME IN (SELECT COHORT_NAME FROM DT_TMP_COHORT_FILTER);

    -- AFTER PERCENT_POPULATION is calculated the 'PERCENT SUBJECTS' records should no longer store the TOTAL_SUBJECTS value - to prevent accidental sharing of this datapoint
    UPDATE DT_LOYALTY_RESULT_SUMMARY
    SET TOTAL_SUBJECTS = NULL
    WHERE SUMMARY_DESCRIPTION = 'PERCENT SUBJECTS'
        AND LOOKBACK_YR = p_lookback_years
        AND GENDER_DENOMINATORS_YN =  v_gender_yn
        AND SITE = p_site
        AND COHORT_NAME IN (SELECT COHORT_NAME FROM DT_TMP_COHORT_FILTER);

    -- CALCULATE THE SLICE RUNTIME AND ADD IT TO THE SUMMARY TABLE
    UPDATE DT_LOYALTY_RESULT_SUMMARY
    SET RUNTIME_MS = v_endruntime_ms
    where
        LOOKBACK_YR = p_lookback_years
        AND SITE = p_site
        AND GENDER_DENOMINATORS_YN = v_gender_yn
        AND COHORT_NAME IN (SELECT COHORT_NAME FROM DT_TMP_COHORT_FILTER);

    V_STEP_TS := LOCALTIMESTAMP;

    -- jgk 8/4/21: Expose the cohort tables for analytics. Keep in mind it is fairly large.
    DELETE FROM DT_LOYALTY_RESULT
    WHERE LOOKBACK_YEARS = p_lookback_years
        AND GENDER_DENOMINATORS_YN = v_gender_yn
        AND SITE = p_site
        AND COHORT_NAME IN (SELECT COHORT_NAME FROM DT_TMP_COHORT_FILTER);

    INSERT INTO DT_LOYALTY_RESULT (LOOKBACK_YEARS, GENDER_DENOMINATORS_YN, SITE, COHORT_NAME, PATIENT_NUM, DEATH_DT, INDEX_DT, SEX, AGE, AGE_GRP, NUM_DX1, NUM_DX2, MED_USE1, MED_USE2, MAMMOGRAPHY, PAP_TEST, PSA_TEST, COLONOSCOPY, FECAL_OCCULT_TEST, FLU_SHOT, PNEUMOCOCCAL_VACCINE, BMI, A1C, MEDICAL_EXAM, INP1_OPT1_VISIT, OPT2_VISIT, ED_VISIT, MDVISIT_PNAME2, MDVISIT_PNAME3, ROUTINE_CARE_2, PREDICTED_SCORE)
    select p_lookback_years as LOOKBACK_YEARS, v_gender_yn AS GENDER_DENOMINATORS_YN, SITE, COHORT_NAME, PATIENT_NUM, DEATH_DT, INDEX_DT, SEX, AGE, AGE_GRP, NUM_DX1, NUM_DX2, MED_USE1, MED_USE2, MAMMOGRAPHY, PAP_TEST, PSA_TEST, COLONOSCOPY, FECAL_OCCULT_TEST, FLU_SHOT, PNEUMOCOCCAL_VACCINE, BMI, A1C, MEDICAL_EXAM, INP1_OPT1_VISIT, OPT2_VISIT, ED_VISIT, MDVISIT_PNAME2, MDVISIT_PNAME3, ROUTINE_CARE_2, PREDICTED_SCORE
    FROM DT_TMP_COHORT_AGE_GRP C
    WHERE AGE_GRP != 'ALL PATIENTS'; -- DROP OUT THE ALL PATIENTS DUPLICATES PRESENT IN AGE_GRP PARTITIONS

    DELETE FROM DT_LOYALTY_RESULT_CHARLSON
    WHERE LOOKBACK_YEARS = p_lookback_years
        AND GENDER_DENOMINATORS_YN = v_gender_yn
        AND SITE = p_site
        AND COHORT_NAME IN (SELECT COHORT_NAME FROM DT_TMP_COHORT_FILTER);

    INSERT INTO DT_LOYALTY_RESULT_CHARLSON (LOOKBACK_YEARS, GENDER_DENOMINATORS_YN,  SITE, COHORT_NAME, PATIENT_NUM, DEATH_DT, LAST_VISIT, SEX, AGE, AGE_GRP, CHARLSON_INDEX, CHARLSON_10YR_PROB, MI, CHF, CVD, PVD, DEMENTIA, COPD, RHEUMDIS, PEPULCER, MILDLIVDIS, DIABETES_NOCC, DIABETES_WTCC, HEMIPARAPLEG, RENALDIS, CANCER, MSVLIVDIS, METASTATIC, AIDSHIV)
    SELECT DISTINCT p_lookback_years as LOOKBACK_YEARS, v_gender_yn, p_site, CC.COHORT_NAME, CC.PATIENT_NUM, C.DEATH_DT, CC.LAST_VISIT, CC.SEX, CC.AGE, AGE_GRP, CHARLSON_INDEX, CHARLSON_10YR_PROB, MI, CHF, CVD, PVD, DEMENTIA, COPD, RHEUMDIS, PEPULCER, MILDLIVDIS, DIABETES_NOCC, DIABETES_WTCC, HEMIPARAPLEG, RENALDIS, CANCER, MSVLIVDIS, METASTATIC, AIDSHIV
    FROM DT_TMP_COHORT_CHARLSON CC
        INNER JOIN DT_TMP_COHORT C
            ON CC.PATIENT_NUM = C.PATIENT_NUM
    WHERE AGE_GRP != 'ALL PATIENTS'; -- DROP OUT THE ALL PATIENTS DUPLICATES PRESENT IN AGE_GRP PARTITIONS

    -- FINAL TIMING MESSAGE
    V_ROWS := SQL%ROWCOUNT;
    V_ENDRUNTIME_MS := EXTRACT (DAY FROM (LOCALTIMESTAMP - V_START_TS))*24*60*60 +
        EXTRACT (HOUR FROM (LOCALTIMESTAMP - V_START_TS))*60*60+
        EXTRACT (MINUTE FROM (LOCALTIMESTAMP - V_START_TS))*60+
        ROUND(EXTRACT(SECOND FROM (LOCALTIMESTAMP - V_START_TS))*1000);
    DBMS_OUTPUT.PUT_LINE('Procedure completed - Total Execution (ms)' || TO_CHAR(v_endruntime_ms));

    -- Adding a blank RAISERROR to pad between runs if using the extract full report sql
    DBMS_OUTPUT.PUT_LINE(TO_CHAR(v_endruntime_ms));

    -- FINAL OUTPUT FOR SHARED SPREADSHEET
    IF P_OUTPUT=1 THEN -- Only if Output parameter was passed true - In general it's expected that the ExtractFullReport would be run to calculate several different cohorts/lookbacks etc. Then run a final output FROM that script
        OPEN V_RESULT FOR
            SELECT DISTINCT LDS.COHORT_NAME, LDS.SITE, LDS.EXTRACT_DTTM, LDS.LOOKBACK_YR, LDS.GENDER_DENOMINATORS_YN, LDS.CUTOFF_FILTER_YN, LDS.SUMMARY_DESCRIPTION, LDS.TABLE_NAME, LDS.NUM_DX1, LDS.NUM_DX2, LDS.MED_USE1, LDS.MED_USE2
                , LDS.MAMMOGRAPHY, LDS.PAP_TEST, LDS.PSA_TEST, LDS.COLONOSCOPY, LDS.FECAL_OCCULT_TEST, LDS.FLU_SHOT, LDS.PNEUMOCOCCAL_VACCINE, LDS.BMI, LDS.A1C, LDS.MEDICAL_EXAM, LDS.INP1_OPT1_VISIT, LDS.OPT2_VISIT, LDS.ED_VISIT
                , LDS.MDVISIT_PNAME2, LDS.MDVISIT_PNAME3, LDS.Routine_care_2, LDS.SUBJECTS_NOCRITERIA, LDS.PREDICTIVE_SCORE_CUTOFF
                , LDS.MEAN_10YR_PROB, LDS.MEDIAN_10YR_PROB, LDS.MODE_10YR_PROB, LDS.STDEV_10YR_PROB
                , LDS.PERCENT_POPULATION
                , LDS.PERCENT_SUBJECTS_FEMALE
                , LDS.PERCENT_SUBJECTS_MALE
                , LDS.AVERAGE_FACT_COUNT
                , LDS.RUNTIME_MS
            FROM DT_LOYALTY_RESULT_SUMMARY LDS
            WHERE LDS.SUMMARY_DESCRIPTION = 'PERCENT SUBJECTS'
                AND LDS.LOOKBACK_YR = p_lookback_years
                AND LDS.GENDER_DENOMINATORS_YN =  v_gender_yn
                AND LDS.SITE = p_site
                AND LDS.COHORT_NAME IN (SELECT COHORT_NAME FROM DT_TMP_COHORT_FILTER)
            ORDER BY LDS.COHORT_NAME, LDS.CUTOFF_FILTER_YN, LDS.TABLE_NAME;

        DBMS_SQL.RETURN_RESULT(V_RESULT);
    END IF;
END;
