--##############################################################################
--##############################################################################
--### KOMAP - Process Results
--### Date: May 8, 2024
--### Database: Oracle
--### Created By: Griffin Weber (weber@hms.harvard.edu)
--##############################################################################
--##############################################################################


-- Drop the procedure if it already exists
-- BEGIN EXECUTE IMMEDIATE 'DROP PROCEDURE usp_dt_komap_process_results'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -4043 THEN RAISE; END IF; END;


CREATE OR REPLACE PROCEDURE usp_dt_komap_process_results
AS
    proc_start_time timestamp := localtimestamp;
    step_start_time timestamp;
    row_count int := 0;
    time_ms int;
    gmm_iteration int;
BEGIN



    --------------------------------------------------------------------------------
    -- Truncate tables to remove old data.
    --------------------------------------------------------------------------------

    execute immediate 'truncate table dt_komap_phenotype_sample_results';
    execute immediate 'truncate table dt_komap_phenotype_gmm';
    --execute immediate 'truncate table dt_komap_phenotype_gold_standard';
    execute immediate 'truncate table dt_komap_phenotype_patient';


    -------------------------------------------------------------------------
    -- Run the phenotype models for each of the sampled patients.
    -------------------------------------------------------------------------
    execute immediate 'analyze table dt_komap_phenotype_feature_coef compute statistics';

    step_start_time := localtimestamp;
    insert into dt_komap_phenotype_sample_results (phenotype, patient_num, score, phecode_dates, utilization_dates, phecode_score, utilization_score, other_positive_feature_score, other_negative_feature_score)
    select c.phenotype, f.patient_num, sum(f.log_dates*c.coef) score,
        max(case when f.feature_cd=c.phenotype then f.num_dates else 0 end) phecode_dates,
        max(case when f.feature_cd='Utilization:IcdDates' then f.num_dates else 0 end) utilization_dates,
        sum(case when f.feature_cd=c.phenotype then f.log_dates*c.coef else 0 end) phecode_score,
        sum(case when f.feature_cd='Utilization:IcdDates' then f.log_dates*c.coef else 0 end) utilization_score,
        sum(case when f.feature_cd not in (c.phenotype,'Utilization:IcdDates') and coef>0 then log_dates*coef else 0 end) other_positive_feature_score,
        sum(case when f.feature_cd not in (c.phenotype,'Utilization:IcdDates') and coef<0 then log_dates*coef else 0 end) other_negative_feature_score
    from dt_komap_phenotype_feature_coef c
         inner join dt_komap_phenotype_sample s
            on c.phenotype=s.phenotype
         inner join dt_komap_patient_feature f
            on c.feature_cd=f.feature_cd and f.patient_num=s.patient_num
    group by c.phenotype, f.patient_num;

    row_count := sql%Rowcount;
    time_ms := extract (day from (localtimestamp - step_start_time))*24*60*60 +
        extract (hour from (localtimestamp - step_start_time))*60*60+
        extract (minute from (localtimestamp - step_start_time))*60+
        round(extract(second from (localtimestamp - step_start_time))*1000);
    dbms_output.put_line('  insert into dt_komap_phenotype_sample_results, step time (ms): ' || to_char(time_ms) || ', rows: ' || to_char(row_count));

    execute immediate 'analyze table dt_komap_phenotype_sample_results compute statistics';

    -------------------------------------------------------------------------
    -- Run Gaussian mixture model (GMM) clustering to determine score threshold.
    -------------------------------------------------------------------------

    -- Divide the score for each phenotype into 100 percentiles
    step_start_time := localtimestamp;
    insert into dt_komap_phenotype_gmm (phenotype, score_percentile, score)
    select phenotype, score_percentile, avg(score)
    from (
        select phenotype, score, ntile(100) over (partition by phenotype order by score) score_percentile
        from dt_komap_phenotype_sample_results
    ) t
    group by phenotype, score_percentile;

    row_count := sql%Rowcount;
    time_ms := extract (day from (localtimestamp - step_start_time))*24*60*60 +
        extract (hour from (localtimestamp - step_start_time))*60*60+
        extract (minute from (localtimestamp - step_start_time))*60+
        round(extract(second from (localtimestamp - step_start_time))*1000);
    dbms_output.put_line('  insert into dt_komap_phenotype_gmm, step time (ms): ' || to_char(time_ms) || ', rows: ' || to_char(row_count));

    -- Set the initial GMM parameters
    step_start_time := localtimestamp;
    update dt_komap_phenotype_gmm g
    set g.m1 = (select avg(score) - stddev(score) from dt_komap_phenotype_gmm t where t.phenotype=g.phenotype),
        g.m2 = (select avg(score) + stddev(score) from dt_komap_phenotype_gmm t where t.phenotype=g.phenotype),
        g.s1 = (select stddev(score) from dt_komap_phenotype_gmm t where t.phenotype=g.phenotype),
        g.s2 = (select stddev(score) from dt_komap_phenotype_gmm t where t.phenotype=g.phenotype);

    row_count := sql%Rowcount;
    time_ms := extract (day from (localtimestamp - step_start_time))*24*60*60 +
        extract (hour from (localtimestamp - step_start_time))*60*60+
        extract (minute from (localtimestamp - step_start_time))*60+
        round(extract(second from (localtimestamp - step_start_time))*1000);
    dbms_output.put_line('  update dt_komap_phenotype_gmm, step time (ms): ' || to_char(time_ms) || ', rows: ' || to_char(row_count));

    -- Run the Expectation-Maximization (EM) algorithm for GMM
    gmm_iteration :=  0;
    step_start_time := localtimestamp;
    row_count := 0;
    while gmm_iteration < 100 loop-- Tune as needed
    -- EXPECTATION STEP
    -- Calculate the normal distribution (m=mean, s=stdev) for each score
        update dt_komap_phenotype_gmm g
        set g.g1 = exp(-0.5*(score-m1)*(score-m1)/s1/s1)/s1/sqrt(2 * acos(-1)),
            g.g2 = exp(-0.5*(score-m2)*(score-m2)/s2/s2)/s2/sqrt(2 * acos(-1));
        row_count := row_count + sql%rowcount;

        -- Calculate likelihood of each score being in each cluster
        update dt_komap_phenotype_gmm g
        set g.p1 = g1/(g1+g2),
            g.p2 = g2/(g1+g2);
        row_count := row_count + sql%rowcount;

        -- MAXIMIZATION STEP
        -- Estimate the new means
        update dt_komap_phenotype_gmm g
        set g.m1 = (select sum(p1*score)/sum(p1) from dt_komap_phenotype_gmm t where t.phenotype=g.phenotype),
            g.m2 = (select sum(p2*score)/sum(p2) from dt_komap_phenotype_gmm t where t.phenotype=g.phenotype);
        row_count := row_count + sql%rowcount;

        -- Estimate the new standard deviations
        update dt_komap_phenotype_gmm g
        set g.s1 = (select sqrt(sum(p1*(score-m1)*(score-m1))/sum(p1)) from dt_komap_phenotype_gmm t where t.phenotype=g.phenotype),
            g.s2 = (select sqrt(sum(p2*(score-m2)*(score-m2))/sum(p2)) from dt_komap_phenotype_gmm t where t.phenotype=g.phenotype);
        row_count := row_count + sql%rowcount;

        -- Next iteration
        gmm_iteration := gmm_iteration + 1;

        /*
        -- Evaluate the log-likelihood to confirm convergence
        select avg(l)
            from (
                select phenotype, sum(log((g1*p1 + g2*p2))) l
                from #gmm
                group by phenotype
            ) t;
        */

    end loop;

    time_ms := extract (day from (localtimestamp - step_start_time))*24*60*60 +
        extract (hour from (localtimestamp - step_start_time))*60*60+
        extract (minute from (localtimestamp - step_start_time))*60+
        round(extract(second from (localtimestamp - step_start_time))*1000);
    dbms_output.put_line('  update dt_komap_phenotype_gmm [all], step time (ms): ' || to_char(time_ms) || ', rows: ' || to_char(row_count));

    execute immediate 'analyze table dt_komap_phenotype_gmm compute statistics';

    -------------------------------------------------------------------------
    -- Save the GMM results to the dt_komap_phenotype table.
    -------------------------------------------------------------------------

    -- Threshold
    -- By default, based on when it becomes more likely that the patient has the phenotype.
    -- Alternatively, the threshold can be based on the estimated PPV.
    step_start_time := localtimestamp;
    row_count := 0;
    update dt_komap_phenotype p
    set p.threshold = (
        select min(score) threshold
        from (
            select g.score, g.p1, g.p2, g.m1, avg(g.p2) over (order by g.score_percentile desc) ppv
            from dt_komap_phenotype_gmm g
            where g.phenotype = p.phenotype
        ) t
        where t.p2>=t.p1 and t.score>t.m1 --and t.ppv>=0.92
    );
    row_count := row_count + sql%rowcount;

    -- Mean1
    update dt_komap_phenotype p
    set p.gmm_mean1 = (
        select min(g.m1) m1
        from dt_komap_phenotype_gmm g
        where g.phenotype=p.phenotype
    );
    row_count := row_count + sql%rowcount;

    -- Mean2
    update dt_komap_phenotype p
    set p.gmm_mean2 = (
        select min(g.m2) m2
        from dt_komap_phenotype_gmm g
        where g.phenotype=p.phenotype
    );
    row_count := row_count + sql%rowcount;

    -- StDev1
    update dt_komap_phenotype p
    set p.gmm_stdev1 = (
        select min(g.s1) s1
        from dt_komap_phenotype_gmm g
        where g.phenotype=p.phenotype
    );
    row_count := row_count + sql%rowcount;

    -- StDev2
    update dt_komap_phenotype p
    set p.gmm_stdev2 = (
        select min(g.s2) s2
        from dt_komap_phenotype_gmm g
        where g.phenotype=p.phenotype
    );
    row_count := row_count + sql%rowcount;

    time_ms := extract (day from (localtimestamp - step_start_time))*24*60*60 +
        extract (hour from (localtimestamp - step_start_time))*60*60+
        extract (minute from (localtimestamp - step_start_time))*60+
        round(extract(second from (localtimestamp - step_start_time))*1000);
    dbms_output.put_line('  update dt_komap_phenotype, step time (ms): ' || to_char(time_ms) || ', rows: ' || to_char(row_count));

    execute immediate 'analyze table dt_komap_phenotype compute statistics';

    -------------------------------------------------------------------------
    -- Create a gold standard.
    -------------------------------------------------------------------------

    -- OPTION 1: Randomly select patients with the PheCode and perform manual chart review.
    -- Make sure you have at least 15 patients in the base cohort.
    -- This is the most accurate way to create a gold standard.


    -- OPTION 2: Simulate based on the results of the GMM.
    -- This is just an estimate if you cannot perform chart review.
    step_start_time := localtimestamp;
    insert into dt_komap_phenotype_gold_standard (phenotype, patient_num, has_phenotype)
    select s.phenotype, s.patient_num,
        (case when g2/(g1+g2) >= dbms_random.value() then 1 else 0 end) has_phenotype
    from (
        select phenotype, patient_num, score, row_number() over (partition by phenotype order by dbms_random.value()) k
        from dt_komap_phenotype_sample_results
    ) s
         inner join dt_komap_phenotype p
            on s.phenotype=p.phenotype
         cross apply (
            select exp(-0.5*(score-p.gmm_mean1)*(score-p.gmm_mean1)/p.gmm_stdev1/p.gmm_stdev1)/p.gmm_stdev1/sqrt(2*acos(-1)) g1,
                exp(-0.5*(score-p.gmm_mean2)*(score-p.gmm_mean2)/p.gmm_stdev2/p.gmm_stdev2)/p.gmm_stdev2/sqrt(2*acos(-1)) g2 from dual
        ) g
    where s.k<1000;

    row_count := sql%Rowcount;
    time_ms := extract (day from (localtimestamp - step_start_time))*24*60*60 +
        extract (hour from (localtimestamp - step_start_time))*60*60+
        extract (minute from (localtimestamp - step_start_time))*60+
        round(extract(second from (localtimestamp - step_start_time))*1000);
    dbms_output.put_line('  insert into dt_komap_phenotype_gold_standard, step time (ms): ' || to_char(time_ms) || ', rows: ' || to_char(row_count));


    -------------------------------------------------------------------------
    -- Calculate the phenotype score of each gold standard patient.
    -------------------------------------------------------------------------

    step_start_time := localtimestamp;
    row_count := 0;
    update dt_komap_phenotype_gold_standard g
    set g.score = (
        select sum(f.log_dates*c.coef)
        from dt_komap_phenotype_feature_coef c
             inner join dt_komap_patient_feature f
                on f.patient_num=g.patient_num and f.feature_cd=c.feature_cd
        where c.phenotype=g.phenotype
            and g.patient_num in (select patient_num from dt_komap_base_cohort)
    );

    row_count := sql%Rowcount;
    time_ms := extract (day from (localtimestamp - step_start_time))*24*60*60 +
        extract (hour from (localtimestamp - step_start_time))*60*60+
        extract (minute from (localtimestamp - step_start_time))*60+
        round(extract(second from (localtimestamp - step_start_time))*1000);
    dbms_output.put_line('  update dt_komap_phenotype_gold_standard, step time (ms): ' || to_char(time_ms) || ', rows: ' || to_char(row_count));

    execute immediate 'analyze table dt_komap_phenotype_gold_standard compute statistics';

    -------------------------------------------------------------------------
    -- Calculate the PPV (precision) and recall of each phenotype.
    -------------------------------------------------------------------------

    step_start_time := localtimestamp;
    row_count := 0;
    update dt_komap_phenotype p
    set p.ppv = (
        select avg(cast(has_phenotype as float))
        from dt_komap_phenotype_gold_standard g
        where g.phenotype=p.phenotype and g.score>=p.threshold
    );
    row_count := row_count + sql%rowcount;

    update dt_komap_phenotype p
    set p.recall = (
        select avg(cast(pred_phenotype as float))
        from dt_komap_phenotype_gold_standard g
             cross apply (select (case when g.score>=p.threshold then 1 else 0 end) pred_phenotype from dual) x
        where g.phenotype=p.phenotype and g.score is not null and g.has_phenotype=1
    );
    row_count := row_count + sql%rowcount;

    -------------------------------------------------------------------------
    -- Calculate additional phenotype evaluation metrics.
    -------------------------------------------------------------------------

    -- Number of patients assigned the phenotype / Number of patients in the base cohort with the phenotype's feature
    update dt_komap_phenotype p
    set p.recall_base_cohort = (
        select avg(cast(pred_phenotype as float))
        from dt_komap_phenotype_gold_standard g
             cross apply (select (case when g.score>=p.threshold then 1 else 0 end) pred_phenotype from dual) x
        where g.phenotype=p.phenotype and g.score is not null
    );
    row_count := row_count + sql%rowcount;

    -- Number of patients in the base cohort with the phenotype's feature / Number of all patients with the phenotype's feature
    update dt_komap_phenotype p
    set p.frac_feature_in_base_cohort = (
        select avg(cast((case when b.patient_num is not null then 1 else 0 end) as float))
        from dt_komap_patient_feature f
             left outer join dt_komap_base_cohort b
                on f.patient_num=b.patient_num
        where f.feature_cd=p.phenotype
    );
    row_count := row_count + sql%rowcount;

    -- Number of patients assigned the phenotype / Number of all patients with the phenotype's feature
    update dt_komap_phenotype p
    set p.recall_has_feature = recall_base_cohort * frac_feature_in_base_cohort;
    row_count := row_count + sql%rowcount;

    -------------------------------------------------------------------------
    -- Generate derived phenotype facts when the PPV >= 0.9.
    -------------------------------------------------------------------------

    -- Select all phenotypes where a threshold was computed
    update dt_komap_phenotype
    set generate_facts = (case when threshold is not null then 1 else 0 end);
    row_count := row_count + sql%rowcount;

    -- Alternatively, use custom logic to select only the best phenotypes
    --update dt_komap_phenotype
    --	set generate_facts = (case when ppv>=0.9 then 1 else 0 end);
    --row_count := row_count + sql%rowcount;

    time_ms := extract (day from (localtimestamp - step_start_time))*24*60*60 +
        extract (hour from (localtimestamp - step_start_time))*60*60+
        extract (minute from (localtimestamp - step_start_time))*60+
        round(extract(second from (localtimestamp - step_start_time))*1000);
    dbms_output.put_line('  update dt_komap_phenotype, step time (ms): ' || to_char(time_ms) || ', rows: ' || to_char(row_count));

    execute immediate 'analyze table dt_komap_phenotype compute statistics';


    row_count := sql%Rowcount;
    time_ms := extract (day from (localtimestamp - proc_start_time))*24*60*60 +
        extract (hour from (localtimestamp - proc_start_time))*60*60+
        extract (minute from (localtimestamp - proc_start_time))*60+
        round(extract(second from (localtimestamp - proc_start_time))*1000);
    dbms_output.put_line('  usp_dt_komap_process_results, total time (ms): ' || to_char(time_ms));

END;


