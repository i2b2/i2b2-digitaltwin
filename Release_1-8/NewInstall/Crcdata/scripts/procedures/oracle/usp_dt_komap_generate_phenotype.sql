--##############################################################################
--##############################################################################
--### KOMAP - Generate Phenotype
--### Date: September 1, 2023
--### Database: Oracle
--### Created By: Griffin Weber (weber@hms.harvard.edu)
--##############################################################################
--##############################################################################


-- Drop the procedure if it already exists
BEGIN EXECUTE IMMEDIATE 'DROP PROCEDURE usp_dt_komap_generate_phenotype'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -4043 THEN RAISE; END IF; END;


CREATE PROCEDURE usp_dt_komap_generate_phenotype
AS
    proc_start_time timestamp := localtimestamp;
    step_start_time timestamp;
BEGIN



--------------------------------------------------------------------------------
-- Truncate tables to remove old data.
--------------------------------------------------------------------------------

execute immediate 'truncate table dt_komap_phenotype_patient';


-------------------------------------------------------------------------
-- Find patients with each phenotype.
-------------------------------------------------------------------------

step_start_time := localtimestamp;
insert into dt_komap_phenotype_patient (phenotype, patient_num, score)
	select t.phenotype, t.patient_num, t.score
	from (
		select c.phenotype, f.patient_num, sum(f.log_dates*c.coef) score
		from dt_komap_phenotype_feature_coef c
			inner join dt_komap_patient_feature s
				on c.phenotype=s.feature_cd
			inner join dt_komap_base_cohort b
				on s.patient_num=b.patient_num
			inner join dt_komap_patient_feature f
				on c.feature_cd=f.feature_cd and f.patient_num=s.patient_num
		group by c.phenotype, f.patient_num
	) t inner join dt_komap_phenotype p
		on t.phenotype=p.phenotype
	where p.generate_facts=1 and t.score>=p.threshold;
usp_dt_print(step_start_time, '  insert into dt_komap_phenotype_patient', sql%Rowcount);
execute immediate 'analyze table dt_komap_phenotype_patient compute statistics';

-------------------------------------------------------------------------
-- Delete old facts for patients who had the phenotype.
-------------------------------------------------------------------------

step_start_time := localtimestamp;
delete
	from DERIVED_FACT
	where concept_cd in (
		select 'DT|' || phenotype
		from dt_komap_phenotype
		where generate_facts=1
	);
usp_dt_print(step_start_time, '  delete from DERIVED_FACT', sql%Rowcount);


-------------------------------------------------------------------------
-- Generate new derived facts for patients who now have the phenotype.
-------------------------------------------------------------------------

step_start_time := localtimestamp;
insert into DERIVED_FACT (encounter_num, patient_num, concept_cd, provider_id, start_date, modifier_cd, instance_num)
	select -1, patient_num, 'DT|' || phenotype, '@', sysdate, '@', 1
	from dt_komap_phenotype_patient;
usp_dt_print(step_start_time, '  insert into DERIVED_FACT', sql%Rowcount);

execute immediate 'analyze table DERIVED_FACT compute statistics';

usp_dt_print(proc_start_time, 'usp_dt_komap_generate_phenotype', null);

END;
/

