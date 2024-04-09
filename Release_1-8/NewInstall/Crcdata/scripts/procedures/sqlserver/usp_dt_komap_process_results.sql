--##############################################################################
--##############################################################################
--### KOMAP - Process Results
--### Date: September 1, 2023
--### Database: Microsoft SQL Server
--### Created By: Griffin Weber (weber@hms.harvard.edu)
--##############################################################################
--##############################################################################


-- Drop the procedure if it already exists
IF OBJECT_ID(N'dbo.usp_dt_komap_process_results') IS NOT NULL DROP PROCEDURE dbo.usp_dt_komap_process_results;
GO


CREATE PROCEDURE dbo.usp_dt_komap_process_results
AS
BEGIN

SET NOCOUNT ON;


--------------------------------------------------------------------------------
-- Truncate tables to remove old data.
--------------------------------------------------------------------------------

truncate table dbo.dt_komap_phenotype_sample_results;
truncate table dbo.dt_komap_phenotype_gmm;
--truncate table dbo.dt_komap_phenotype_gold_standard;
truncate table dbo.dt_komap_phenotype_patient;


-------------------------------------------------------------------------
-- Run the phenotype models for each of the sampled patients.
-------------------------------------------------------------------------

insert into dbo.dt_komap_phenotype_sample_results (phenotype, patient_num, score, phecode_dates, utilization_dates, phecode_score, utilization_score, other_positive_feature_score, other_negative_feature_score)
	select c.phenotype, f.patient_num, sum(f.log_dates*c.coef) score,
		max(case when f.feature_cd=c.phenotype then f.num_dates else 0 end) phecode_dates,
		max(case when f.feature_cd='Utilization:IcdDates' then f.num_dates else 0 end) utilization_dates,
		sum(case when f.feature_cd=c.phenotype then f.log_dates*c.coef else 0 end) phecode_score,
		sum(case when f.feature_cd='Utilization:IcdDates' then f.log_dates*c.coef else 0 end) utilization_score,
		sum(case when f.feature_cd not in (c.phenotype,'Utilization:IcdDates') and coef>0 then log_dates*coef else 0 end) other_positive_feature_score,
		sum(case when f.feature_cd not in (c.phenotype,'Utilization:IcdDates') and coef<0 then log_dates*coef else 0 end) other_negative_feature_score
	from dbo.dt_komap_phenotype_feature_coef c
		inner join dbo.dt_komap_phenotype_sample s
			on c.phenotype=s.phenotype
		inner join dbo.dt_komap_patient_feature f
			on c.feature_cd=f.feature_cd and f.patient_num=s.patient_num
	group by c.phenotype, f.patient_num;


-------------------------------------------------------------------------
-- Run Gaussian mixture model (GMM) clustering to determine score threshold.
-------------------------------------------------------------------------

-- Divide the score for each phenotype into 100 percentiles
insert into dbo.dt_komap_phenotype_gmm (phenotype, score_percentile, score)
	select phenotype, score_percentile, avg(score) score
	from (
		select *, ntile(100) over (partition by phenotype order by score) score_percentile
		from dt_komap_phenotype_sample_results
	) t
	group by phenotype, score_percentile;

-- Set the initial GMM parameters
update g
	set g.m1 = (select avg(score)-stdev(score) from dbo.dt_komap_phenotype_gmm t where t.phenotype=g.phenotype),
		g.m2 = (select avg(score)+stdev(score) from dbo.dt_komap_phenotype_gmm t where t.phenotype=g.phenotype),
		g.s1 = (select stdev(score) from dbo.dt_komap_phenotype_gmm t where t.phenotype=g.phenotype),
		g.s2 = (select stdev(score) from dbo.dt_komap_phenotype_gmm t where t.phenotype=g.phenotype)
	from dbo.dt_komap_phenotype_gmm g;

-- Run the Expectation-Maximization (EM) algorithm for GMM
declare @gmm_iteration int;
select @gmm_iteration=0;
while (@gmm_iteration<100) -- Tune as needed
begin
	-- EXPECTATION STEP
	-- Calculate the normal distribution (m=mean, s=stdev) for each score
	update g
		set g.g1 = exp(-0.5*(score-m1)*(score-m1)/s1/s1)/s1/sqrt(2*pi()),
			g.g2 = exp(-0.5*(score-m2)*(score-m2)/s2/s2)/s2/sqrt(2*pi())
		from dbo.dt_komap_phenotype_gmm g;
	-- Calculate likelihood of each score being in each cluster
	update g
		set g.p1 = g1/(g1+g2),
			g.p2 = g2/(g1+g2)
		from dbo.dt_komap_phenotype_gmm g;

	-- MAXIMIZATION STEP
	-- Estimate the new means
	update g
		set g.m1 = (select sum(p1*score)/sum(p1) from dbo.dt_komap_phenotype_gmm t where t.phenotype=g.phenotype),
			g.m2 = (select sum(p2*score)/sum(p2) from dbo.dt_komap_phenotype_gmm t where t.phenotype=g.phenotype)
		from dbo.dt_komap_phenotype_gmm g;
	-- Estimate the new standard deviations
	update g
		set g.s1 = (select sqrt(sum(p1*(score-m1)*(score-m1))/sum(p1)) from dbo.dt_komap_phenotype_gmm t where t.phenotype=g.phenotype),
			g.s2 = (select sqrt(sum(p2*(score-m2)*(score-m2))/sum(p2)) from dbo.dt_komap_phenotype_gmm t where t.phenotype=g.phenotype)
		from dbo.dt_komap_phenotype_gmm g;

	-- Next iteration
	select @gmm_iteration = @gmm_iteration + 1;
 	
-- 	-- Evaluate the log-likelihood to confirm convergence
-- 	select avg(l)
-- 		from (
-- 			select phenotype, sum(log((g1*p1 + g2*p2))) l
-- 			from #gmm
-- 			group by phenotype
-- 		) t;

end;


-------------------------------------------------------------------------
-- Save the GMM results to the dt_komap_phenotype table.
-------------------------------------------------------------------------

-- Threshold
-- (Target PPV>=0.9, but listed here as PPV>=0.92 to give a small buffer.)
update p
	set p.threshold = (
		select min(score) threshold
		from (
			select *, avg(p2) over (order by score_percentile desc) ppv
			from dbo.dt_komap_phenotype_gmm g
			where g.phenotype=p.phenotype
		) t
		where p2>=p1 and score>m1 and ppv>=0.92
	)
	from dbo.dt_komap_phenotype p;
	
-- Mean1
update p
	set p.gmm_mean1 = (
		select min(m1) m1
		from dbo.dt_komap_phenotype_gmm g
		where g.phenotype=p.phenotype
	)
	from dbo.dt_komap_phenotype p;

-- Mean2
update p
	set p.gmm_mean2 = (
		select min(m2) m2
		from dbo.dt_komap_phenotype_gmm g
		where g.phenotype=p.phenotype
	)
	from dbo.dt_komap_phenotype p;

-- StDev1
update p
	set p.gmm_stdev1 = (
		select min(s1) s1
		from dbo.dt_komap_phenotype_gmm g
		where g.phenotype=p.phenotype
	)
	from dbo.dt_komap_phenotype p;

-- StDev2
update p
	set p.gmm_stdev2 = (
		select min(s2) s2
		from dbo.dt_komap_phenotype_gmm g
		where g.phenotype=p.phenotype
	)
	from dbo.dt_komap_phenotype p;


-------------------------------------------------------------------------
-- Create a gold standard.
-------------------------------------------------------------------------

-- OPTION 1: Randomly select patients with the PheCode and perform manual chart review.
-- Make sure you have at least 15 patients in the base cohort.
-- This is the most accurate way to create a gold standard.

-- OPTION 2: Simulate based on the results of the GMM.
-- This is just an estimate if you cannot perform chart review.
insert into dbo.dt_komap_phenotype_gold_standard (phenotype, patient_num, has_phenotype)
	select s.phenotype, s.patient_num,
		(case when g2/(g1+g2) >= abs(binary_checksum(newid())/2147483648.0) then 1 else 0 end) has_phenotype
	from (
			select *, row_number() over (partition by phenotype order by newid()) k
			from dbo.dt_komap_phenotype_sample_results
		) s
		inner join dbo.dt_komap_phenotype p
			on s.phenotype=p.phenotype
		cross apply (
			select exp(-0.5*(score-gmm_mean1)*(score-gmm_mean1)/gmm_stdev1/gmm_stdev1)/gmm_stdev1/sqrt(2*pi()) g1,
				exp(-0.5*(score-gmm_mean2)*(score-gmm_mean2)/gmm_stdev2/gmm_stdev2)/gmm_stdev2/sqrt(2*pi()) g2
		) g
	where s.k<1000


-------------------------------------------------------------------------
-- Calculate the phenotype score of each gold standard patient.
-------------------------------------------------------------------------

update g
	set g.score = (
		select sum(f.log_dates*c.coef)
		from dbo.dt_komap_phenotype_feature_coef c
			inner join dbo.dt_komap_patient_feature f
				on f.patient_num=g.patient_num and f.feature_cd=c.feature_cd
		where c.phenotype=g.phenotype
			and g.patient_num in (select patient_num from dbo.dt_komap_base_cohort)
	)
	from dbo.dt_komap_phenotype_gold_standard g;


-------------------------------------------------------------------------
-- Calculate the PPV (precision) and recall of each phenotype.
-------------------------------------------------------------------------

update p
	set p.ppv = (
		select avg(cast(has_phenotype as float))
		from dbo.dt_komap_phenotype_gold_standard g
		where g.phenotype=p.phenotype and g.score>=p.threshold
	)
	from dbo.dt_komap_phenotype p;

update p
	set p.recall = (
		select avg(cast(pred_phenotype as float))
		from dbo.dt_komap_phenotype_gold_standard g
			cross apply (select (case when g.score>=p.threshold then 1 else 0 end) pred_phenotype) x
		where g.phenotype=p.phenotype and g.score is not null and g.has_phenotype=1
	)
	from dbo.dt_komap_phenotype p;


-------------------------------------------------------------------------
-- Calculate additional phenotype evaluation metrics.
-------------------------------------------------------------------------

-- Number of patients assigned the phenotype / Number of patients in the base cohort with the phenotype's feature
update p
	set p.recall_base_cohort = (
		select avg(cast(pred_phenotype as float))
		from dbo.dt_komap_phenotype_gold_standard g
			cross apply (select (case when g.score>=p.threshold then 1 else 0 end) pred_phenotype) x
		where g.phenotype=p.phenotype and g.score is not null
	)
	from dbo.dt_komap_phenotype p;

-- Number of patients in the base cohort with the phenotype's feature / Number of all patients with the phenotype's feature
update p
	set p.frac_feature_in_base_cohort = (
		select avg(cast((case when b.patient_num is not null then 1 else 0 end) as float))
		from dbo.dt_komap_patient_feature f
			left outer join dbo.dt_komap_base_cohort b
				on f.patient_num=b.patient_num
		where f.feature_cd=p.phenotype
	)
	from dbo.dt_komap_phenotype p;

-- Number of patients assigned the phenotype / Number of all patients with the phenotype's feature
update p
	set p.recall_has_feature = recall_base_cohort * frac_feature_in_base_cohort
	from dbo.dt_komap_phenotype p;
	
	
-------------------------------------------------------------------------
-- Generate derived phenotype facts when the PPV >= 0.9.
-------------------------------------------------------------------------

update dbo.dt_komap_phenotype
	set generate_facts = (case when ppv>=0.9 then 1 else 0 end);
	

END
GO

