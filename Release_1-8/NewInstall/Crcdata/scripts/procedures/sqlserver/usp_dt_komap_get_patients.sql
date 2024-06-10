--##############################################################################
--##############################################################################
--### KOMAP - Get Patients
--### Date: April 23, 2024
--### Database: Microsoft SQL Server
--### Created By: Griffin Weber (weber@hms.harvard.edu)
--##############################################################################
--##############################################################################


-- Drop the procedure if it already exists
-- IF OBJECT_ID(N'dbo.usp_dt_komap_get_patients') IS NOT NULL DROP PROCEDURE dbo.usp_dt_komap_get_patients;;


CREATE PROCEDURE DBO.USP_DT_KOMAP_GET_PATIENTS
AS
BEGIN

SET NOCOUNT ON;


--------------------------------------------------------------------------------
-- Truncate tables to remove old data.
--------------------------------------------------------------------------------

truncate table dbo.dt_komap_patient_feature;
truncate table dbo.dt_komap_base_cohort;


-------------------------------------------------------------------------
-- Get patient data for the PheCode and additional features from KESER.
-------------------------------------------------------------------------
	
-- OPTION 1: From the KESER patient_period_feature table (faster).
-- This option assumes the KESER table is up to date. It can be used for testing.
-- However, in production, KOMAP might be run more often than KESER.
-- As a result, in production, the second option is better since it uses more up-to-date data.
insert into dbo.dt_komap_patient_feature (patient_num, feature_cd, num_dates, log_dates)
	select patient_num, feature_cd, num_dates, log(num_dates+1)
	from (
		select t.patient_num, f.feature_cd, 
			(case when f.feature_cd like 'PheCode:%' then concept_dates else feature_dates end) num_dates
		from (
			select patient_num, feature_num, sum(feature_dates) feature_dates, sum(concept_dates) concept_dates
			from dbo.dt_keser_patient_period_feature
			group by patient_num, feature_num
		) t 
		inner join dbo.dt_keser_feature f
				on t.feature_num=f.feature_num
	) t;

-- OPTION 2: Directly from the observation_fact table (slower).
-- --
-- insert into dbo.dt_komap_patient_feature (patient_num, feature_cd, num_dates, log_dates)
-- 	select t.patient_num, f.feature_cd, d.num_dates, log(d.num_dates+1) log_dates
-- 	from (
-- 		select patient_num, feature_num, count(*) feature_dates, sum(num_concepts) concept_dates
-- 		from (
-- 			select f.patient_num, c.feature_num, t.start_date, count(distinct c.concept_cd) num_concepts
-- 			from dbo.observation_fact f with (nolock)
-- 				inner join dbo.dt_keser_concept_feature c with (nolock)
-- 					on f.concept_cd=c.concept_cd
-- 				cross apply (select cast(f.start_date as date) start_date) t
-- 			group by f.patient_num, c.feature_num, t.start_date
-- 		) t
-- 		group by patient_num, feature_num
-- 	) t 
-- 	inner join dbo.dt_keser_feature f
-- 			on t.feature_num=f.feature_num
-- 	cross apply (select (case when f.feature_cd like 'PheCode:%' then concept_dates else feature_dates end) num_dates) d
-- 	;
-- 
-- 

-------------------------------------------------------------------------
-- Calculate the healthcare utilization feature for each patient.
-------------------------------------------------------------------------

-- Healthcare utilization feature (distinct dates with an ICD code)
insert into dbo.dt_komap_patient_feature (patient_num, feature_cd, num_dates, log_dates)
	select patient_num, 'Utilization:IcdDates' feature_cd, num_dates, log(num_dates+1)
	from (
		select patient_num, count(distinct feature_date) num_dates
		from dbo.observation_fact with (nolock)
			cross apply (select cast(start_date as date) feature_date) d
		where concept_cd like 'DIAG|ICD%' -- or 'ICD%' for ACT ontology
        group by patient_num
	) t;


-------------------------------------------------------------------------
-- Get patient data for custom features. (Edit the SQL as needed.)
-------------------------------------------------------------------------

-- Female
insert into dbo.dt_komap_patient_feature (patient_num, feature_cd, num_dates, log_dates)
	select distinct patient_num, 'DEM|SEX:F', 1, log(2)
		from dbo.patient_dimension with (nolock)
		where sex_cd='F';

-- Age group
insert into dbo.dt_komap_patient_feature (patient_num, feature_cd, num_dates, log_dates)
	select distinct patient_num, 
			(case when age_in_years_num>=65 then 'DEM|AGE:65plus'
				when age_in_years_num between 55 and 64 then 'DEM|AGE:55to64'
				when age_in_years_num between 45 and 54 then 'DEM|AGE:45to54'
				when age_in_years_num between 35 and 44 then 'DEM|AGE:35to44'
				when age_in_years_num between 18 and 34 then 'DEM|AGE:18to34'
				else 'DEM|AGE:Missing' end),
			1, log(2)
		from dbo.patient_dimension with (nolock)
		where isnull(age_in_years_num,99) >= 18;

-- BMI >= 30
insert into dbo.dt_komap_patient_feature (patient_num, feature_cd, num_dates, log_dates)
	select distinct patient_num, 'VITAL|BMI:30plus', 1, log(2)
		from dbo.observation_fact with (nolock)
		where concept_cd = 'VITAL|LOINC:39156-5' and nval_num >= 30;

-- Smoking
insert into dbo.dt_komap_patient_feature (patient_num, feature_cd, num_dates, log_dates)
	select distinct patient_num, 'VITAL|SMOKING:YES', 1, log(2)
		from dbo.observation_fact with (nolock)
		where concept_cd in ('VITAL|SMOKING:YES','VITAL|SMOKING:01','VITAL|SMOKING:02','VITAL|SMOKING:05','VITAL|SMOKING:07','VITAL|SMOKING:08','VITAL|SMOKING:03');


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
insert into dbo.dt_komap_base_cohort (patient_num)
	select patient_num
	from dbo.observation_fact
		cross apply (select cast(start_date as date) d) d
	where concept_cd like 'DIAG|ICD%' -- or 'ICD%' for ACT ontology
	    and start_date>='1/1/2010'
	group by patient_num
	having count(distinct d)>=3;

-- OPTION 2: This is a minimal approach that only requires one diagnosis.
-- --
-- insert into dbo.dt_komap_base_cohort (patient_num)
-- 	select patient_num
-- 		from dbo.dt_komap_patient_feature with (nolock)
-- 		where feature_cd = 'Utilization:IcdDates'
-- 			and num_dates>=1;
-- 
-- 

-- OPTION 3: Use a "loyalty cohort" algorithm to select patients whose data are likely complete.
-- This must be generated by a separate process. It is not part of KESER/KOMAP.
-- Patients who receive all their care at one site ("loyal" patients) have complete EHR data.
-- As a result, there is less concern about missing data when generating phenotypes.
-- However, loyal patients might not be representative of the larger population.
-- --
-- select patient_num
-- 	select patient_num
-- 	from dbo.loyalty_cohort;
-- 
-- 


END

