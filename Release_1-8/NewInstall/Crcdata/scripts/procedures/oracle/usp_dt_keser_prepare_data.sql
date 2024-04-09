--##############################################################################
--##############################################################################
--### KESER - Prepare Data
--### Date: September 1, 2023
--### Database: Oracle
--### Created By: Griffin Weber (weber@hms.harvard.edu)
--##############################################################################
--##############################################################################


-- Drop the procedure if it already exists
BEGIN EXECUTE IMMEDIATE 'DROP PROCEDURE usp_dt_keser_prepare_data'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -4043 THEN RAISE; END IF; END;


CREATE PROCEDURE usp_dt_keser_prepare_data
AS
    proc_start_time timestamp := localtimestamp;
    step_start_time timestamp;
    loop_start_time timestamp;
    batch_size number(3,0);
    partition_start number(3,0);
    partition_end number(3,0);
BEGIN

--------------------------------------------------------------------------------
-- Truncate tables to remove old data.
--------------------------------------------------------------------------------

execute immediate 'truncate table dt_keser_patient_partition';
execute immediate 'truncate table dt_keser_patient_period_feature';
execute immediate 'truncate table dt_keser_feature_count';
execute immediate 'truncate table dt_keser_feature_cooccur_temp';
execute immediate 'truncate table dt_keser_feature_cooccur';
execute immediate 'truncate table dt_keser_embedding';
execute immediate 'truncate table dt_keser_phenotype';
execute immediate 'truncate table dt_keser_phenotype_feature';


--------------------------------------------------------------------------------
-- Divide patients into two cohorts: 80% training (cohort 0) and 20% test (cohort 1).
-- Then divide each cohort into 100 partitions.
-- Note that cohort 0 partitions will be 4x larger than cohort 1 partitions.
-- Assign a patient_partition to each patient, where:
-- partitions 0-99 are the training cohort, partitions 100-199 are the test cohort.
--------------------------------------------------------------------------------
step_start_time := localtimestamp;
insert into dt_keser_patient_partition (patient_num, patient_partition)
	select patient_num,
        100*cohort - 1 + ntile(100) over (partition by cohort order by dbms_random.value())
	from (
		select patient_num, (case when quintile=5 then 1 else 0 end) cohort
		from (
            select patient_num, ntile(5) over (order by dbms_random.value()) quintile
			from patient_dimension
		) t
	) t;
usp_dt_print(step_start_time, '  insert into dt_keser_patient_partition', sql%Rowcount);

execute immediate 'analyze table dt_keser_patient_partition compute statistics';


--------------------------------------------------------------------------------
-- Get a list of features for each patient by time period.
-- The default time period is 30 days.
-- The start date of time period 0 can be arbitrarily chosen.
-- Here we use the SQL Server default of Jan 1, 1900, as that start date.
-- *** This might take an hour or longer to run.
--------------------------------------------------------------------------------

step_start_time := localtimestamp;
insert into dt_keser_patient_period_feature (patient_partition, patient_num, time_period, feature_num, min_offset, max_offset)
	select p.patient_partition, f.patient_num, t.time_period, c.feature_num, min(t.offset_days), max(t.offset_days)
	from observation_fact f
		inner join dt_keser_patient_partition p
			on f.patient_num=p.patient_num
		inner join dt_keser_concept_feature c
			on f.concept_cd=c.concept_cd
		cross apply (select trunc((trunc(f.start_date) - to_date('1900-01-01', 'YYYY-DD-MM')) / 30) time_period,
                         mod(floor(trunc(f.start_date) - to_date('1900-01-01', 'YYYY-DD-MM')), 30) offset_days from dual) t
	group by p.patient_partition, f.patient_num, t.time_period, c.feature_num;
usp_dt_print(step_start_time, '  insert into dt_keser_patient_period_feature', sql%Rowcount);

execute immediate 'analyze table dt_keser_patient_period_feature compute statistics';


--------------------------------------------------------------------------------
-- For each cohort, get the number of patients for each feature (feature_count).
-- Delete the data for any features with fewer than 1000 patients.
--------------------------------------------------------------------------------

-- Calculate the number of patients per cohort-feature pair.
step_start_time := localtimestamp;
insert into dt_keser_feature_count (cohort, feature_num, feature_cd, feature_name, feature_count)
	select c.cohort, c.feature_num, f.feature_cd, f.feature_name, c.feature_count
	from (
		select cohort, feature_num, count(distinct patient_num) feature_count
		from dt_keser_patient_period_feature f
			cross apply (select (case when f.patient_partition <100 then 0 else 1 end) cohort from dual) t
		group by cohort, feature_num
	) c inner join dt_keser_feature f on c.feature_num=f.feature_num;
usp_dt_print(step_start_time, '  insert into dt_keser_feature_count', sql%Rowcount);
execute immediate 'analyze table dt_keser_feature_count compute statistics';

-- Delete low frequency features for cohort 0.
step_start_time := localtimestamp;
delete
	from dt_keser_patient_period_feature
	where patient_partition between 0 and 99
		and feature_num in (
			select feature_num
			from dt_keser_feature_count
			where cohort=0 and feature_count<1000
		);
usp_dt_print(step_start_time, '  delete from dt_keser_patient_period_feature [0-99]', sql%Rowcount);

-- Delete low frequency features for cohort 1.
delete
	from dt_keser_patient_period_feature
	where patient_partition between 100 and 199
		and feature_num in (
			select feature_num
			from dt_keser_feature_count
			where cohort=1 and feature_count<1000
		);
usp_dt_print(step_start_time, '  delete from dt_keser_patient_period_feature [100-199]', sql%Rowcount);


--------------------------------------------------------------------------------
-- Calculate the co-occurrence matrix.
-- The patient partitions are used to split the processing into batches.
-- The batch size can range from 1 to 100 partitions. The default is 10.
-- Adjust the batch size to optimize performance.
-- *** This might take several hours to run!
--------------------------------------------------------------------------------

-- Set initial values
batch_size := 10;
partition_start := 0;

-- Loop through batches
loop_start_time := localtimestamp;
while partition_start<200 loop
	-- Set the end partition for this batch
    partition_end :=
		(case when (partition_start < 100) and (partition_start + batch_size >= 100) then 99
			else partition_start + batch_size - 1
		end);

	-- Calcuate co-occurrences for this batch
    step_start_time := localtimestamp;
    insert into dt_keser_feature_cooccur_temp
		select (case when partition_start<100 then 0 else 1 end) cohort,
			feature_num1, feature_num2, count(distinct patient_num) num_patients
		from (
			select a.patient_num, a.feature_num feature_num1, b.feature_num feature_num2
				from dt_keser_patient_period_feature a inner join dt_keser_patient_period_feature b
					on a.patient_partition=b.patient_partition and a.patient_num=b.patient_num and a.feature_num<b.feature_num
						and a.time_period=b.time_period
				where a.patient_partition between partition_start and partition_end
			union all
			select a.patient_num, a.feature_num, b.feature_num
				from dt_keser_patient_period_feature a inner join dt_keser_patient_period_feature b
					on a.patient_partition=b.patient_partition and a.patient_num=b.patient_num and a.feature_num<b.feature_num
						and a.time_period=b.time_period-1 and b.min_offset<a.max_offset
				where a.patient_partition between partition_start and partition_end
			union all
			select a.patient_num, a.feature_num, b.feature_num
				from dt_keser_patient_period_feature a inner join dt_keser_patient_period_feature b
					on a.patient_partition=b.patient_partition and a.patient_num=b.patient_num and a.feature_num<b.feature_num
						and a.time_period=b.time_period+1 and a.min_offset<b.max_offset
				where a.patient_partition between partition_start and partition_end
		) t
		group by feature_num1, feature_num2;
    usp_dt_print(step_start_time, '    insert into dt_keser_feature_cooccur_temp ['
            || to_char(partition_start) || '-' || to_char(partition_end) || ']', sql%Rowcount);

	-- Set the start partition for the next batch
	partition_start :=
		(case when (partition_start < 100) and (partition_start + batch_size >= 100) then 100
			else partition_start + batch_size
		end);
end loop;
usp_dt_print(loop_start_time, '  insert into dt_keser_feature_cooccur_temp [all]', null);

-- Merge the batches, saving feature pairs with at least 10 patients
step_start_time := localtimestamp;
insert into dt_keser_feature_cooccur (cohort, feature_num1, feature_num2, coocur_count)
	select *
	from (
		select cohort, feature_num1, feature_num2, sum(num_patients) coocur_count
		from dt_keser_feature_cooccur_temp
		group by cohort, feature_num1, feature_num2
	) t
	where coocur_count>=10;
usp_dt_print(step_start_time, '  insert into dt_keser_feature_cooccur', sql%Rowcount);

execute immediate 'analyze table dt_keser_feature_cooccur compute statistics';

-- The individual batch results are no longer needed.
execute immediate 'truncate table dt_keser_feature_cooccur_temp';


--------------------------------------------------------------------------------
-- Create a list of features to convert into phenotypes.
-- Make sure the embeddings for the features exist in both cohorts
-- or else the KESER R script for embedding regression will fail!
--------------------------------------------------------------------------------


-- OPTION 1: For testing, just PheCodes 250.2 (T2DM) and 714.1 (RA)
insert into dt_keser_phenotype (phenotype) values ('PheCode:250.2');
insert into dt_keser_phenotype (phenotype) values ('PheCode:714.1');



-- OPTION 2: All PheCodes that appear in both cohorts (from cooccur).
-- Note that if embeddings fail to generate for a feature, this won't work.
-- insert into dt_keser_phenotype (phenotype)
-- 	select feature_cd
-- 	from (
-- 		select feature_num
-- 		from (
-- 			select distinct feature_num1 feature_num, cohort
--             from dt_keser_feature_cooccur
-- 		) t
-- 		group by feature_num
-- 		having count(*)=2
-- 	) t inner join dt_keser_feature f
-- 		on t.feature_num=f.feature_num
-- 	where f.feature_cd like 'PheCode:%';


-- OPTION 3: All PheCodes that appear in both cohorts (from embedding).
-- This is the best way to ensure embeddings exist in both cohorts.
-- However, you would need to run this AFTER embeddings are generated
-- by the first R script.
-- 
-- insert into dt_keser_phenotype (phenotype)
-- 	select feature_cd
-- 	from (
-- 		select feature_cd
-- 		from (
-- 			select distinct feature_cd, cohort
-- 			from dt_keser_embedding
-- 		) t
-- 		group by feature_cd
-- 		having count(*)=2
-- 	) t
-- 	where feature_cd like 'PheCode:%';



--------------------------------------------------------------------------------
-- Run the KESER R code.
--------------------------------------------------------------------------------

-- The R scripts can either read/write directly to the database,
-- or data can be passed between the database and R via CSV files.
-- To use CSV files, export the tables listed below to CSV files,
-- and then import the CSV files created by R to the database tables.
-- 
-- PART 1: Generate Embeddings
-- 1) Export to CSV: dt_keser_feature_cooccur --> dt_keser_feature_cooccur.csv
-- 2) Export to CSV: dt_keser_feature_count --> dt_keser_feature_count.csv
-- 3) Run in R: keser_embed.R
-- 4) Import from CSV: dt_keser_embedding.csv --> dt_keser_embedding
-- 
-- PART 2: Embedding Regression
-- 1) Export to CSV: dt_keser_embedding --> dt_keser_embedding.csv
-- 2) Run in R: keser_embed_regression.R
-- 3) Import from CSV: dt_keser_phenotype_feature.csv --> dt_keser_phenotype_feature
usp_dt_print(proc_start_time, 'usp_dt_keser_prepare_data', null);


END;
/
