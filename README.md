# ZBC_S4_DATASELECTION – Data & Org Questionnaire figures from SAP ECC (ABAP)

An SAP ABAP report that collects the figures of the "Data & Org Questionnaire" for the S/4HANA evaluation from an SAP ECC instance. All ICL ECC systems use the same definitions, so their results can be compared and reproduced. It covers the questionnaire figures the SAP Readiness Check does not provide.

The repository is an [abapGit](https://abapgit.org) export (package `ZICL_BCS4`). No code is built or run here: it is imported into an SAP system and activated there.

## Contents

| File | Purpose |
|---|---|
| `ZBC_S4_DATASELECTION_Design.md` | Specification: scope, definition of every figure, output views, texts, technical rules, rollout |
| `zbc_s4_dataselection.abap` | Program source (maintained here) |
| `textpool.tsv` | All texts of the program in English and German (maintained here) |
| `make_abapgit_zip.py` | Regenerates the program files under `src/` and builds the abapGit ZIP |
| `.abapgit.xml`, `src/` | What abapGit reads. The program files in `src/` are generated, don't edit them by hand |

## Installation

1. Build the ZIP: `python make_abapgit_zip.py`. It writes `Systemreport-abapgit.zip` into the parent folder, taken from `main`.
2. In SAP, in an abapGit **offline** repository for package `ZICL_BCS4`: *Import zip*, then *Pull*. Activate `ZBC_S4_DATASELECTION`.
3. Check the text elements in German and English logon.

## Running

Schedule a background job in the productive client: mode "Collect data", period empty (= last 12 complete months), store result, logon language EN. Then start the report in dialog with "Display stored result" and copy the views into the questionnaire. See section 14.3 of the design.

Translations: English is the master language. German texts are included as `*.i18n.de.po` files.
