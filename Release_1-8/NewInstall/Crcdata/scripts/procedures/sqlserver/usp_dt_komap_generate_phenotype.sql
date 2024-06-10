--##############################################################################
--##############################################################################
--### KOMAP - Generate Phenotype
--### Date: April 23, 2024
--### Database: Microsoft SQL Server
--### Created By: Griffin Weber (weber@hms.harvard.edu)
--##############################################################################
--##############################################################################


-- Drop the procedure if it already exists
-- IF OBJECT_ID(N'dbo.usp_dt_komap_generate_phenotype') IS NOT NULL DROP PROCEDURE dbo.usp_dt_komap_generate_phenotype;;


CREATE PROCEDURE DBO.USP_DT_KOMAP_GENERATE_PHENOTYPE
AS
BEGIN

SET NOCOUNT ON;


--------------------------------------------------------------------------------
-- Truncate tables to remove old data.
--------------------------------------------------------------------------------

truncate table dbo.dt_komap_phenotype_patient;


-------------------------------------------------------------------------
-- Calculate the phenotype scores for all patients with the PheCode.
-------------------------------------------------------------------------

-- First run this for phenotypes with >= 50,000 patients
insert into dbo.dt_komap_phenotype_patient (phenotype, patient_num, score)
	select c.phenotype, f.patient_num, sum(f.log_dates*c.coef) score
	from dbo.dt_komap_phenotype_feature_coef c
		inner join dbo.dt_komap_patient_feature s
			on c.phenotype=s.feature_cd
		inner join dbo.dt_komap_base_cohort b
			on s.patient_num=b.patient_num
		inner join dbo.dt_komap_patient_feature f
			on c.feature_cd=f.feature_cd and f.patient_num=s.patient_num
		inner join dbo.dt_komap_phenotype p
			on c.phenotype=p.phenotype and p.generate_facts=1
	where c.coef<>0
		and c.phenotype in (
			select phenotype 
			from dt_komap_phenotype_sample 
			group by phenotype 
			having count(*)>=50000
		)
	group by c.phenotype, f.patient_num


-- Next, use the sample results to get the scores for phenotypes with < 50,000 patients
insert into dbo.dt_komap_phenotype_patient (phenotype, patient_num, score)
	select s.phenotype, s.patient_num, s.score
	from dt_komap_phenotype_sample_results s
		inner join dbo.dt_komap_phenotype p
			on s.phenotype=p.phenotype and p.generate_facts=1
	where s.phenotype in (
		select phenotype 
		from dt_komap_phenotype_sample 
		group by phenotype 
		having count(*)<50000
	)


-------------------------------------------------------------------------
-- Delete old facts for patients who had the phenotype.
-------------------------------------------------------------------------

delete 
	from dbo.OBSERVATION_FACT -- or dbo.DERIVED_FACT if using multiple fact tables
	where concept_cd in (
		select 'DT|'+phenotype
		from dbo.dt_komap_phenotype
		where generate_facts=1
	);


-------------------------------------------------------------------------
-- Generate new derived facts for patients who now have the phenotype.
-- Here, using a dummy encounter_num = -1, which is assumed not to exist in VISIT_DIMENSION.
-------------------------------------------------------------------------

insert into dbo.OBSERVATION_FACT -- or dbo.DERIVED_FACT if using multiple fact tables
		(encounter_num, patient_num, concept_cd, provider_id, start_date, modifier_cd, instance_num,
			valtype_cd, tval_char, nval_num, valueflag_cd, end_date, location_cd, observation_blob, sourcesystem_cd)
	select -1, s.patient_num, 'DT|'+s.phenotype, '@', GetDate(), '@', 1,
		'N', 'E', s.score, '@', GetDate(), '@', '', 'phenotype'
	from dbo.dt_komap_phenotype_patient s
		inner join dbo.dt_komap_phenotype p
			on s.phenotype=p.phenotype
	where s.score >= p.threshold;


-------------------------------------------------------------------------
-- Update facts representing the Base Cohort.
-- Here, using a dummy encounter_num = -1, which is assumed not to exist in VISIT_DIMENSION.
-------------------------------------------------------------------------

-- Delete existing facts
delete 
	from dbo.OBSERVATION_FACT -- or dbo.DERIVED_FACT if using multiple fact tables
	where concept_cd = 'DT|BaseCohort';

-- Insert new facts
insert into dbo.OBSERVATION_FACT -- or dbo.DERIVED_FACT if using multiple fact tables
		(encounter_num, patient_num, concept_cd, provider_id, start_date, modifier_cd, instance_num,
			valtype_cd, tval_char, nval_num, valueflag_cd, end_date, location_cd, observation_blob, sourcesystem_cd)
	select -1, patient_num, 'DT|BaseCohort', '@', GetDate(), '@', 1,
		null, null, null, '@', GetDate(), '@', '', 'phenotype'
	from dbo.dt_komap_base_cohort;


END


