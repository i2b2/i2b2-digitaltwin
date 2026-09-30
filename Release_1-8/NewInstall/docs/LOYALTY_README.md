# Loyalty usage

Install and run `USP_DT_LOYALTYCOHORT` on Oracle or SQL Server with conventional
i2b2 or ACT-OMOP. The procedure evaluates a supplied patient cohort and writes
loyalty scores, Charlson profiles, and aggregate summaries.

For eligibility rules, feature definitions, scoring, and implementation
differences, see [architecture and process](LOYALTY_ARCHITECTURE_README.md).

## Choose your setup

| Database and model | Source prerequisites | Cohort input | Preparation |
| --- | --- | --- | --- |
| SQL Server, i2b2 | Conventional fact, patient, visit, and ontology objects | Table-valued parameter | Existing physical fact table is preserved |
| SQL Server, ACT-OMOP | Standard ACT-OMOP compatibility views and ontology registration | Table-valued parameter | Run SQL Server OMOP prep before the procedure |
| Oracle, i2b2 | Conventional fact, patient, visit, and ontology objects | Persistent cohort-filter table | Existing queryable fact object is preserved |
| Oracle, ACT-OMOP | Standard ACT-OMOP compatibility views and ontology registration | Persistent cohort-filter table | Run Oracle OMOP prep before the procedure |

ACT-OMOP here means the ACT compatibility layer over OMOP, not a bare OMOP CDM.
The scripts expect `PATIENT_DIMENSION`, `VISIT_DIMENSION`, ontology metadata
through `CONCEPT_DIMENSION` and/or `TABLE_ACCESS`, and a fact interface.
The prep scripts require standard and nonstandard condition, drug, device,
measurement, observation, and procedure views when creating that interface.

## Installation

Use the platform-specific files in the
[script inventory](LOYALTY_ARCHITECTURE_README.md#script-responsibilities).

1. Establish the conventional i2b2 objects or install/link the standard ACT-OMOP
   compatibility views and ontology objects. Confirm the procedure owner can
   read them. Oracle requires direct grants or local synonyms backed by suitable
   privileges; role-only privileges are insufficient for stored procedure SQL.
2. For a new installation, run the matching Digital Twin schema script to
   create its tables and, on SQL Server, the cohort-filter table type. On an
   existing installation, review schema changes instead of blindly rerunning
   `CREATE` statements against populated objects.
3. [Load reference data](#reference-data) using the matching inserts or CSVs.
4. For ACT-OMOP, run the matching `00_dt_loyaltycohort_prep_omop.sql`.
5. Install the matching `usp_dt_loyaltycohort.sql`. The procedure installer uses
   lexical ordering, so the `00_` prep runs first when installing the directory.
6. Run the appropriate [validation checks](#validation-and-troubleshooting),
   then execute a small cohort and inspect the results before a full run.

SQL Server prep preserves a physical `OBSERVATION_FACT` table but rebuilds an
existing view after validating the source views; other existing object types
are rejected. Oracle prep skips creation whenever `OBSERVATION_FACT` is already
queryable, including through a synonym. Review an existing custom view before
running prep. Neither prep script replaces a physical i2b2 fact table.

SQL Server supports qualified ontology objects and synonyms, including
cross-database references. Oracle supports local/schema-qualified objects and
synonyms; database-link ontology names are not supported.

## Reference data

Load `DT_LOYALTY_PATHS`, `DT_LOYALTY_PSCOEFF`, and `DT_LOYALTY_CHARLSON` from the
[SQL Server inserts](../Crcdata/act/scripts/sqlserver/insert_loyalty_ref_sqlserver.sql)
or [Oracle inserts](../Crcdata/act/scripts/oracle/insert_loyalty_ref_oracle.sql).
These references are used with both i2b2 and ACT-OMOP.

For CSV loading, use the [reference file manifest](LOYALTY_REFERENCE_CSV_README.md).
Paths and coefficients are shared. Choose `dt_loyalty_charlson_sqlserver.csv`
for SQL Server or `dt_loyalty_charlson.csv` for Oracle; do not load both.

1. Create the target tables using the applicable database schema script before
   importing. The CSVs contain data only.
2. Use UTF-8 encoding, a comma delimiter, and a double-quote text qualifier.
   The first row contains column names; map by these names and skip it as data.
3. Import empty fields as SQL `NULL`. Preserve backslashes literally; they are
   part of the ontology paths, not escape characters.
4. Import `CHARLSON_WT` and `COEFF` as numbers, using a period as the decimal
   separator. All other columns are text. Preserve codes, punctuation, spaces,
   and trailing zeros within codes exactly.
5. Use these files as an alternative to the corresponding inserts. If inserts
   already ran or partially succeeded, reconcile existing rows before importing
   to avoid duplicate data or key conflicts. Commit the import as required by
   your database client and check the loaded row counts.

The Oracle reference now contains 496 prefix patterns instead of the former
4,435 enumerated codes. Replace the old reference set when upgrading, preserving
intentional local customizations; do not append the new set. Revalidate mapping
coverage because prefixes may include codes absent from the old enumeration.

Sites may need additional local ontology paths or visit codes. Follow the
[mapping rules](LOYALTY_ARCHITECTURE_README.md#ontology-mapping), and validate
local coverage after changing the ontology or reference data.

## Parameters

### SQL Server parameters

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

### Oracle parameters

| Parameter | Default | Meaning |
| --- | --- | --- |
| `P_SITE VARCHAR` | Required | Descriptive site label; keep within the result tables' 10-character limit. Does not filter source facts. |
| `P_LOOKBACK_YEARS INT` | `1` | Years before each input index date. |
| `P_DEMOGRAPHIC_FACTS NUMBER` | `0` | Use `1` to exclude demographic-only facts from initial inclusion. |
| `P_GENDERED NUMBER` | `0` | Use `1` for sex-specific denominators in the relevant preventive-care summaries. |
| `P_OUTPUT NUMBER` | `1` | Use `1` for an implicit summary result set, or `0` to query persistent results yourself. |

Oracle has no cohort-filter argument: it reads all rows of
`DT_LOYALTY_COHORTFILTER`. Use `0`/`1` for the numeric switches. With the supplied
ACT-OMOP fact view, the demographic-facts switch normally remains `0` on either
platform because that view does not include demographic domains.

## Prepare the cohort

Supply `PATIENT_NUM`, `COHORT_NAME`, and `INDEX_DT` for each intended input row.
Use patient identifiers from the installed patient/fact interfaces, date-only
index values, and enough preceding data for the chosen lookback. Avoid duplicate
input rows and use separate cohort names/runs for distinct analyses. The site
label is descriptive; it does not select a site from the source database.

The same platform-specific call works with i2b2 and ACT-OMOP after installation.
Replace `MY_COHORT` with your cohort table or query and adjust the example dates.

## Example execution

### SQL Server

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

### Oracle

Run this example in the schema containing the installed Digital Twin tables and
procedure. Replace `MY_COHORT` with your patient cohort table or query, and adjust
the site label, index date, and lookback period for your data.

Oracle reads every row in the persistent `DT_LOYALTY_COHORTFILTER` table; there
is no cohort-filter parameter. The example clears that input table before loading
the intended run. Confirm that its existing contents are no longer needed first.
The input and working tables are shared, so do not prepare or execute concurrent
loyalty runs in the same schema.

```sql
-- SQL*Plus / SQLcl, or SQL Developer's Run Script mode.
SET SERVEROUTPUT ON;

DELETE FROM DT_LOYALTY_COHORTFILTER;

INSERT INTO DT_LOYALTY_COHORTFILTER (PATIENT_NUM, COHORT_NAME, INDEX_DT)
SELECT DISTINCT PATIENT_NUM, 'Example cohort', DATE '2011-01-01'
FROM MY_COHORT;

COMMIT;

BEGIN
  USP_DT_LOYALTYCOHORT(
    P_SITE              => 'SITE1',
    P_LOOKBACK_YEARS     => 5,
    P_DEMOGRAPHIC_FACTS  => 0,
    P_GENDERED          => 0,
    P_OUTPUT            => 0
  );
END;
/

COMMIT;

SELECT *
FROM DT_LOYALTY_RESULT_SUMMARY
WHERE SITE = 'SITE1'
  AND COHORT_NAME = 'Example cohort'
  AND LOOKBACK_YR = 5
  AND GENDER_DENOMINATORS_YN = 'N';
```

Each input row needs an `INDEX_DT` with enough preceding data for the lookback.
`P_OUTPUT => 0` suppresses the implicit result set; the example queries the stored
summary directly. Set `P_OUTPUT => 1` to return the summary through a client that
supports Oracle implicit result sets. Persistent results are populated either
way. The procedure performs DDL with implicit commits, so the run cannot be
treated as a single rollbackable transaction.

## Results and reruns

| Table | Use |
| --- | --- |
| `DT_LOYALTY_RESULT` | Patient features and loyalty scores |
| `DT_LOYALTY_RESULT_CHARLSON` | Patient Charlson indices and weighted category flags |
| `DT_LOYALTY_RESULT_SUMMARY` | Cohort summaries with and without the loyalty cutoff |

To inspect a stored SQL Server summary:

```sql
SELECT *
FROM dbo.DT_LOYALTY_RESULT_SUMMARY
WHERE SITE = 'SITE1'
  AND COHORT_NAME = 'Example cohort'
  AND LOOKBACK_YR = 5
  AND GENDER_DENOMINATORS_YN = 'N';
```

The Oracle example includes the equivalent query. Patient-level tables use
`LOOKBACK_YEARS` rather than the summary's `LOOKBACK_YR`. Summary
`CUTOFF_FILTER_YN = 'Y'` selects the high-loyalty subset, and `'N'` selects the
full eligible cohort. See [output definitions](LOYALTY_ARCHITECTURE_README.md#output-tables)
for details, including age strata.

Rerunning a site/cohort/lookback/gender-denominator slice replaces that slice;
the index date is not an additional replacement key. Coordinate runs that
target the same slice. Oracle requires serial runs in a schema even for
different cohorts because its input and working tables are shared. Its DDL
also causes implicit commits. Inspect partial results before retrying a failed
run; do not assume rollback restores the previous state.

Patient result tables contain patient-level data. Apply institutional access
and disclosure controls before exporting them or aggregate summaries.

## Validation and troubleshooting

For ACT-OMOP, run the
[SQL Server validation script](../Crcdata/scripts/validation/sqlserver/validate_dt_loyaltycohort_omop.sql)
or [Oracle validation script](../Crcdata/scripts/validation/oracle/validate_dt_loyaltycohort_omop.sql).
These scripts inspect prerequisites, fact dates, ontology coverage, and visit
and Charlson mappings. They are tailored to ACT-OMOP; for conventional i2b2,
verify its source objects and mappings and inspect a small procedure run rather
than treating missing OMOP-specific columns as installation failures.

Important informational messages include:

- Initial inclusion (`#INCLPAT` on SQL Server, `DT_TMP_INCLPAT` on Oracle): patients having a qualifying observation fact.
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
| Initial inclusion is zero | No facts fall inside the patient-specific lookback window, or the supplied index dates are outside the data. |
| Initial inclusion is nonzero but the cohort is zero | No visits fall inside the same window, patient dimension rows are missing, or all remaining patients have unusable birth dates or are pediatric. |
| All three visit flags are zero | Visit ontology codes do not match `VISIT_DIMENSION.INOUT_CD`, even though general visits may exist. |
| Charlson fact concept IDs are zero | The ICD ontology tables or their OMOP mapping columns are unavailable, or reference patterns do not match the installed ontology. |
| Charlson concepts map but patient flags are zero | No mapped diagnosis facts occur during the year before `LAST_VISIT`, or condition fact codes do not match the ontology IDs. |
| Charlson index is nonzero but all diagnosis flags are zero | The index contains age points only. |

Oracle progress messages require server output to be enabled. The exact
checkpoint wording differs between platforms. Examples here were checked
against the repository's procedure signatures and schema; they have not been
executed against a live Oracle or SQL Server database as part of this doc update.

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

- Oracle and SQL Server currently differ in distinct-date counting and date
  arithmetic at some boundaries. Review the
  [measurement and feature details](LOYALTY_ARCHITECTURE_README.md#measurement-period)
  before interpreting cross-platform differences.

## Visualization and further reading

The [visualization guide](../Crcdata/scripts/visualization/README.md) describes
the aggregate exports and browser-based Loyalty × Health Burden Atlas. The
supplied extract queries are SQL Server-specific; Oracle equivalents are not
provided. Follow that guide for suppression thresholds and export instructions.

- [Architecture and process](LOYALTY_ARCHITECTURE_README.md)
- [Reference CSV manifest](LOYALTY_REFERENCE_CSV_README.md)
- [Historical ACT-OMOP changelog](CHANGELOG_OMOP.md)
- [Digital Twin package documentation](https://community.i2b2.org/wiki/display/BUN/Digital+Twin+Technologies)
- [Computed-phenotype installation documentation](https://docs.google.com/document/d/1Th98QZimCQ4w-cj_15lDc6zYUiwypLs7sQ0dioBsY-M/edit#heading=h.hn0g2vivalv9)

The scripts are maintained by the i2b2 team. Report issues and suggestions in
the [i2b2 Core Software project](http://community.i2b2.org/jira/secure/Dashboard.jspa).
