-- Read-only preflight checks for Oracle ACT-OMOP loyalty cohort support.
-- Run after the ACT-OMOP views, Digital Twin tables/reference data,
-- 00_dt_loyaltycohort_prep_omop.sql, and the loyalty procedure are installed.

SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
    TYPE NAME_LIST IS TABLE OF VARCHAR2(500) INDEX BY PLS_INTEGER;
    TYPE STRING_SET IS TABLE OF PLS_INTEGER INDEX BY VARCHAR2(200);

    V_ONTOLOGY_TABLES NAME_LIST;
    V_DIAG_TABLES NAME_LIST;
    V_CODES STRING_SET;
    V_CATEGORIES STRING_SET;
    V_CURSOR SYS_REFCURSOR;
    V_NAME VARCHAR2(500);
    V_OBJECT VARCHAR2(500);
    V_SQL VARCHAR2(32767);
    V_COUNT NUMBER;
    V_COUNT2 NUMBER;
    V_COUNT3 NUMBER;
    V_COUNT4 NUMBER;
    V_COUNT5 NUMBER;
    V_COUNT6 NUMBER;
    V_COUNT7 NUMBER;
    V_VISIT_PATHS NUMBER := 0;
    V_FACT_PATHS NUMBER := 0;
    V_MATCHED NUMBER;
    V_CODE VARCHAR2(200);
    V_CATEGORY VARCHAR2(200);
    V_TABLE_COUNT PLS_INTEGER := 0;
    V_DIAG_COUNT PLS_INTEGER := 0;
    V_VISIT_TABLE VARCHAR2(500);

    FUNCTION QUERYABLE(P_NAME VARCHAR2) RETURN BOOLEAN IS
        V_N NUMBER;
    BEGIN
        IF INSTR(P_NAME, '@') > 0 THEN RETURN FALSE; END IF;
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' ||
            DBMS_ASSERT.SQL_OBJECT_NAME(P_NAME) || ' WHERE 1=0' INTO V_N;
        RETURN TRUE;
    EXCEPTION
        WHEN OTHERS THEN RETURN FALSE;
    END;

    PROCEDURE SHOW_REQUIREMENT(P_LABEL VARCHAR2, P_NAME VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(RPAD(P_LABEL, 34) || RPAD(P_NAME, 34) ||
            CASE WHEN QUERYABLE(P_NAME) THEN 'OK' ELSE 'MISSING OR INACCESSIBLE' END);
    END;

    PROCEDURE CLOSE_CURSOR_IF_OPEN(P_CURSOR IN OUT SYS_REFCURSOR) IS
    BEGIN
        IF P_CURSOR%ISOPEN THEN CLOSE P_CURSOR; END IF;
    EXCEPTION
        WHEN INVALID_CURSOR THEN NULL;
    END;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== Oracle ACT-OMOP loyalty prerequisites ===');
    SHOW_REQUIREMENT('OMOP fact compatibility', 'OBSERVATION_FACT');
    SHOW_REQUIREMENT('OMOP patient compatibility', 'PATIENT_DIMENSION');
    SHOW_REQUIREMENT('OMOP visit compatibility', 'VISIT_DIMENSION');
    SHOW_REQUIREMENT('Ontology registry', 'TABLE_ACCESS');
    SHOW_REQUIREMENT('Unified concept dimension', 'CONCEPT_DIMENSION');
    SHOW_REQUIREMENT('Loyalty paths', 'DT_LOYALTY_PATHS');
    SHOW_REQUIREMENT('Loyalty coefficients', 'DT_LOYALTY_PSCOEFF');
    SHOW_REQUIREMENT('Charlson mappings', 'DT_LOYALTY_CHARLSON');
    SHOW_REQUIREMENT('Oracle concept work table', 'DT_TMP_LOY_CONCEPT');

    DBMS_OUTPUT.PUT_LINE(CHR(10) || 'At least one of CONCEPT_DIMENSION or TABLE_ACCESS must be OK.');

    IF QUERYABLE('OBSERVATION_FACT') THEN
        EXECUTE IMMEDIATE q'~
            SELECT COUNT(*), COUNT(DISTINCT PATIENT_NUM),
                SUM(CASE WHEN PATIENT_NUM IS NULL THEN 1 ELSE 0 END),
                SUM(CASE WHEN CONCEPT_CD IS NULL THEN 1 ELSE 0 END),
                SUM(CASE WHEN START_DATE IS NULL THEN 1 ELSE 0 END),
                MIN(START_DATE), MAX(START_DATE)
            FROM OBSERVATION_FACT
        ~' INTO V_COUNT, V_COUNT2, V_COUNT3, V_COUNT4, V_COUNT5, V_NAME, V_OBJECT;

        DBMS_OUTPUT.PUT_LINE(CHR(10) || '=== OBSERVATION_FACT coverage ===');
        DBMS_OUTPUT.PUT_LINE('Rows=' || V_COUNT || ', patients=' || V_COUNT2 ||
            ', null patient=' || V_COUNT3 || ', null concept=' || V_COUNT4 ||
            ', null date=' || V_COUNT5 || ', earliest=' || V_NAME ||
            ', latest=' || V_OBJECT);
    END IF;

    IF QUERYABLE('PATIENT_DIMENSION') THEN
        EXECUTE IMMEDIATE q'~
            SELECT COUNT(*),
                SUM(CASE WHEN BIRTH_DATE IS NULL THEN 1 ELSE 0 END),
                SUM(CASE WHEN UPPER(TRIM(TO_CHAR(SEX_CD))) IN ('F','DEM|SEX:F','8532') THEN 1 ELSE 0 END),
                SUM(CASE WHEN UPPER(TRIM(TO_CHAR(SEX_CD))) IN ('M','DEM|SEX:M','8507') THEN 1 ELSE 0 END),
                SUM(CASE WHEN DEATH_DATE IS NOT NULL THEN 1 ELSE 0 END)
            FROM PATIENT_DIMENSION
        ~' INTO V_COUNT, V_COUNT2, V_COUNT3, V_COUNT4, V_COUNT5;

        DBMS_OUTPUT.PUT_LINE(CHR(10) || '=== PATIENT_DIMENSION coverage ===');
        DBMS_OUTPUT.PUT_LINE('Patients=' || V_COUNT || ', missing birth date=' ||
            V_COUNT2 || ', recognized female=' || V_COUNT3 ||
            ', recognized male=' || V_COUNT4 || ', nonnull death date=' || V_COUNT5);
    END IF;

    IF QUERYABLE('TABLE_ACCESS') THEN
        OPEN V_CURSOR FOR
            'SELECT DISTINCT C_TABLE_NAME FROM TABLE_ACCESS ' ||
            'WHERE C_TABLE_NAME IS NOT NULL AND C_VISUALATTRIBUTES LIKE ''%A%''';
        LOOP
            FETCH V_CURSOR INTO V_NAME;
            EXIT WHEN V_CURSOR%NOTFOUND;
            V_TABLE_COUNT := V_TABLE_COUNT + 1;
            V_ONTOLOGY_TABLES(V_TABLE_COUNT) := V_NAME;
        END LOOP;
        CLOSE V_CURSOR;

        OPEN V_CURSOR FOR
            'SELECT DISTINCT C_TABLE_NAME FROM TABLE_ACCESS ' ||
            'WHERE C_TABLE_NAME IS NOT NULL AND C_VISUALATTRIBUTES LIKE ''%A%'' ' ||
            'AND (C_FULLNAME LIKE ''\ACT\Diagnosis\ICD10%'' ' ||
            'OR C_FULLNAME LIKE ''\ACT\Diagnosis\ICD9%'')';
        LOOP
            FETCH V_CURSOR INTO V_NAME;
            EXIT WHEN V_CURSOR%NOTFOUND;
            V_DIAG_COUNT := V_DIAG_COUNT + 1;
            V_DIAG_TABLES(V_DIAG_COUNT) := V_NAME;
        END LOOP;
        CLOSE V_CURSOR;
    END IF;

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '=== Configured loyalty path coverage ===');
    FOR P IN (
        SELECT FEATURE_NAME, CODE_TYPE, CONCEPT_PATH
        FROM DT_LOYALTY_PATHS
        WHERE CONCEPT_PATH IS NOT NULL AND CONCEPT_PATH <> '**Not Found'
        ORDER BY FEATURE_NAME, CONCEPT_PATH
    ) LOOP
        V_MATCHED := 0;

        IF QUERYABLE('CONCEPT_DIMENSION') THEN
            EXECUTE IMMEDIATE
                'SELECT COUNT(*) FROM CONCEPT_DIMENSION ' ||
                'WHERE CONCEPT_PATH LIKE :1 AND CONCEPT_CD IS NOT NULL'
                INTO V_COUNT USING P.CONCEPT_PATH || '%';
            IF V_COUNT > 0 THEN V_MATCHED := 1; END IF;
        END IF;

        IF V_MATCHED = 0 AND V_TABLE_COUNT > 0 THEN
            FOR I IN 1 .. V_TABLE_COUNT LOOP
                V_OBJECT := DBMS_ASSERT.SQL_OBJECT_NAME(V_ONTOLOGY_TABLES(I));
                EXECUTE IMMEDIATE
                    'SELECT COUNT(*) FROM ' || V_OBJECT ||
                    ' WHERE C_FULLNAME LIKE :1 AND C_BASECODE IS NOT NULL'
                    INTO V_COUNT USING P.CONCEPT_PATH || '%';
                IF V_COUNT > 0 THEN V_MATCHED := 1; EXIT; END IF;
            END LOOP;
        END IF;

        IF V_MATCHED = 0 THEN
            DBMS_OUTPUT.PUT_LINE('MISSING: ' || P.FEATURE_NAME || ' [' ||
                P.CODE_TYPE || '] ' || P.CONCEPT_PATH);
        ELSIF P.CODE_TYPE = 'VISIT' THEN
            V_VISIT_PATHS := V_VISIT_PATHS + 1;
        ELSIF P.CODE_TYPE IN ('DX','PX','LAB','MEDS','SITE') THEN
            V_FACT_PATHS := V_FACT_PATHS + 1;
        END IF;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Matched visit paths=' || V_VISIT_PATHS ||
        ', matched fact-feature paths=' || V_FACT_PATHS);

    IF QUERYABLE('TABLE_ACCESS') AND QUERYABLE('VISIT_DIMENSION') THEN
        BEGIN
            EXECUTE IMMEDIATE
                'SELECT C_TABLE_NAME FROM TABLE_ACCESS ' ||
                'WHERE UPPER(C_TABLE_CD) = ''ACT_VISIT'' AND C_TABLE_NAME IS NOT NULL AND ROWNUM = 1'
                INTO V_VISIT_TABLE;

            V_OBJECT := DBMS_ASSERT.SQL_OBJECT_NAME(V_VISIT_TABLE);
            V_SQL :=
                'SELECT TRIM(TO_CHAR(O.C_BASECODE)), COUNT(V.PATIENT_NUM), ' ||
                'COUNT(DISTINCT V.PATIENT_NUM) FROM ' || V_OBJECT || ' O ' ||
                'JOIN DT_LOYALTY_PATHS L ON O.C_FULLNAME LIKE L.CONCEPT_PATH || ''%'' ' ||
                'LEFT JOIN VISIT_DIMENSION V ON TRIM(TO_CHAR(V.INOUT_CD)) = TRIM(TO_CHAR(O.C_BASECODE)) ' ||
                'WHERE L.CODE_TYPE = ''VISIT'' AND O.C_BASECODE IS NOT NULL ' ||
                'GROUP BY TRIM(TO_CHAR(O.C_BASECODE)) ORDER BY COUNT(V.PATIENT_NUM) DESC';

            DBMS_OUTPUT.PUT_LINE(CHR(10) || '=== Visit-code matches ===');
            OPEN V_CURSOR FOR V_SQL;
            LOOP
                FETCH V_CURSOR INTO V_CODE, V_COUNT, V_COUNT2;
                EXIT WHEN V_CURSOR%NOTFOUND;
                DBMS_OUTPUT.PUT_LINE('Code=' || V_CODE || ', rows=' || V_COUNT ||
                    ', patients=' || V_COUNT2);
            END LOOP;
            CLOSE V_CURSOR;

            V_SQL :=
                'SELECT INOUT_CD, VISIT_ROWS, PATIENTS FROM (' ||
                'SELECT TRIM(TO_CHAR(V.INOUT_CD)) INOUT_CD, COUNT(*) VISIT_ROWS, ' ||
                'COUNT(DISTINCT V.PATIENT_NUM) PATIENTS FROM VISIT_DIMENSION V ' ||
                'WHERE NOT EXISTS (SELECT 1 FROM ' || V_OBJECT || ' O ' ||
                'JOIN DT_LOYALTY_PATHS L ON O.C_FULLNAME LIKE L.CONCEPT_PATH || ''%'' ' ||
                'WHERE L.CODE_TYPE = ''VISIT'' AND O.C_BASECODE IS NOT NULL ' ||
                'AND TRIM(TO_CHAR(O.C_BASECODE)) = TRIM(TO_CHAR(V.INOUT_CD))) ' ||
                'GROUP BY TRIM(TO_CHAR(V.INOUT_CD)) ORDER BY COUNT(*) DESC) ' ||
                'WHERE ROWNUM <= 25';

            DBMS_OUTPUT.PUT_LINE(CHR(10) || '=== Common uncovered visit codes ===');
            OPEN V_CURSOR FOR V_SQL;
            LOOP
                FETCH V_CURSOR INTO V_CODE, V_COUNT, V_COUNT2;
                EXIT WHEN V_CURSOR%NOTFOUND;
                DBMS_OUTPUT.PUT_LINE('Code=' || NVL(V_CODE, '<NULL>') ||
                    ', rows=' || V_COUNT || ', patients=' || V_COUNT2);
            END LOOP;
            CLOSE V_CURSOR;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                DBMS_OUTPUT.PUT_LINE('No ACT_VISIT table is registered in TABLE_ACCESS.');
        END;
    END IF;

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '=== Charlson OMOP mapping ===');
    IF V_DIAG_COUNT > 0 THEN
        FOR I IN 1 .. V_DIAG_COUNT LOOP
            V_OBJECT := DBMS_ASSERT.SQL_OBJECT_NAME(V_DIAG_TABLES(I));
            V_SQL :=
                'SELECT DISTINCT C.CHARLSON_CATGRY, X.CONCEPT_CD ' ||
                'FROM DT_LOYALTY_CHARLSON C JOIN (' ||
                'SELECT CAST(I2B2_ACT_BASECODE AS VARCHAR2(100)) ACT_CODE, ' ||
                'CAST(OMOP_S_CONCEPT_ID AS VARCHAR2(50)) CONCEPT_CD FROM ' || V_OBJECT ||
                ' UNION ALL SELECT CAST(I2B2_ACT_BASECODE AS VARCHAR2(100)), ' ||
                'CAST(OMOP_NS_CONCEPT_ID AS VARCHAR2(50)) FROM ' || V_OBJECT ||
                ') X ON X.ACT_CODE LIKE C.DIAGPATTERN ' ||
                'WHERE X.CONCEPT_CD IS NOT NULL AND X.ACT_CODE NOT LIKE ''%-%''';
            BEGIN
                OPEN V_CURSOR FOR V_SQL;
                LOOP
                    FETCH V_CURSOR INTO V_CATEGORY, V_CODE;
                    EXIT WHEN V_CURSOR%NOTFOUND;
                    V_CATEGORIES(V_CATEGORY) := 1;
                    V_CODES(V_CODE) := 1;
                END LOOP;
                CLOSE V_CURSOR;
            EXCEPTION
                WHEN OTHERS THEN
                    CLOSE_CURSOR_IF_OPEN(V_CURSOR);
                    IF SQLCODE != -904 THEN RAISE; END IF;
            END;
        END LOOP;
    END IF;

    DBMS_OUTPUT.PUT_LINE('Diagnosis ontology tables=' || V_DIAG_COUNT ||
        ', fact concept IDs=' || V_CODES.COUNT ||
        ', categories=' || V_CATEGORIES.COUNT);
    IF V_CODES.COUNT = 0 THEN
        DBMS_OUTPUT.PUT_LINE('WARNING: no ACT-OMOP Charlson diagnosis concepts mapped.');
    END IF;

    DBMS_OUTPUT.PUT_LINE(CHR(10) ||
        'NOTICE: a zero nonnull death-date count is expected until ACT-OMOP death mapping is implemented.');
EXCEPTION
    WHEN OTHERS THEN
        CLOSE_CURSOR_IF_OPEN(V_CURSOR);
        DBMS_OUTPUT.PUT_LINE('VALIDATION ERROR ' || SQLCODE || ': ' || SQLERRM);
        RAISE;
END;
/
