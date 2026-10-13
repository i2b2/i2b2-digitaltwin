# Loyalty × Health Burden Atlas

This directory contains a browser-only visualization of the patient-level
loyalty and Charlson result tables. The supplied SQL Server and Oracle queries
aggregate the data and do not return patient identifiers.

## Create the CSV files

1. Review the filter values and minimum cell size at the top of each query.
   Use the scripts under `sqlserver/` or `oracle/` for your database.
2. Run `01_extract_loyalty_landscape.sql` and save the result grid as
   `loyalty_landscape.csv`, including column headers.
3. Run `02_extract_charlson_profile.sql` and save the result grid as
   `charlson_profile.csv`, including column headers.

The default minimum cell size is 10. Confirm the appropriate disclosure policy
with your institution before sharing either CSV or a rendered figure.

## View the atlas

Open `loyalty-burden-atlas.html` in a modern browser and select both CSV files.
No server is required, and the page does not upload the selected files. Use the
filters to prepare a view, then use **Print / save PDF** for a presentation or
poster-ready output. **Preview with sample data** demonstrates the layout
without using research data.

Because suppressed cells are excluded, displayed counts describe represented
patients and can be smaller than the full cohort count.
