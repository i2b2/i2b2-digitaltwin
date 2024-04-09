--##############################################################################
--##############################################################################
--### KOMAP - Generate Phenotype
--### Date: September 1, 2023
--### Database: Microsoft SQL Server
--### Created By: Griffin Weber (weber@hms.harvard.edu)
--##############################################################################
--##############################################################################


-- Drop the procedure if it already exists
IF OBJECT_ID(N'dbo.usp_dt_komap_generate_phenotype') IS NOT NULL DROP PROCEDURE dbo.usp_dt_komap_generate_phenotype;;


CREATE PROCEDURE dbo.usp_dt_komap_generate_phenotype
AS
BEGIN

SET NOCOUNT ON;


--------------------------------------------------------------------------------
-- Truncate tables to remove old data.
--------------------------------------------------------------------------------

truncate table dbo.dt_komap_phenotype_patient;


-------------------------------------------------------------------------
-- Find patients with each phenotype.
-------------------------------------------------------------------------

insert into dbo.dt_komap_phenotype_patient (phenotype, patient_num, score)
	select t.phenotype, t.patient_num, t.score
	from (
		select c.phenotype, f.patient_num, sum(f.log_dates*c.coef) score
		from dbo.dt_komap_phenotype_feature_coef c
			inner join dbo.dt_komap_patient_feature s
				on c.phenotype=s.feature_cd
			inner join dbo.dt_komap_base_cohort b
				on s.patient_num=b.patient_num
			inner join dbo.dt_komap_patient_feature f
				on c.feature_cd=f.feature_cd and f.patient_num=s.patient_num
		group by c.phenotype, f.patient_num
	) t inner join dbo.dt_komap_phenotype p
		on t.phenotype=p.phenotype
	where p.generate_facts=1 and t.score>=p.threshold;


-------------------------------------------------------------------------
-- Delete old facts for patients who had the phenotype.
-------------------------------------------------------------------------

delete 
	from dbo.DERIVED_FACT
	where concept_cd in (
		select 'DT|'+phenotype
		from dbo.dt_komap_phenotype
		where generate_facts=1
	);


-------------------------------------------------------------------------
-- Generate new derived facts for patients who now have the phenotype.
-------------------------------------------------------------------------

insert into dbo.DERIVED_FACT (encounter_num, patient_num, concept_cd, provider_id, start_date, modifier_cd, instance_num)
	select -1, patient_num, 'DT|'+phenotype, '@', GetDate(), '@', 1
	from dbo.dt_komap_phenotype_patient;


END

