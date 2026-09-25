# SQL Server loyalty cohort

`USP_DT_LOYALTYCOHORT` identifies patients whose longitudinal i2b2 record is
likely to be sufficiently complete for follow-up analyses. It calculates 20
binary indicators over a patient-specific lookback period, combines them into a
published loyalty score, identifies the highest-scoring fifth of each cohort,
and calculates a Charlson comorbidity profile.

The method is described in:

> Klann JG, Henderson DW, Morris M, et al. A broadly applicable approach to
> enrich electronic-health-record cohorts by identifying patients with complete
> data: a multisite evaluation. *JAMIA*. 2023. doi:10.1093/jamia/ocad166

This document describes the SQL Server implementation. The procedure supports
conventional i2b2 and the ACT-OMOP compatibility setup documented below.

## What the procedure does

For every `(PATIENT_NUM, COHORT_NAME, INDEX_DT)` supplied by the caller, the
procedure:

1. Resolves the configured ontology paths to fact and visit codes.
2. Applies the initial patient-inclusion rules.
3. Calculates age and sex from `PATIENT_DIMENSION`.
4. Calculates 20 loyalty feature flags during the lookback period.
5. Applies the coefficients in `DT_LOYALTY_PSCOEFF` to produce a loyalty score.
6. Finds the top score quintile within the cohort and age stratum.
7. Calculates diagnosis-based Charlson flags and an age-adjusted Charlson index.
8. Replaces the matching slice in the three persistent result tables.
9. Optionally returns the shareable summary rows to the caller.

The procedure does not create the input cohort. It evaluates a cohort supplied
through the `UDT_DT_LOYALTY_COHORTFILTER` table type.

## Required objects

The Digital Twin installation creates or loads:

- `dbo.UDT_DT_LOYALTY_COHORTFILTER`
- `dbo.DT_LOYALTY_PATHS`
- `dbo.DT_LOYALTY_PSCOEFF`
- `dbo.DT_LOYALTY_CHARLSON`
- `dbo.DT_LOYALTY_RESULT`
- `dbo.DT_LOYALTY_RESULT_SUMMARY`
- `dbo.DT_LOYALTY_RESULT_CHARLSON`
- `dbo.USP_DT_LOYALTYCOHORT`

The procedure reads these i2b2-compatible objects:

- `dbo.OBSERVATION_FACT`
- `dbo.PATIENT_DIMENSION`
- `dbo.VISIT_DIMENSION`
- `dbo.CONCEPT_DIMENSION`, `dbo.TABLE_ACCESS`, or both

Tables registered through `TABLE_ACCESS` may be local tables, views, synonyms,
or qualified objects in another schema or database.

## Parameters

| Parameter | Default | Meaning |
| --- | ---: | --- |
| `@SITE varchar(10)` | Required | Site label written to the results. It does not filter source facts. |
| `@LOOKBACK_YEARS int` | `1` | Number of years before each patient's index date included in the measurement period. |
| `@DEMOGRAPHIC_FACTS bit` | `0` | Set to `1` when demographic facts are stored in `OBSERVATION_FACT` and must not independently qualify a patient for inclusion. |
| `@GENDERED bit` | `0` | When `1`, summary percentages for mammography and Pap testing use female patients as their denominator and PSA testing uses male patients. It also labels the result slice; it does not change the patient-level feature flags or coefficients. |
| `@COHORT_FILTER UDT_DT_LOYALTY_COHORTFILTER READONLY` | Required | Patient, cohort name, and index date records to evaluate. |
| `@OUTPUT bit` | `1` | When `1`, returns the final shareable summary result set. Persistent result tables are populated either way. |

`@SITE` is descriptive. Source-table filtering is determined by the patient
numbers and dates in `@COHORT_FILTER`, not by a site column in the i2b2 tables.

## Measurement period

All general loyalty features use the following patient-specific interval:

```sql
START_DATE >= DATEADD(year, -@LOOKBACK_YEARS, INDEX_DT)
AND START_DATE < DATEADD(day, 1, INDEX_DT)
```

The interval begins exactly `@LOOKBACK_YEARS` before `INDEX_DT` and includes the
entire index date. Using an exclusive upper bound avoids losing records whose
timestamps occur later on the index date.

Charlson uses a different interval, described under **Charlson calculation**.

## Patient inclusion and exclusion

Patient selection happens in two stages.

### Initial `#INCLPAT` population

A patient must:

1. Appear in `@COHORT_FILTER`.
2. Have at least one `OBSERVATION_FACT` record during the measurement period.

When `@DEMOGRAPHIC_FACTS = 0`, any observation fact qualifies. When
`@DEMOGRAPHIC_FACTS = 1`, the qualifying set excludes concepts found under
`\ACT\Demographics%`; a patient with demographic facts only is not included.

The ACT-OMOP `OBSERVATION_FACT` compatibility view supplied with this package
does not include demographic domains, so `@DEMOGRAPHIC_FACTS = 0` is normally
appropriate for that setup.

### Final cohort requirements

An initially included patient must also have:

- At least one `VISIT_DIMENSION` record during the measurement period. This is
  enforced by the inner join used to calculate `LAST_VISIT`.
- A matching `PATIENT_DIMENSION` record.
- A usable birth date, so that age can be calculated.
- An age greater than 18 on `INDEX_DT`.

The visit that anchors inclusion does not need to match an inpatient,
outpatient, or emergency-department feature code. Those mappings control the
three visit feature flags; any visit can establish `LAST_VISIT` and final
inclusion.

The following historical filters are present as comments but are not active:

- The multi-visit or “non-ephemeral patient” filter is disabled. A patient does
  not need two or more encounters to enter the cohort.
- Patients with a non-null death date are no longer excluded.

In plain language, the active rule is: start with the supplied cohort, require
at least one fact and one visit in the lookback period, require usable patient
demographics, and exclude patients aged 18 or younger.

## Loyalty features

The procedure produces the following 20 binary features:

| Group | Features | Rule |
| --- | --- | --- |
| Diagnosis activity | `NUM_DX1`, `NUM_DX2` | Exactly one distinct diagnosis date for `NUM_DX1`; at least two for `NUM_DX2`. |
| Medication activity | `MED_USE1`, `MED_USE2` | Exactly one distinct medication date for `MED_USE1`; at least two for `MED_USE2`. |
| Preventive care | `MAMMOGRAPHY`, `PAP_TEST`, `PSA_TEST`, `COLONOSCOPY`, `FECAL_OCCULT_TEST`, `FLU_SHOT`, `PNEUMOCOCCAL_VACCINE` | At least one mapped fact. |
| Monitoring and examination | `BMI`, `A1C`, `MEDICAL_EXAM` | At least one mapped fact. |
| Visit activity | `INP1_OPT1_VISIT`, `OPT2_VISIT`, `ED_VISIT` | At least one mapped inpatient/outpatient visit; at least two mapped outpatient visits; or at least one mapped ED visit, respectively. |
| Physician visits | `MDVISIT_PNAME2`, `MDVISIT_PNAME3` | Exactly two distinct physician-visit dates; or at least three distinct dates, respectively. |
| Composite | `ROUTINE_CARE_2` | At least two of the configured routine-care facts are present. |

`ROUTINE_CARE_2` considers medical examination, mammography, PSA testing,
colonoscopy, fecal occult blood testing, influenza vaccination, pneumococcal
vaccination, A1C, and BMI. Pap testing is a standalone feature but is not part
of this composite in the current SQL implementation.

Diagnosis, medication, and physician-visit thresholds count distinct calendar
dates. Other fact-based features test raw fact presence. Visit features are
calculated from `VISIT_DIMENSION` rather than `OBSERVATION_FACT`.

## Ontology mapping

`DT_LOYALTY_PATHS` associates each feature with an ontology path. At runtime,
the procedure expands the configured path to all matching child concepts.

On conventional i2b2 installations, concepts are read from
`CONCEPT_DIMENSION`. ACT-OMOP commonly distributes concepts across the ontology
tables registered in `TABLE_ACCESS`; the procedure merges both sources when
both exist. This is important for hybrid installations in which a unified
`CONCEPT_DIMENSION` omits visit concepts.

Local codes can be added to `DT_LOYALTY_PATHS` using `CODE_TYPE = 'SITE'` and
`SITE_SPECIFIC_CODE`. Review local additions carefully because they directly
change feature classification.

## Loyalty score and cutoff

Each true feature contributes its coefficient from `DT_LOYALTY_PSCOEFF`. The
score begins with an intercept of `-0.010`:

```text
PREDICTED_SCORE = -0.010 + sum(feature flag × feature coefficient)
```

Despite its historical column name, `PREDICTED_SCORE` should be described as a
loyalty score unless it has been calibrated as a probability for the population
being studied.

The procedure divides patients into five groups ordered from highest to lowest
score. It calculates a cutoff separately for each:

- Cohort
- Age stratum (`UNDER 65`, `OVER 65`, and the combined `ALL PATIENTS` summary)

The minimum score in the highest-scoring quintile is stored as
`PREDICTIVE_SCORE_CUTOFF`. Summary rows with `CUTOFF_FILTER_YN = 'Y'` describe
patients at or above this cutoff. Rows with `CUTOFF_FILTER_YN = 'N'` describe
the full eligible cohort.

With small cohorts or tied scores, the retained proportion may not be exactly
20 percent.

## Charlson calculation

Charlson is calculated after the loyalty cohort is assembled.

For each patient, diagnosis facts are examined from one year before
`LAST_VISIT` through the end of `LAST_VISIT`:

```sql
START_DATE >= DATEADD(year, -1, LAST_VISIT)
AND START_DATE < DATEADD(day, 1, LAST_VISIT)
```

This is deliberately different from the general loyalty measurement period,
which is anchored on `INDEX_DT` and uses `@LOOKBACK_YEARS`.

`DT_LOYALTY_CHARLSON` contains ICD-9-CM and ICD-10-CM patterns and weights. On
ACT-OMOP, the procedure matches those patterns to `I2B2_ACT_BASECODE`, then
maps the result to both `OMOP_S_CONCEPT_ID` and `OMOP_NS_CONCEPT_ID` so that
standard and source condition facts are recognized.

The diagnosis weights are combined with age points:

| Age | Points |
| --- | ---: |
| Under 50 | 0 |
| 50–59 | 1 |
| 60–69 | 2 |
| 70 or older | 3 |

More severe liver disease supersedes mild liver disease, and diabetes with
complications supersedes diabetes without complications in the final index.

Consequently, `CHARLSON_INDEX` can be nonzero even when every diagnosis feature
is zero: the nonzero value may consist entirely of age points. Runtime messages
report the number of ontology tables found, mapped fact concept IDs, mapped
categories, and patients with one or more diagnosis feature flags.

## Output tables

### `DT_LOYALTY_RESULT`

One patient-level row per result slice, containing demographics, index date,
the 20 feature flags, and `PREDICTED_SCORE`.

### `DT_LOYALTY_RESULT_CHARLSON`

One patient-level row containing `LAST_VISIT`, the age-adjusted Charlson index,
estimated 10-year probability, and the 17 weighted Charlson category flags.

### `DT_LOYALTY_RESULT_SUMMARY`

Aggregated age-stratified results for the complete cohort and the
highest-scoring group. It includes patient counts, feature percentages,
Charlson statistics, the score cutoff, and runtime information. The procedure
clears `TOTAL_SUBJECTS` from the `PERCENT SUBJECTS` rows after calculating the
population percentages to reduce accidental disclosure.

Before inserting results, the procedure deletes existing rows with the same:

- Site
- Cohort name
- Lookback length
- Gender-denominator setting

Rerunning the same slice therefore replaces it rather than appending another
copy. Other result slices are preserved.

These tables contain patient-level data unless explicitly aggregated. Apply
institutional access and disclosure controls before exporting them.

## Example execution

```sql
DECLARE @COHORT dbo.UDT_DT_LOYALTY_COHORTFILTER;

INSERT INTO @COHORT (PATIENT_NUM, COHORT_NAME, INDEX_DT)
SELECT PATIENT_NUM, 'Example cohort', CONVERT(date, '2011-01-01')
FROM dbo.MY_COHORT;

EXEC dbo.USP_DT_LOYALTYCOHORT
  @SITE = 'SITE1',
  @LOOKBACK_YEARS = 5,
  @DEMOGRAPHIC_FACTS = 0,
  @GENDERED = 0,
  @COHORT_FILTER = @COHORT,
  @OUTPUT = 1;
```

Every cohort-filter record requires its own `INDEX_DT`. Confirm that the source
data extend far enough before that date to support the requested lookback.

## ACT-OMOP installation

For SQL Server ACT-OMOP:

1. Build or link the standard ACT-OMOP compatibility views.
2. Create the Digital Twin tables and table type.
3. Load the loyalty paths, coefficients, and Charlson reference mappings.
4. Run `00_dt_loyaltycohort_prep_omop.sql`.
5. Install `usp_dt_loyaltycohort.sql`.
6. Run `../../validation/sqlserver/validate_dt_loyaltycohort_omop.sql`.
7. Test a small cohort before a production run.

The prep script creates a limited three-column `OBSERVATION_FACT` compatibility
view over the ACT-OMOP domain views. It does not overwrite a real
`OBSERVATION_FACT` table and accepts required source objects exposed as views or
synonyms.

## Runtime checkpoints and troubleshooting

Important informational messages include:

- `Finish #INCLPAT`: patients having a qualifying observation fact.
- `Cohort and Visit Type variables`: patients surviving the visit and patient
  dimension joins.
- `Visit flag checkpoint`: patients receiving each visit feature flag.
- `Charlson metadata discovery`: diagnosis ontology tables found.
- `Charlson diagnosis map`: reference patterns, mapped concept IDs, and mapped
  categories.
- `Charlson diagnosis matches`: patients with at least one diagnosis-derived
  Charlson flag.

Common interpretations:

| Observation | Likely explanation |
| --- | --- |
| `#INCLPAT` is zero | No facts fall inside the patient-specific lookback window, or the supplied index dates are outside the data. |
| `#INCLPAT` is nonzero but the cohort is zero | No visits fall inside the same window, patient dimension rows are missing, or all remaining patients have unusable birth dates or are pediatric. |
| All three visit flags are zero | Visit ontology codes do not match `VISIT_DIMENSION.INOUT_CD`, even though general visits may exist. |
| Charlson fact concept IDs are zero | The ICD ontology tables or their OMOP mapping columns are unavailable, or reference patterns do not match the installed ontology. |
| Charlson concepts map but patient flags are zero | No mapped diagnosis facts occur during the year before `LAST_VISIT`, or condition fact codes do not match the ontology IDs. |
| Charlson index is nonzero but all diagnosis flags are zero | The index contains age points only. |

Use `../../validation/sqlserver/validate_dt_loyaltycohort_omop.sql` to inspect
prerequisites, fact dates, path coverage, and visit-code matches.

## Known limitations

- The current ACT-OMOP `PATIENT_DIMENSION` compatibility view exposes a null
  `DEATH_DATE`; consequently `DEATH_DT` remains null in OMOP results. Death
  mapping is intentionally left for a future change.
- The average fact-count calculation is disabled because it is expensive on
  large databases.
- Charlson adds a potentially expensive pass over condition facts.
- The model was developed for adult populations; patients aged 18 or younger
  are explicitly excluded.
- Ontology versions and local coding practices can change feature coverage.
  Validate mappings whenever installing a new ontology release.

## Visualization

`../../visualization` contains two aggregate SQL exports and a standalone
browser visualization that combines `DT_LOYALTY_RESULT` with
`DT_LOYALTY_RESULT_CHARLSON`. The exports omit patient identifiers and suppress
small groups using a configurable disclosure threshold.
