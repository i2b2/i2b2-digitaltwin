# Loyalty reference CSVs

These files provide reference data for CSV import when running the inserts is
inconvenient. The original three CSVs reproduce
[`insert_loyalty_ref_oracle.sql`](../Crcdata/act/scripts/oracle/insert_loyalty_ref_oracle.sql).
The SQL Server Charlson CSV reproduces the Charlson inserts in
[`insert_loyalty_ref_sqlserver.sql`](../Crcdata/act/scripts/sqlserver/insert_loyalty_ref_sqlserver.sql).

| File | Target table | Data rows |
| --- | --- | ---: |
| [dt_loyalty_paths.csv](dt_loyalty_paths.csv) | `DT_LOYALTY_PATHS` | 125 |
| [dt_loyalty_charlson.csv](dt_loyalty_charlson.csv) | `DT_LOYALTY_CHARLSON` | 496 |
| [dt_loyalty_charlson_sqlserver.csv](dt_loyalty_charlson_sqlserver.csv) | `dbo.DT_LOYALTY_CHARLSON` | 138 |
| [dt_loyalty_pscoeff.csv](dt_loyalty_pscoeff.csv) | `DT_LOYALTY_PSCOEFF` | 20 |

Paths and coefficients are identical in the two source scripts. Select the
Charlson CSV matching your database; do not load both.

See the [usage guide](LOYALTY_README.md#reference-data) for import settings and
upgrade instructions, and [architecture and process](LOYALTY_ARCHITECTURE_README.md#reference-pattern-representation)
for how the Charlson patterns correspond across platforms.

Column order, row order, duplicate rows, and values are preserved from the source
SQL. SQL delimiters are removed, escaped apostrophes decoded, and nulls represented
as empty fields. Numeric literals retain their source precision, including
`0.050`. Regenerate and verify these CSVs when the source inserts change.
