-- Sample code that will run the loyalty cohort algorithm on all patients in a patient set, identified by a query named "patient set test1" and run by "demouser".
-- It uses an index date of 01/01/2020 and a three-year lookback. Use this template to modify for your own work.

-- IF OBJECT_ID(N'DBO.USP_DT_LOYALTYCOHORT_EXAMPLE') IS NOT NULL DROP PROCEDURE DBO.USP_DT_LOYALTYCOHORT_EXAMPLE;;

CREATE PROCEDURE DBO.USP_DT_LOYALTYCOHORT_EXAMPLE

AS

SET NOCOUNT ON
SET XACT_ABORT ON

DELETE FROM DT_LOYALTY_RESULT WHERE COHORT_NAME = 'EXAMPLE';

DECLARE @cfilter UDT_DT_LOYALTY_COHORTFILTER;

INSERT INTO @cfilter (PATIENT_NUM, COHORT_NAME, INDEX_DT)
select patient_num, 'EXAMPLE', CONVERT(DATETIME,'20200101') AS index_dt from
(select result.DESCRIPTION,pset.PATIENT_NUM from QT_QUERY_MASTER master
inner join QT_QUERY_INSTANCE instance on master.QUERY_MASTER_ID=instance.QUERY_MASTER_ID 
inner join QT_QUERY_RESULT_INSTANCE result on instance.QUERY_INSTANCE_ID=result.QUERY_INSTANCE_ID
inner join QT_PATIENT_SET_COLLECTION pset on result.RESULT_INSTANCE_ID=pset.RESULT_INSTANCE_ID
where master.name='patient set test1' and master.user_id='demouser') x


-- Edit for your site
EXEC [dbo].[USP_DT_LOYALTYCOHORT] @site='DEMO', @LOOKBACK_YEARS=3, @DEMOGRAPHIC_FACTS=0, @GENDERED=1, @COHORT_FILTER=@cfilter, @OUTPUT=0

