--##############################################################################
--##############################################################################
--### KESER - Prepare Mappings
--### Date: September 1, 2023
--### Database: Oracle
--### Created By: Griffin Weber (weber@hms.harvard.edu)
--##############################################################################
--##############################################################################


-- Drop the procedure if it already exists
BEGIN EXECUTE IMMEDIATE 'DROP PROCEDURE usp_dt_keser_prepare_mappings'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -4043 THEN RAISE; END IF; END;

CREATE PROCEDURE usp_dt_keser_prepare_mappings
AS
    proc_start_time timestamp := localtimestamp;
    step_start_time timestamp;
BEGIN



--------------------------------------------------------------------------------
-- Truncate tables to remove old data.
--------------------------------------------------------------------------------

--truncate table dt_keser_import_concept_feature;
execute immediate 'truncate table dt_keser_feature';
execute immediate 'truncate table dt_keser_concept_feature';
execute immediate 'truncate table dt_keser_concept_children';


--------------------------------------------------------------------------------
-- Import the KeserConceptFeature.tsv file.
--------------------------------------------------------------------------------

-- This is a manual step.
-- Import the file KeserConceptFeature.tsv file
-- into the table dt_keser_import_concept_feature


--------------------------------------------------------------------------------
-- Change concept prefixes to match your ontology.
--------------------------------------------------------------------------------

-- Edit this query as needed.
step_start_time := localtimestamp;
update dt_keser_import_concept_feature
	set concept_cd = (
		case
		when concept_cd like 'DIAG|ICD9CM:%' then replace(concept_cd,'DIAG|ICD9CM:','ICD9CM:')
		when concept_cd like 'DIAG|ICD10CM:%' then replace(concept_cd,'DIAG|ICD10CM:','ICD10CM:')
		when concept_cd like 'PROC|ICD9PROC:%' then replace(concept_cd,'PROC|ICD9PROC:','ICD9Proc:')
		when concept_cd like 'PROC|ICD10PCS:%' then replace(concept_cd,'PROC|ICD10PCS:','ICD10PCS:')
		when concept_cd like 'PROC|CPT4:%' then replace(concept_cd,'PROC|CPT4:','CPT4:')
		when concept_cd like 'MED|RXNORM:%' then replace(concept_cd,'MED|RXNORM:','RxNorm:')
		when concept_cd like 'LAB|LOINC:%' then replace(concept_cd,'LAB|LOINC:','LOINC:')
		when 1=0 then concept_cd
		else concept_cd
		end
	);
usp_dt_print(step_start_time, '  update dt_keser_import_concept_feature', sql%Rowcount);
execute immediate 'analyze table DT_KESER_IMPORT_CONCEPT_FEATURE compute statistics';

--------------------------------------------------------------------------------
-- Assign an integer feature_num to each feature.
--------------------------------------------------------------------------------

step_start_time := localtimestamp;
insert into dt_keser_feature (feature_num, feature_cd, feature_name)
	select row_number() over (order by feature_cd) feature_num, 
		feature_cd, feature_name
	from (
		select feature_cd, max(feature_name) feature_name 
		from dt_keser_import_concept_feature
		group by feature_cd
	) t;
usp_dt_print(step_start_time, '  insert into dt_keser_feature', sql%Rowcount);
execute immediate 'analyze table DT_KESER_FEATURE compute statistics';

step_start_time := localtimestamp;
insert into dt_keser_concept_feature (concept_cd, feature_num)
	select distinct c.concept_cd, f.feature_num
	from dt_keser_import_concept_feature c
		inner join dt_keser_feature f
			on c.feature_cd=f.feature_cd;
usp_dt_print(step_start_time, '  insert into dt_keser_concept_feature', sql%Rowcount);
execute immediate 'analyze table DT_KESER_CONCEPT_FEATURE compute statistics';


--------------------------------------------------------------------------------
-- Use the concept_dimension to get child concepts under each concept_cd.
--------------------------------------------------------------------------------

step_start_time := localtimestamp;
insert into dt_keser_concept_children (concept_cd, child_cd)
with cte_concept_parent (parent_path,concept_cd,is_anchor) as (
	select concept_path, concept_cd, 1
		from concept_dimension
		where concept_cd is not null
			and concept_cd in (select concept_cd from observation_fact)
	union all
	select substr(parent_path, 1, length(parent_path) - instr(
            substr(reverse(parent_path), 2, length(parent_path) - 1), '\')), concept_cd, 0
	    from cte_concept_parent
	    where parent_path<>'\'
)
cycle parent_path, concept_cd set is_cycle to 1 default 0
select distinct c.concept_cd, t.child_cd
from (
    select distinct nvl(parent_path,'') parent_path, nvl(concept_cd,'') child_cd
    from cte_concept_parent
    where is_anchor=0 and parent_path<>'\'
) t inner join concept_dimension c
    on t.parent_path=c.concept_path;
usp_dt_print(step_start_time, '  insert into dt_keser_concept_children', sql%Rowcount);
execute immediate 'analyze table DT_KESER_CONCEPT_CHILDREN compute statistics';


--------------------------------------------------------------------------------
-- Insert additional child concepts to the dt_keser_concept_feature table.
--------------------------------------------------------------------------------

step_start_time := localtimestamp;
insert into dt_keser_concept_feature (concept_cd, feature_num)
	select distinct c.child_cd, f.feature_num
	from dt_keser_concept_feature f
		inner join dt_keser_concept_children c
			on f.concept_cd=c.concept_cd
	where not exists (
		select *
		from dt_keser_concept_feature g
		where f.feature_num=g.feature_num and c.child_cd=g.concept_cd
	);
usp_dt_print(step_start_time, '  insert into dt_keser_concept_feature (dt_keser_concept_children)', sql%Rowcount);
execute immediate 'analyze table DT_KESER_CONCEPT_FEATURE compute statistics';

usp_dt_print(proc_start_time, 'usp_dt_keser_prepare_mappings', null);


END;
/

