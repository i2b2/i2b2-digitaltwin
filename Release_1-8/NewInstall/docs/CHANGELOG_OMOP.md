# Changelog: SQL Server ACT-OMOP loyalty cohort support

This changelog records the changes made to run the Digital Twin loyalty cohort
procedure against an ACT-OMOP installation on Microsoft SQL Server. Oracle and
the shared i2b2-OMOP implementation were intentionally left unchanged.

The work is currently maintained on the `loyalty-omop` branch and is not
assigned a package release number yet.

## Unreleased — SQL Server ACT-OMOP support

### Added: OMOP fact compatibility preparation

- Added
  `Crcdata/scripts/procedures/sqlserver/00_dt_loyaltycohort_prep_omop.sql`.
- Created a minimal `dbo.OBSERVATION_FACT` compatibility view containing the
  three columns read by the loyalty procedure:
  - `PATIENT_NUM`
  - `CONCEPT_CD`
  - `START_DATE`
- Combined standard and nonstandard ACT-OMOP facts from:
  - `CONDITION_VIEW` and `CONDITION_NS_VIEW`
  - `DRUG_VIEW` and `DRUG_NS_VIEW`
  - `DEVICE_VIEW` and `DEVICE_NS_VIEW`
  - `MEASUREMENT_VIEW` and `MEASUREMENT_NS_VIEW`
  - `OBSERVATION_VIEW` and `OBSERVATION_NS_VIEW`
  - `PROCEDURE_VIEW` and `PROCEDURE_NS_VIEW`
- Deliberately excluded `VISIT_NS_VIEW`. Loyalty visit features are calculated
  from `VISIT_DIMENSION` and the ACT visit ontology rather than visit fact rows.
- Added explicit casts so unions remain stable when OMOP views expose differing
  numeric or date types.
- Added support for required source objects implemented as either views or SQL
  Server synonyms.
- Added rerun and safety behavior:
  - A real i2b2 `OBSERVATION_FACT` table is never replaced.
  - An existing compatibility view can be recreated.
  - Unexpected object types cause a clear error instead of being overwritten.
  - Missing source views or synonyms are reported by name.
- Used a numeric filename prefix so automated procedure installation runs the
  prep before `usp_dt_loyaltycohort.sql`.

### Changed: ontology discovery and concept mapping

- Replaced the assumption that all ontology concepts exist in one physical
  `CONCEPT_DIMENSION` table with a private, temporary unified concept map.
- Allowed `CONCEPT_DIMENSION` and `TABLE_ACCESS` to be tables, views, or
  synonyms.
- Loaded concepts from both metadata sources when both are available. They are
  merged rather than treated as mutually exclusive alternatives.
- Read active ontology tables registered in `TABLE_ACCESS`, enabling ACT-OMOP's
  split-table metadata model.
- Added support for one-, two-, three-, and four-part ontology object names.
- Quoted each object-name component to avoid failures with qualified schemas,
  databases, linked servers, or special characters.
- Restricted the temporary concept map to the ontology branches required by
  loyalty features, demographics, and Charlson processing.
- Preserved conventional i2b2 behavior when only a unified
  `CONCEPT_DIMENSION` is present.
- Added a clustered index to the temporary concept map for repeated path and
  concept lookups.
- Added a fatal check when no configured loyalty paths match the installed
  ontology.
- Added a nonfatal warning showing how many configured paths do not match, with
  guidance to run the validation script.

### Fixed: visit feature flags

- Fixed all-zero `INP1_OPT1_VISIT`, `OPT2_VISIT`, and `ED_VISIT` results on
  hybrid installations where `CONCEPT_DIMENSION` existed but did not contain
  ACT visit concepts.
- The procedure now merges visit concepts discovered through `TABLE_ACCESS`
  even when a `CONCEPT_DIMENSION` object also exists.
- Normalized `VISIT_DIMENSION.INOUT_CD` and ontology concept codes with
  `LTRIM`/`RTRIM` and a common string conversion before comparison.
- Preserved site-specific visit codes from `DT_LOYALTY_PATHS`.
- Added a runtime visit checkpoint reporting the number of patients receiving
  each of the three visit flags.

### Changed: OMOP demographic compatibility

- Normalized OMOP gender concept IDs while building the cohort:
  - `8532` maps to `F`.
  - `8507` maps to `M`.
- Continued to recognize conventional i2b2 representations such as `F`, `M`,
  `DEM|SEX:F`, and `DEM|SEX:M`.
- Left the shared ACT-OMOP `PATIENT_DIMENSION` implementation unchanged.

### Fixed: Charlson diagnosis mapping

- Reworked Charlson mapping for ACT-OMOP metadata.
- Charlson ICD patterns are now matched against `I2B2_ACT_BASECODE`, where the
  ACT ontology stores strings such as `ICD10CM:I50.20`.
- Each matched ICD entry is translated to both fact-facing identifiers:
  - `OMOP_S_CONCEPT_ID` for `CONDITION_VIEW`
  - `OMOP_NS_CONCEPT_ID` for `CONDITION_NS_VIEW`
- Removed the unnecessary requirement for a local `dbo.CONCEPT` object before
  using the ACT-OMOP mapping columns. This supports installations where the
  ontology is exposed through `TABLE_ACCESS` and synonyms without a local OMOP
  vocabulary table.
- Preserved the original vocabulary-prefixed code matching for conventional
  i2b2 installations.
- Added runtime diagnostics reporting:
  - Number of diagnosis ontology tables discovered
  - Number of Charlson reference patterns loaded
  - Number of fact concept IDs produced
  - Number of Charlson categories mapped
  - Number of patients with one or more diagnosis-derived flags
- Added a prominent warning when no Charlson diagnosis concepts map. The
  warning explains that feature flags will remain zero and the index will
  contain age points only.
- Confirmed on an ACT-OMOP installation that both diagnosis ontology tables were
  discovered, all 17 Charlson categories mapped, and diagnosis-derived patient
  flags were populated.

### Added: SQL Server ACT-OMOP validation

- Added
  `Crcdata/scripts/validation/sqlserver/validate_dt_loyaltycohort_omop.sql`.
- Added read-only checks for required compatibility objects and Digital Twin
  reference tables.
- Treated `PATIENT_DIMENSION`, `VISIT_DIMENSION`, `CONCEPT_DIMENSION`,
  `TABLE_ACCESS`, and the OMOP vocabulary as valid when exposed as tables,
  views, or synonyms, as applicable.
- Added `OBSERVATION_FACT` coverage checks including row count, patient count,
  null keys, and earliest/latest dates.
- Added patient demographic checks for usable birth dates, recognized gender
  encodings, and available death dates.
- Added dynamic validation of configured loyalty paths against all active
  ontology tables registered in `TABLE_ACCESS`.
- Aligned validation path matching with procedure behavior by requiring a
  non-null ontology base code.
- Added summary counts for visit-path and fact-feature path coverage.
- Added visit diagnostics that compare expected ACT visit codes with actual
  `VISIT_DIMENSION.INOUT_CD` values.
- Added a report of common visit codes not covered by configured loyalty paths.
- Fixed standalone execution issues involving variable scope and synonym-backed
  objects.

### Added: documentation

- Added an ACT-OMOP installation overview and supported installation order.
- Added `docs/LOYALTY_README.md`, documenting:
  - Procedure purpose and inputs
  - Exact lookback-date boundaries
  - Initial and final patient-inclusion rules
  - Active and disabled exclusion filters
  - Definitions of all 20 loyalty features
  - Ontology and site-specific code mapping
  - Loyalty scoring and top-quintile cutoff behavior
  - Charlson timing, translation, weighting, and age points
  - Persistent output tables and rerun behavior
  - ACT-OMOP installation
  - Runtime checkpoints and troubleshooting
  - Privacy considerations and known limitations
- Documented that `@SITE` labels a result slice but does not independently
  filter source facts.
- Documented that loyalty features use the patient-specific index-date lookback,
  while Charlson uses the year preceding each patient's `LAST_VISIT`.
- Documented that the historical multi-visit filter and deceased-patient
  exclusion are currently disabled.

### Added: optional result visualization

- Added a browser-only Loyalty × Health Burden Atlas under
  `Crcdata/scripts/visualization`.
- Added two SQL Server aggregate extracts:
  - Loyalty decile × Charlson burden landscape and feature counts
  - Charlson condition prevalence by lower, middle, and upper loyalty groups
- Excluded patient identifiers from visualization output.
- Added configurable small-cell suppression, defaulting to 10 patients.
- Added a standalone HTML page with:
  - Loyalty × burden landscape
  - Twenty-feature loyalty fingerprint heatmap
  - Charlson comorbidity profile
  - Site, cohort, lookback, denominator, age, and sex filters
  - Local-only CSV loading
  - Sample-data preview
  - Print/PDF presentation mode

## Compatibility retained

- Conventional SQL Server i2b2 installations with a physical
  `OBSERVATION_FACT` table continue to use that table.
- Original i2b2 vocabulary-prefixed Charlson matching remains available when
  ACT-OMOP metadata is not present.
- Existing patient-level and summary result table schemas were not changed.
- The Oracle loyalty cohort procedure was not modified as part of this work.
- Shared ACT-OMOP views were not modified; compatibility is implemented locally
  in the Digital Twin package.

## Known limitation

The current ACT-OMOP `PATIENT_DIMENSION` compatibility view returns a null
`DEATH_DATE`. Therefore, loyalty `DEATH_DT` remains null even when the OMOP
`DEATH` table contains a record. The prep script and documentation contain a
prominent notice, but death mapping is intentionally deferred to a future
change.

## Related commits

- `be9291b` — Loyalty script modifications to support OMOP (MSSQL)
- `ad07676` — Fix validation script, load both ontologies and concept dimension
- `b6a9c0a` — Support Charlson when concept table is not a physical table in
  this database
- `5333fd9` — Add the loyalty output visualization

