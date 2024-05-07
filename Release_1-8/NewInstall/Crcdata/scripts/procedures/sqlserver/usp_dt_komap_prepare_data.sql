--##############################################################################
--##############################################################################
--### KOMAP - Prepare Data
--### Date: April 23, 2024
--### Database: Microsoft SQL Server
--### Created By: Griffin Weber (weber@hms.harvard.edu)
--##############################################################################
--##############################################################################


-- Drop the procedure if it already exists
IF OBJECT_ID(N'dbo.usp_dt_komap_prepare_data') IS NOT NULL DROP PROCEDURE dbo.usp_dt_komap_prepare_data;;


CREATE PROCEDURE dbo.usp_dt_komap_prepare_data
AS
BEGIN

SET NOCOUNT ON;


--------------------------------------------------------------------------------
-- Truncate tables to remove old data.
--------------------------------------------------------------------------------

truncate table dbo.dt_komap_phenotype;
truncate table dbo.dt_komap_phenotype_feature_dict;
truncate table dbo.dt_komap_phenotype_sample;
truncate table dbo.dt_komap_phenotype_sample_feature;
truncate table dbo.dt_komap_phenotype_sample_feature_temp;
truncate table dbo.dt_komap_phenotype_covar_inner;
truncate table dbo.dt_komap_phenotype_covar;
truncate table dbo.dt_komap_phenotype_feature_coef;


-------------------------------------------------------------------------
-- Set the list of phenotypes to generate with KOMAP.
-------------------------------------------------------------------------

-- OPTION 1: For testing, just PheCodes 250.2 (T2DM) and 714.1 (RA)
insert into dbo.dt_komap_phenotype (phenotype, phenotype_name, generate_facts)
	select feature_cd, feature_name, 0
	from dbo.dt_keser_feature
	where feature_cd in ('PheCode:250.2','PheCode:714.1')


-- OPTION 2: A list of phenotypes that have been validated at Mass General Brigham hospitals.
--insert into dbo.dt_komap_phenotype (phenotype, phenotype_name, generate_facts)
--	select feature_cd, feature_name, 0
--	from dbo.dt_keser_feature
--	where feature_cd in (
--		'PheCode:157','PheCode:165.1','PheCode:172.1','PheCode:172.21','PheCode:174','PheCode:182','PheCode:184.11','PheCode:185','PheCode:189.1','PheCode:189.2',
--		'PheCode:191.11','PheCode:193','PheCode:202.2','PheCode:204','PheCode:244','PheCode:250.1','PheCode:250.2','PheCode:252.1','PheCode:256.4','PheCode:272.1',
--		'PheCode:274.1','PheCode:278.1','PheCode:284','PheCode:288.11','PheCode:290.11','PheCode:295.1','PheCode:296.1','PheCode:296.2','PheCode:297.1','PheCode:297.2',
--		'PheCode:300.3','PheCode:305.2','PheCode:313.3','PheCode:316','PheCode:317.1','PheCode:318','PheCode:327.32','PheCode:327.4','PheCode:332','PheCode:335',
--		'PheCode:340','PheCode:345.1','PheCode:395','PheCode:401','PheCode:411.2','PheCode:411.4','PheCode:415','PheCode:426.2','PheCode:427.21','PheCode:430',
--		'PheCode:433.2','PheCode:433.5','PheCode:442.1','PheCode:443','PheCode:452.2','PheCode:475','PheCode:480','PheCode:483','PheCode:530.14','PheCode:550',
--		'PheCode:555.1','PheCode:555.2','PheCode:562','PheCode:574.1','PheCode:577.1','PheCode:577.2','PheCode:585','PheCode:594','PheCode:714.1'
--	);

	
-- OPTION 3: All available phenotypes from KESER.
--insert into dbo.dt_komap_phenotype (phenotype, phenotype_name, generate_facts)
--	select feature_cd, feature_name, 0
--	from dbo.dt_keser_feature
--	where feature_cd in (select phenotype from dbo.dt_keser_phenotype);


-------------------------------------------------------------------------
-- Set the list of features for each phenotype.
-------------------------------------------------------------------------

insert into dbo.dt_komap_phenotype_feature_dict (phenotype, feature_cd, feature_name)
	select phenotype, feature_cd, max(feature_name)
	from (
		-- Include the phenotype's corresponding PheCode (required)
		select phenotype, phenotype feature_cd, phenotype_name feature_name
			from dbo.dt_komap_phenotype
		-- Include a healthcare utilization feature (required)
		union all
		select phenotype, 'Utilization:IcdDates' feature_cd, 'Utlization ICD Dates' feature_name
			from dbo.dt_komap_phenotype
		-- Include additional features suggested by KESER
		union all
		select p.phenotype, f.feature_cd, n.feature_name
			from dbo.dt_komap_phenotype p
				inner join dbo.dt_keser_phenotype_feature f
					on p.phenotype=f.phenotype
				inner join dbo.dt_keser_feature n
					on f.feature_cd=n.feature_cd
		-- Include additional custom features
		union all
		select phenotype, feature_cd, feature_name
			from dbo.dt_komap_phenotype p
				cross apply (
					select 'DEM|SEX:F' feature_cd, 'Female' feature_name
					union all select 'DEM|AGE:65plus', 'Age 65 plus'
					union all select 'DEM|AGE:55to64', 'Age 55 to 64'
					union all select 'DEM|AGE:45to54', 'Age 45 to 54'
					union all select 'DEM|AGE:35to44', 'Age 35 to 44'
					union all select 'DEM|AGE:18to34', 'Age 18 to 34'
					union all select 'DEM|AGE:Missing', 'Age Missing'
					union all select 'VITAL|BMI:30plus', 'BMI 30 plus'
					union all select 'VITAL|SMOKING:YES', 'Current or former smoker'
				) t
	) t
	group by phenotype, feature_cd;


-------------------------------------------------------------------------
-- Get a sample of up to 50,000 patients for each phenotype.
-- Use patients who have at least one occurrence of the feature.
-------------------------------------------------------------------------

insert into dbo.dt_komap_phenotype_sample (phenotype, patient_num)
	select phenotype, patient_num
	from (
		select p.phenotype, f.patient_num, row_number() over (partition by p.phenotype order by newid()) k
		from dbo.dt_komap_phenotype p
			inner join dbo.dt_komap_patient_feature f
				on p.phenotype=f.feature_cd
			inner join dbo.dt_komap_base_cohort b
				on f.patient_num=b.patient_num
	) t
	where k<=50000;	
-- For testing:
--select phenotype, count(*) n from dbo.dt_komap_phenotype_sample group by phenotype;


-------------------------------------------------------------------------
-- Get the features for patients in each phenotype sample
-------------------------------------------------------------------------

-- For all available phenotypes, this can take several hours and generate more than a billion rows
insert into dbo.dt_komap_phenotype_sample_feature (phenotype, patient_num, feature_cd, num_dates, log_dates)
	select f.phenotype, p.patient_num, p.feature_cd, p.num_dates, p.log_dates
	from dbo.dt_komap_phenotype_feature_dict f
		inner join dbo.dt_komap_phenotype_sample s
			on f.phenotype=s.phenotype
		inner join dbo.dt_komap_patient_feature p
			on s.patient_num=p.patient_num and f.feature_cd=p.feature_cd;


-------------------------------------------------------------------------
-- Calculate the "inner" covariance matrix for each phenotype.
-- This is the slower part (about a minute per phenotype).
-------------------------------------------------------------------------

-- Declare variables
declare @CurrentPhenotype varchar(50);
declare @PhenotypeNumber int;
declare @ProcessStartTime datetime;
declare @ProcessDurationMS int;

-- Set initial values
select @CurrentPhenotype = min(phenotype),
		@PhenotypeNumber = 1,
		@ProcessStartTime = GetDate()
	from dbo.dt_komap_phenotype;

-- Loop through each phenotype
while (@CurrentPhenotype is not null)
begin
	-- Delete data from the temp table
	truncate table dt_komap_phenotype_sample_feature_temp;

	-- Get the sample feature data for just this phenotype
	insert into dt_komap_phenotype_sample_feature_temp
		select * 
		from dbo.dt_komap_phenotype_sample_feature
		where phenotype = @CurrentPhenotype;

	-- Calculate the inner covariance matrix for this phenotype
	insert into dbo.dt_komap_phenotype_covar_inner
		select max(a.phenotype) phenotype, a.feature_cd feature_cd1, b.feature_cd feature_cd2, count(*) n, sum(a.log_dates * b.log_dates) d
		from dt_komap_phenotype_sample_feature_temp a
			inner join dt_komap_phenotype_sample_feature_temp b
				on a.patient_num=b.patient_num
		group by a.feature_cd, b.feature_cd;

	-- Remove comments to output a message that indicates progress
	--select @ProcessDurationMS = DateDiff(ms,@ProcessStartTime,GetDate());
	--RAISERROR(N'Finished phenotype %d (%s) in %d ms.', 1, 1, @PhenotypeNumber, @CurrentPhenotype, @ProcessDurationMS) with nowait;

	-- Move to the next phenotype
	select @CurrentPhenotype = min(phenotype),
			@PhenotypeNumber = @PhenotypeNumber + 1,
			@ProcessStartTime = GetDate()
		from dbo.dt_komap_phenotype
		where phenotype > @CurrentPhenotype;
end


-------------------------------------------------------------------------
-- Calculate the full covariance matrix for each phenotype.
-- This is the faster part (about a second per phenotype).
-------------------------------------------------------------------------
;with p as (
	select phenotype, count(*) phenotype_num_patients
	from dbo.dt_komap_phenotype_sample
	group by phenotype
), s as (
	select phenotype, feature_cd, count(*) feature_num_patients, sum(log_dates) feature_sum_log_dates
	from dbo.dt_komap_phenotype_sample_feature
	group by phenotype, feature_cd
), m as (
	select s.phenotype, s.feature_cd, s.feature_num_patients, s.feature_sum_log_dates,
		s.feature_sum_log_dates/cast(p.phenotype_num_patients as float) feature_mean,
		p.phenotype_num_patients
	from s inner join p on p.phenotype=s.phenotype
)
insert into dbo.dt_komap_phenotype_covar
	select a.phenotype, a.feature_cd, b.feature_cd,
		(isnull(c.sum_log_dates,0)
			- a.feature_mean*b.feature_sum_log_dates
			- b.feature_mean*a.feature_sum_log_dates
			+ a.feature_mean*b.feature_mean*(a.feature_num_patients+b.feature_num_patients-isnull(c.num_patients,0))
		) / cast(a.phenotype_num_patients-1 as float)
	from m a
		inner join m b
			on a.phenotype=b.phenotype
		left outer join dbo.dt_komap_phenotype_covar_inner c
			on a.phenotype=c.phenotype and a.feature_cd=c.feature_cd1 and b.feature_cd=c.feature_cd2;


-------------------------------------------------------------------------
-- Run the KOMAP R code.
-------------------------------------------------------------------------

-- --
-- 
-- The R script can either read/write directly to the database,
-- or data can be passed between the database and R via CSV files.
-- To use CSV files, export the tables listed below to CSV files,
-- and then import the CSV file created by R to the database table.
-- 
-- 1) Export to CSV: dbo.dt_komap_phenotype_feature_dict --> dt_komap_phenotype_feature_dict.csv
-- 2) Export to CSV: dbo.dt_komap_phenotype_covar --> dt_komap_phenotype_covar.csv
-- 3) Run in R: komap.R
-- 4) Import from CSV: dt_komap_phenotype_feature_coef.csv --> dbo.dt_komap_phenotype_feature_coef
-- 
-- 
-- 


END


