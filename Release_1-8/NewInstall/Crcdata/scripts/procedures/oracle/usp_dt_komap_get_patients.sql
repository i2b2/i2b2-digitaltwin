--##############################################################################
--##############################################################################
--### KOMAP - Get Patients
--### Date: September 1, 2023
--### Database: Oracle
--### Created By: Griffin Weber (weber@hms.harvard.edu)
--##############################################################################
--##############################################################################


-- Drop the procedure if it already exists
BEGIN EXECUTE IMMEDIATE 'DROP PROCEDURE usp_dt_komap_get_patients'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -4043 THEN RAISE; END IF; END;


CREATE PROCEDURE usp_dt_komap_get_patients
AS
    proc_start_time timestamp := localtimestamp;
    step_start_time timestamp;
BEGIN



--------------------------------------------------------------------------------
-- Truncate tables to remove old data.
--------------------------------------------------------------------------------

execute immediate 'truncate table dt_komap_patient_feature';
execute immediate 'truncate table dt_komap_base_cohort';


-------------------------------------------------------------------------
-- Get patient data for the PheCode and additional features from KESER.
-------------------------------------------------------------------------

-- OPTION 1: Directly from the observation_fact table (slower).
step_start_time := localtimestamp;
insert into dt_komap_patient_feature (patient_num, feature_cd, num_dates, log_dates)
	select t.patient_num, f.feature_cd, d.num_dates, ln(d.num_dates+1) log_dates
	from (
		select patient_num, feature_num, count(*) feature_dates, sum(num_concepts) concept_dates
		from (
			select f.patient_num, c.feature_num, t.start_date, count(distinct c.concept_cd) num_concepts
			from observation_fact f
				inner join dt_keser_concept_feature c
					on f.concept_cd=c.concept_cd
				cross apply (select cast(f.start_date as date) start_date from dual) t
			group by f.patient_num, c.feature_num, t.start_date
		) t
		group by patient_num, feature_num
	) t 
	inner join dt_keser_feature f
			on t.feature_num=f.feature_num
	cross apply (select (case when f.feature_cd like 'PheCode:%' then concept_dates else feature_dates end) num_dates from dual) d
	;
usp_dt_print(step_start_time, '  insert into dt_komap_patient_feature', sql%Rowcount);

-- OPTION 2: From the KESER patient_period_feature table (faster).
-- This option assumes the KESER table is up to date. It can be used for testing.
-- However, in production, KOMAP might be run more often than KESER.
-- As a result, in production, the first option is better since it uses more up-to-date data.
-- 
-- insert into dt_komap_patient_feature (patient_num, feature_cd, num_dates, log_dates)
-- 	select patient_num, feature_cd, num_dates, ln(num_dates+1)
-- 	from (
-- 		select t.patient_num, f.feature_cd, 
-- 			(case when f.feature_cd like 'PheCode:%' then concept_dates else feature_dates end) num_dates
-- 		from (
-- 			select patient_num, feature_num, sum(feature_dates) feature_dates, sum(concept_dates) concept_dates
-- 			from dt_keser_patient_period_feature
-- 			group by patient_num, feature_num
-- 		) t 
-- 		inner join dt_keser_feature f
-- 				on t.feature_num=f.feature_num
-- 	) t;


-------------------------------------------------------------------------
-- Calculate the healthcare utilization feature for each patient.
-------------------------------------------------------------------------

-- Healthcare utilization feature (distinct dates with an ICD code)
step_start_time := localtimestamp;
insert into dt_komap_patient_feature (patient_num, feature_cd, num_dates, log_dates)
	select patient_num, 'Utilization:IcdDates' feature_cd, num_dates, ln(num_dates+1)
	from (
		select f.patient_num, count(distinct d.feature_date) num_dates
		from observation_fact f
			cross apply (select cast(f.start_date as date) feature_date from dual) d
		where f.concept_cd like 'ICD%'
-- 			where f.concept_cd like 'DIAG|ICD%'
        group by f.patient_num
	) t;
usp_dt_print(step_start_time, '  insert into dt_komap_patient_feature (Utilization:IcdDates)', sql%Rowcount);


-------------------------------------------------------------------------
-- Get patient data for custom features. (Edit the SQL as needed.)
-------------------------------------------------------------------------

-- Female
step_start_time := localtimestamp;
insert into dt_komap_patient_feature (patient_num, feature_cd, num_dates, log_dates)
	select distinct patient_num, 'DEM|SEX:F', 1, ln(2)
		from patient_dimension
		where sex_cd='F';
usp_dt_print(step_start_time, '  insert into dt_komap_patient_feature (DEM|SEX:F)', sql%rowcount );

-- Age group
step_start_time := localtimestamp;
insert into dt_komap_patient_feature (patient_num, feature_cd, num_dates, log_dates)
	select distinct patient_num, 
			(case when age_in_years_num>=65 then 'DEM|AGE:65plus'
				when age_in_years_num between 55 and 64 then 'DEM|AGE:55to64'
				when age_in_years_num between 45 and 54 then 'DEM|AGE:45to54'
				when age_in_years_num between 35 and 44 then 'DEM|AGE:35to44'
				when age_in_years_num between 18 and 34 then 'DEM|AGE:18to34'
				else 'DEM|AGE:Missing' end),
			1, ln(2)
		from patient_dimension
		where nvl(age_in_years_num,99) >= 18;
usp_dt_print(step_start_time, '  insert into dt_komap_patient_feature (DEM|AGE)', sql%Rowcount);

-- BMI >= 30
step_start_time := localtimestamp;
insert into dt_komap_patient_feature (patient_num, feature_cd, num_dates, log_dates)
	select distinct patient_num, 'VITAL|BMI:30plus', 1, ln(2)
		from observation_fact
		where concept_cd = 'LOINC:39156-5' and nval_num >= 30;
--         where concept_cd = 'VITAL|LOINC:39156-5' and nval_num >= 30;
usp_dt_print(step_start_time, '  insert into dt_komap_patient_feature (VITAL|BMI)', sql%Rowcount);

-- Smoking
step_start_time := localtimestamp;
insert into dt_komap_patient_feature (patient_num, feature_cd, num_dates, log_dates)
	select distinct patient_num, 'VITAL|SMOKING:YES', 1, ln(2)
		from observation_fact
		where concept_cd in ('VITAL|SMOKING:YES','VITAL|SMOKING:01','VITAL|SMOKING:02','VITAL|SMOKING:05','VITAL|SMOKING:07','VITAL|SMOKING:08','VITAL|SMOKING:03');
usp_dt_print(step_start_time, '  insert into dt_komap_patient_feature (VITAL|SMOKING)', sql%Rowcount);

execute immediate 'analyze table dt_komap_patient_feature compute statistics';

-------------------------------------------------------------------------
-- Determine the base cohort.
-- This is the population which has enough data to generate a phenotype.
-- There are many ways to define this. Be careful of introducing biases.
-------------------------------------------------------------------------

-- OPTION 1: This requires 3+ different dates (visits) with a diagnosis after 1/1/2010.
-- With fewer than 3 visits, there likely is not enough data to be confident in the phenotype.
-- Older EHR data (e.g., before 1/1/2010) might not be as reliable or complete.
-- For example, an EHR might have diagnoses starting in 2002, but medications starting in 2007.
-- As a result, it will incorrectly appear that patients from 2002-2006 were not taking any medications.
-- This approach attempts to keep biases from base cohort selection small and only remove obvious problems.
-- Both parameters (minimum number of diagnosis dates and cutoff date) need to be tuned for your site.
step_start_time := localtimestamp;
insert into dt_komap_base_cohort (patient_num)
	select f.patient_num
	from observation_fact f
		cross apply (select trunc(f.start_date) d from dual) d
	where f.concept_cd like 'ICD%' and trunc(f.start_date) >= to_date('2010-01-01', 'YYYY-MM-DD')
--  where f.concept_cd like 'DIAG|ICD%' and trunc(f.start_date) >= to_date('2010-01-01', 'YYYY-MM-DD')
	group by f.patient_num
	having count(distinct d)>=3;
usp_dt_print(step_start_time, '  insert into dt_komap_base_cohort', sql%Rowcount);

-- OPTION 2: This is a minimal approach that only requires one diagnosis.
-- 
-- insert into dt_komap_base_cohort (patient_num)
-- 	select patient_num
-- 		from dt_komap_patient_feature
-- 		where feature_cd = 'Utilization:IcdDates'
-- 			and num_dates>=1;

-- OPTION 3: Use a "loyalty cohort" algorithm to select patients whose data are likely complete.
-- This must be generated by a separate process. It is not part of KESER/KOMAP.
-- Patients who receive all their care at one site ("loyal" patients) have complete EHR data.
-- As a result, there is less concern about missing data when generating phenotypes.
-- However, loyal patients might not be representative of the larger population.
-- 
-- select patient_num
-- 	select patient_num
-- 	from loyalty_cohort;

execute immediate 'analyze table dt_komap_base_cohort compute statistics';
usp_dt_print(proc_start_time, 'usp_dt_komap_get_patients', null);

END;
/

