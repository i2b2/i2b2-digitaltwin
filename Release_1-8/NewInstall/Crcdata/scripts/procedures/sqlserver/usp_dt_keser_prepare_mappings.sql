--##############################################################################
--##############################################################################
--### KESER - Prepare Mappings
--### Date: September 1, 2023
--### Database: Microsoft SQL Server
--### Created By: Griffin Weber (weber@hms.harvard.edu)
--##############################################################################
--##############################################################################


-- Drop the procedure if it already exists
IF OBJECT_ID(N'dbo.usp_dt_keser_prepare_mappings') IS NOT NULL DROP PROCEDURE dbo.usp_dt_keser_prepare_mappings;
GO


CREATE PROCEDURE dbo.usp_dt_keser_prepare_mappings
AS
BEGIN

SET NOCOUNT ON;


--------------------------------------------------------------------------------
-- Truncate tables to remove old data.
--------------------------------------------------------------------------------

--truncate table dbo.dt_keser_import_concept_feature;
truncate table dbo.dt_keser_feature;
truncate table dbo.dt_keser_concept_feature;
truncate table dbo.dt_keser_concept_children;


--------------------------------------------------------------------------------
-- Import the KeserConceptFeature.tsv file.
--------------------------------------------------------------------------------

-- This is a manual step.
-- Import the file KeserConceptFeature.tsv file
-- into the table dbo.dt_keser_import_concept_feature


--------------------------------------------------------------------------------
-- Change concept prefixes to match your ontology.
--------------------------------------------------------------------------------

-- Edit this query as needed.
update dbo.dt_keser_import_concept_feature
	set concept_cd = (
		case
		--when concept_cd like 'DIAG|ICD9CM:%' then replace(concept_cd,'DIAG|ICD9CM:','ICD9CM:')
		--when concept_cd like 'DIAG|ICD10CM:%' then replace(concept_cd,'DIAG|ICD10CM:','ICD10CM:')
		--when concept_cd like 'PROC|ICD9PROC:%' then replace(concept_cd,'PROC|ICD9PROC:','ICD9PROC:')
		--when concept_cd like 'PROC|ICD10PCS:%' then replace(concept_cd,'PROC|ICD10PCS:','ICD10PCS:')
		--when concept_cd like 'PROC|CPT4:%' then replace(concept_cd,'PROC|CPT4:','CPT4:')
		--when concept_cd like 'MED|RXNORM:%' then replace(concept_cd,'MED|RXNORM:','RXNORM:')
		--when concept_cd like 'LAB|LOINC:%' then replace(concept_cd,'LAB|LOINC:','LOINC:')
		when 1=0 then concept_cd
		else concept_cd
		end
	);
		

--------------------------------------------------------------------------------
-- Assign an integer feature_num to each feature.
--------------------------------------------------------------------------------

insert into dbo.dt_keser_feature (feature_num, feature_cd, feature_name)
	select row_number() over (order by feature_cd) feature_num, 
		feature_cd, feature_name
	from (
		select feature_cd, max(feature_name) feature_name 
		from dbo.dt_keser_import_concept_feature 
		group by feature_cd
	) t;

insert into dbo.dt_keser_concept_feature (concept_cd, feature_num)
	select distinct c.concept_cd, f.feature_num
	from dbo.dt_keser_import_concept_feature c
		inner join dbo.dt_keser_feature f
			on c.feature_cd=f.feature_cd;


--------------------------------------------------------------------------------
-- Use the concept_dimension to get child concepts under each concept_cd.
--------------------------------------------------------------------------------

;with cte_concept_parent (parent_path,concept_cd,is_anchor) as (
	select concept_path, concept_cd, 1
		from dbo.concept_dimension
		where concept_cd is not null
			and concept_cd in (select concept_cd from dbo.observation_fact)
	union all
	select LEFT(parent_path, LEN(parent_path)-CHARINDEX('\', RIGHT(REVERSE(parent_path), LEN(parent_path)-1))), concept_cd, 0
		from cte_concept_parent
		where parent_path<>'\'
)
insert into dbo.dt_keser_concept_children (concept_cd, child_cd)
	select distinct c.concept_cd, t.child_cd
	from (
		select distinct isnull(parent_path,'') parent_path, isnull(concept_cd,'') child_cd
		from cte_concept_parent
		where is_anchor=0 and parent_path<>'\'
	) t inner join dbo.concept_dimension c
		on t.parent_path=c.concept_path;


--------------------------------------------------------------------------------
-- Insert additional child concepts to the dt_keser_concept_feature table.
--------------------------------------------------------------------------------

insert into dbo.dt_keser_concept_feature (concept_cd, feature_num)
	select distinct c.child_cd, f.feature_num
	from dbo.dt_keser_concept_feature f
		inner join dt_keser_concept_children c
			on f.concept_cd=c.concept_cd
	where not exists (
		select *
		from dbo.dt_keser_concept_feature g
		where f.feature_num=g.feature_num and c.child_cd=g.concept_cd
	);


END
GO

