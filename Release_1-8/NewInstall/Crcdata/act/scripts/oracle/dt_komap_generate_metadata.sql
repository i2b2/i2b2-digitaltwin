--##############################################################################
--##############################################################################
--### KOMAP - Generate Metadata
--### Date: May 11, 2024
--### Database: Oracle
--### Created By: Griffin Weber (weber@hms.harvard.edu)
--##############################################################################
--##############################################################################
-- NOTE: This script assumes the ACT_RESEARCH_V41 table of the ACT 4.1 Ontology
-- has been installed in your i2b2 ontology cell. It makes modifications to
-- this table to enable i2b2 users to include phenotypes in their queries.
-- The ACT 4.1 ontology is available at
-- https://ontology-store.s3.amazonaws.com/ACTOntologyV4.1/ENACT_V41_MSSQL_I2B2_TSV.zip
--------------------------------------------------------------------------------
-- Start by changing the name of the existing PheCode folder to clarify
-- that these are just code groupings and not probabilistic
--------------------------------------------------------------------------------
update ACT_RESEARCH_V41
	set C_NAME = 'PheCodes (Diagnosis Code Groups)'
	where C_FULLNAME = '\ACT\Research\Phenotyping\PheCode\';
--------------------------------------------------------------------------------
-- Unvalidated Phenotypes
--------------------------------------------------------------------------------
-- Insert the parent folder
insert into ACT_RESEARCH_V41 (C_HLEVEL, C_FULLNAME, C_NAME, C_SYNONYM_CD, C_VISUALATTRIBUTES, C_TOTALNUM, C_BASECODE, C_METADATAXML, C_FACTTABLECOLUMN, C_TABLENAME, C_COLUMNNAME, C_COLUMNDATATYPE, C_OPERATOR, C_DIMCODE, C_COMMENT, C_TOOLTIP, M_APPLIED_PATH, UPDATE_DATE, DOWNLOAD_DATE, IMPORT_DATE, SOURCESYSTEM_CD, VALUETYPE_CD, M_EXCLUSION_CD, C_PATH, C_SYMBOL)
	select 4 C_HLEVEL, 
		'\ACT\Research\Phenotyping\PheCodeDTNotValidated\' C_FULLNAME,
		'PheCodes (Probabilistic, Not Validated)' C_NAME,
		'N' C_SYNONYM_CD,
		'FA ' C_VISUALATTRIBUTES,
		null C_TOTALNUM,
		null C_BASECODE,
		null C_METADATAXML,
		'concept_cd' C_FACTTABLECOLUMN, 
		'concept_dimension' C_TABLENAME,
		'concept_path' C_COLUMNNAME,
		'T' C_COLUMNDATATYPE,
		'LIKE' C_OPERATOR,
		'\ACT\Research\Phenotyping\PheCodeDTNotValidated\' C_DIMCODE,
		null C_COMMENT,
		'Probabilistic PheCodes use automated machine learning algorithms to filter out data quality problems and select patients who most likely have the phenotype. WARNING: These have NOT been manually validated through chart review.' C_TOOLTIP,
		'@' M_APPLIED_PATH, 
		cast(sysdate as date) UPDATE_DATE,
		cast(sysdate as date) DOWNLOAD_DATE,
		cast(sysdate as date) IMPORT_DATE,
		'DigitalTwin' SOURCESYSTEM_CD, 
		null VALUETYPE_CD, 
		null M_EXCLUSION_CD,
		null C_PATH, 
		null C_SYMBOL
    from dual;
-- Insert the child concepts by replicating the existing PheCode Case ontology
insert into ACT_RESEARCH_V41 (C_HLEVEL, C_FULLNAME, C_NAME, C_SYNONYM_CD, C_VISUALATTRIBUTES, C_TOTALNUM, C_BASECODE, C_METADATAXML, C_FACTTABLECOLUMN, C_TABLENAME, C_COLUMNNAME, C_COLUMNDATATYPE, C_OPERATOR, C_DIMCODE, C_COMMENT, C_TOOLTIP, M_APPLIED_PATH, UPDATE_DATE, DOWNLOAD_DATE, IMPORT_DATE, SOURCESYSTEM_CD, VALUETYPE_CD, M_EXCLUSION_CD, C_PATH, C_SYMBOL)
	select C_HLEVEL-1 C_HLEVEL, 
		replace(replace(replace(C_FULLNAME,'\ACT\Research\Phenotyping\PheCode\Case\','\ACT\Research\Phenotyping\PheCodeDTNotValidated\'),'_',''),':','') C_FULLNAME, 
        case when substr(rtrim(C_NAME),length(rtrim(C_NAME)),1)=')' then substr(C_NAME,1,length(rtrim(C_NAME))-1) || ', ' else rtrim(C_NAME) || ' (' end || 'Probabilistic, Not Validated)' C_NAME,
		C_SYNONYM_CD,
		C_VISUALATTRIBUTES,
		C_TOTALNUM, 
		'DT|' || C_BASECODE C_BASECODE,
		C_METADATAXML,
		C_FACTTABLECOLUMN,
		C_TABLENAME,
		C_COLUMNNAME,
		C_COLUMNDATATYPE,
		C_OPERATOR,
		replace(replace(replace(C_DIMCODE,'\ACT\Research\Phenotyping\PheCode\Case\','\ACT\Research\Phenotyping\PheCodeDTNotValidated\'),'_',''),':','') C_DIMCODE, 
		C_COMMENT, 
		replace(C_TOOLTIP,'\ACT\Research\Phenotyping\PheCode\Case\','\ACT\Research\Phenotyping\PheCodeDTNotValidated\') C_TOOLTIP,
		M_APPLIED_PATH, 
		cast(sysdate as date) UPDATE_DATE, 
		cast(sysdate as date) DOWNLOAD_DATE, 
		cast(sysdate as date) IMPORT_DATE, 
		'DigitalTwin' SOURCESYSTEM_CD, 
		VALUETYPE_CD, 
		M_EXCLUSION_CD,
		C_PATH, 
		C_SYMBOL
	from ACT_RESEARCH_V41
	where c_fullname like '\ACT\Research\Phenotyping\PheCode\Case\_%'
		and (c_basecode is null or c_basecode not like 'ICD%');
-- Do not include the ICD mappings
-- Change folders to leaf concepts if they do not have any children
update ACT_RESEARCH_V41
	set C_VISUALATTRIBUTES = 'LA '
	where C_FULLNAME like '\ACT\Research\Phenotyping\PheCodeDTNotValidated\%'
		and C_FULLNAME not in (
            select substr(C_FULLNAME, length(C_FULLNAME) - instr(reverse(C_FULLNAME), '\', 2) + 1)
			from ACT_RESEARCH_V41
			where C_FULLNAME like '\ACT\Research\Phenotyping\PheCodeDTNotValidated\%'		
		);
--------------------------------------------------------------------------------
-- Validated Phenotypes
-- Note: These are hidden by defauilt. Once manual chart review is done to
-- validate the phenotypes, change the second character of C_VISUALATTRIBUTES
-- to "A" and enter the correct PPV and Recall in the C_NAME field.
--------------------------------------------------------------------------------
-- Insert the parent folder
insert into ACT_RESEARCH_V41 (C_HLEVEL, C_FULLNAME, C_NAME, C_SYNONYM_CD, C_VISUALATTRIBUTES, C_TOTALNUM, C_BASECODE, C_METADATAXML, C_FACTTABLECOLUMN, C_TABLENAME, C_COLUMNNAME, C_COLUMNDATATYPE, C_OPERATOR, C_DIMCODE, C_COMMENT, C_TOOLTIP, M_APPLIED_PATH, UPDATE_DATE, DOWNLOAD_DATE, IMPORT_DATE, SOURCESYSTEM_CD, VALUETYPE_CD, M_EXCLUSION_CD, C_PATH, C_SYMBOL)
	select 4 C_HLEVEL, 
		'\ACT\Research\Phenotyping\PheCodeDTValidated\' C_FULLNAME,
		'PheCodes (Probabilistic, Validated)' C_NAME,
		'N' C_SYNONYM_CD,
		'FH ' C_VISUALATTRIBUTES,
		null C_TOTALNUM,
		null C_BASECODE,
		null C_METADATAXML,
		'concept_cd' C_FACTTABLECOLUMN, 
		'concept_dimension' C_TABLENAME,
		'concept_path' C_COLUMNNAME,
		'T' C_COLUMNDATATYPE,
		'LIKE' C_OPERATOR,
		'\ACT\Research\Phenotyping\PheCodeDTValidated\' C_DIMCODE,
		null C_COMMENT,
		'Probabilistic PheCodes use automated machine learning algorithms to filter out data quality problems and select patients who most likely have the phenotype. NOTE: These have been manually validated through chart review.' C_TOOLTIP,
		'@' M_APPLIED_PATH, 
		cast(sysdate as date) UPDATE_DATE,
		cast(sysdate as date) DOWNLOAD_DATE,
		cast(sysdate as date) IMPORT_DATE,
		'DigitalTwin' SOURCESYSTEM_CD, 
		null VALUETYPE_CD, 
		null M_EXCLUSION_CD,
		null C_PATH, 
		null C_SYMBOL
	from dual;
-- Insert the child concepts by replicating the existing PheCode Case ontology and flattening the hierarchy.
insert into ACT_RESEARCH_V41 (C_HLEVEL, C_FULLNAME, C_NAME, C_SYNONYM_CD, C_VISUALATTRIBUTES, C_TOTALNUM, C_BASECODE, C_METADATAXML, C_FACTTABLECOLUMN, C_TABLENAME, C_COLUMNNAME, C_COLUMNDATATYPE, C_OPERATOR, C_DIMCODE, C_COMMENT, C_TOOLTIP, M_APPLIED_PATH, UPDATE_DATE, DOWNLOAD_DATE, IMPORT_DATE, SOURCESYSTEM_CD, VALUETYPE_CD, M_EXCLUSION_CD, C_PATH, C_SYMBOL)
	select 5 C_HLEVEL,
		'\ACT\Research\Phenotyping\PheCodeDTValidated\' || C_BASECODE || '\' C_FULLNAME,
        case when substr(rtrim(C_NAME),length(rtrim(C_NAME)),1)=')' then substr(C_NAME,1,length(rtrim(C_NAME))-1) || ', ' else rtrim(C_NAME) || ' (' end || 'Probabilistic, PPV=TBD, Recall=TBD)' C_NAME,
		C_SYNONYM_CD,
		'LH ' C_VISUALATTRIBUTES, 
		null C_TOTALNUM, 
		'DT|' || C_BASECODE C_BASECODE,
		C_METADATAXML, 
		C_FACTTABLECOLUMN, 
		C_TABLENAME, 
		C_COLUMNNAME, 
		C_COLUMNDATATYPE, 
		C_OPERATOR, 
		'\ACT\Research\Phenotyping\PheCodeDTValidated\' || C_BASECODE || '\' C_DIMCODE,
		C_COMMENT, 
		replace(C_TOOLTIP,'\ACT\Research\Phenotyping\PheCode\Case\','\ACT\Research\Phenotyping\PheCodeDTValidated\') C_TOOLTIP,
		M_APPLIED_PATH, 
		cast(sysdate as date) UPDATE_DATE, 
		cast(sysdate as date) DOWNLOAD_DATE, 
		cast(sysdate as date) IMPORT_DATE, 
		'DigitalTwin' SOURCESYSTEM_CD, 
		VALUETYPE_CD, 
		M_EXCLUSION_CD,
		C_PATH, 
		C_SYMBOL
	from ACT_RESEARCH_V41
	where c_fullname like '\ACT\Research\Phenotyping\PheCode\Case\_%'
		and c_basecode like 'PHECODE:%';
--------------------------------------------------------------------------------
-- Base Cohort
--------------------------------------------------------------------------------
insert into ACT_RESEARCH_V41 (C_HLEVEL, C_FULLNAME, C_NAME, C_SYNONYM_CD, C_VISUALATTRIBUTES, C_TOTALNUM, C_BASECODE, C_METADATAXML, C_FACTTABLECOLUMN, C_TABLENAME, C_COLUMNNAME, C_COLUMNDATATYPE, C_OPERATOR, C_DIMCODE, C_COMMENT, C_TOOLTIP, M_APPLIED_PATH, UPDATE_DATE, DOWNLOAD_DATE, IMPORT_DATE, SOURCESYSTEM_CD, VALUETYPE_CD, M_EXCLUSION_CD, C_PATH, C_SYMBOL)
	select 4 C_HLEVEL, 
		'\ACT\Research\Phenotyping\BaseCohort\' C_FULLNAME,
		'zz Base Cohort (3+ Diagnosis Dates Since 2010)' C_NAME,
		'N' C_SYNONYM_CD,
		'LA ' C_VISUALATTRIBUTES,
		null C_TOTALNUM,
		'DT|BaseCohort' C_BASECODE,
		null C_METADATAXML,
		'concept_cd' C_FACTTABLECOLUMN, 
		'concept_dimension' C_TABLENAME,
		'concept_path' C_COLUMNNAME,
		'T' C_COLUMNDATATYPE,
		'LIKE' C_OPERATOR,
		'\ACT\Research\Phenotyping\BaseCohort\' C_DIMCODE,
		null C_COMMENT,
		'The base cohort represents patients with the minimal amount of data required to generate probabilistic PheCodes.' C_TOOLTIP,
		'@' M_APPLIED_PATH, 
		cast(sysdate as date) UPDATE_DATE,
		cast(sysdate as date) DOWNLOAD_DATE,
		cast(sysdate as date) IMPORT_DATE,
		'DigitalTwin' SOURCESYSTEM_CD, 
		null VALUETYPE_CD, 
		null M_EXCLUSION_CD,
		null C_PATH, 
		null C_SYMBOL
	from dual;