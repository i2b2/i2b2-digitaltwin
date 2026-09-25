# i2b2 Digital Twin

The scripts to modify an i2b2 database with stored procedures to compute derived facts to support the digital twin in i2b2. Click here for the documentation: [The Digital Twin Package documentation](https://community.i2b2.org/wiki/display/BUN/Digital+Twin+Technologies)


## Development / Maintenance
The i2b2 digital twin scripts are maintained by the i2b2 team.

## Documentation
The documentation for installing the digital twin computed phenotypes is at: https://docs.google.com/document/d/1Th98QZimCQ4w-cj_15lDc6zYUiwypLs7sQ0dioBsY-M/edit#heading=h.hn0g2vivalv9 

### SQL Server ACT-OMOP loyalty cohort

For ACT-OMOP on SQL Server, build the standard ACT-OMOP compatibility views before installing the Digital Twin procedures. The source objects may also be SQL Server synonyms pointing to views in another schema or database. The numerically prefixed `00_dt_loyaltycohort_prep_omop.sql` script then creates the limited `OBSERVATION_FACT` compatibility view required by `USP_DT_LOYALTYCOHORT`. It will not replace a real i2b2 `OBSERVATION_FACT` table.

The supported installation order is:

1. Build the ACT-OMOP SQL Server views.
2. Create the Digital Twin tables and cohort-filter type.
3. Load the loyalty reference data.
4. Install the SQL Server procedures; the numeric prefix runs the OMOP prep before the loyalty procedure.
5. Run `scripts/validation/sqlserver/validate_dt_loyaltycohort_omop.sql`, then test a small cohort before a production run.

The shared ACT-OMOP `PATIENT_DIMENSION` view is not modified. `TABLE_ACCESS`, `CONCEPT_DIMENSION`, and the OMOP `CONCEPT` vocabulary may be local tables, views, or synonyms. The loyalty procedure normalizes OMOP gender concept IDs itself. ACT-OMOP currently supplies a null `DEATH_DATE`, so loyalty `DEATH_DT` remains null until death mapping is implemented separately.

#### How one procedure supports both i2b2 and ACT-OMOP

The core loyalty feature and scoring logic is shared between the two database
models. A small compatibility layer adapts their different fact and metadata
representations:

- A conventional i2b2 installation continues to use its physical
  `OBSERVATION_FACT` table. On ACT-OMOP, the prep script creates a minimal
  three-column compatibility view over the standard and nonstandard condition,
  drug, device, measurement, observation, and procedure views. A real i2b2 fact
  table is never replaced.
- At runtime, the procedure creates a private unified concept map. It reads a
  conventional `CONCEPT_DIMENSION`, the split ACT-OMOP ontology tables
  registered in `TABLE_ACCESS`, or both. Merging both sources is important for
  hybrid installations whose unified concept dimension omits ACT visit codes.
- Tables, views, synonyms, and qualified ontology object names are supported,
  allowing compatibility objects to point to another schema or database.
- Patient sex values are normalized across conventional i2b2 codes and OMOP
  concept IDs (`8532` for female and `8507` for male). Visit codes are converted
  to a common string form and trimmed before comparison.
- Conventional i2b2 Charlson mappings match vocabulary-prefixed ICD codes
  directly. ACT-OMOP mappings match the ICD pattern stored in
  `I2B2_ACT_BASECODE`, then translate it to both `OMOP_S_CONCEPT_ID` and
  `OMOP_NS_CONCEPT_ID` so standard and source condition facts are recognized.

After these adaptations, both installations use the same patient-inclusion,
feature calculation, loyalty scoring, Charlson calculation, and result-writing
logic. The shared i2b2-OMOP views themselves are not modified.

The `scripts/visualization` directory contains privacy-conscious aggregate SQL
extracts and a standalone Loyalty × Health Burden Atlas for exploring
`DT_LOYALTY_RESULT` together with `DT_LOYALTY_RESULT_CHARLSON`.

See the [SQL Server loyalty cohort README](LOYALTY_README.md)
for the procedure inputs, patient-inclusion rules, feature definitions, scoring,
Charlson calculation, outputs, and troubleshooting guidance.


## Reporting Issues
If an issue is found with the i2b2 digital twin scripts please submit an issue in the [i2b2 Bug Tracker](http://community.i2b2.org/jira/secure/Dashboard.jspa "i2b2 Bug Tracker") under the *i2b2 Core Software* project.
    
Suggestions for improvements or enhancements to the i2b2 database scripts can also be submitted into the i2b2 Bug Tracker.
