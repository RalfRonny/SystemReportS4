# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

One executable ABAP report, `ZBC_S4_DATASELECTION` (package `ZICL_BCS4`, abapGit offline repo `ZICL_BCS4_offline`), that collects the figures of the "Data & Org Questionnaire" for the S/4HANA evaluation from SAP ECC instances. `ZBC_S4_DATASELECTION_Design.md` is the authoritative specification: definitions of every figure (section 7), details (8.2), text ID scheme (12.2), syntax rules (13.1), and the text tables in appendices A to C. Read the relevant section before changing a figure, and update the design when code and design diverge.

There's no local ABAP compiler or test tooling. The code is compiled, activated and tested only inside SAP after an abapGit import. Don't invent local build or test commands. The SAP syntax check stops at the first error, so the user reports errors one at a time (e.g. as `E:\issue.txt`).

## Build and transfer

- `/abapgit` (or `python make_abapgit_zip.py`) regenerates the program files under `src/`, checks the text pool against the source, and writes `C:\claudeCode\Systemreport-abapgit.zip` from `main` with `git archive`. Uncommitted changes are not in the ZIP; the script prints a `NOTE`. In SAP: abapGit → *Import zip* → *Pull* → activate.
- Maintained sources are `zbc_s4_dataselection.abap` (program) and `textpool.tsv` (all texts, EN + DE). `src/zbc_s4_dataselection.prog.abap`, `.prog.xml` and `.prog.i18n.de.po` are **generated**. Never edit them by hand, and commit them together with their sources.
- `.abapgit.xml` and `src/package.*` come from the system export. Master language is English, German is in LXE `.po` files sorted by msgid in binary order (as abapGit exports them).

## Code rules (design 2 and 13)

- **Classic ABAP syntax only**, compilable on SAP_BASIS 7.00 to 7.5x: no inline declarations, no `@` host variables, no string templates or `&&`, no constructor operators (`VALUE`, `NEW`, `CONV`, `COND`, ...), no table expressions, no method chaining, no functional calls in operand positions other than the right side of an assignment. Classic Open SQL (blank-separated field lists, `INTO` after the field list), no joins, no `UNION`.
- SAP standard tables only, no Z objects, no customizing values hard-coded. Classify customizing through SAP attributes. Constants are restricted to SAP-defined values.
- **No user-visible literals.** Every text is a text pool entry, looked up with `lcl_text=>get( 'ID' )` (logon language, gaps filled from EN). Add each new ID to `textpool.tsv` in EN and DE and to the ranges in `lcl_text=>get_missing`. `make_abapgit_zip.py` fails if a literal ID, a `get_missing` ID or a parameter has no text.
- `CATCH` of a superclass and its subclass in one `TRY` is a syntax error (`CX_SY_IMPORT_MISMATCH_ERROR` already covers `CX_SY_IMPORT_FORMAT_ERROR`).
- Typed method parameters need an exact type match. Copy text and numbers into typed variables before passing them (e.g. SALV `scrtext_*`, `ty_num`).

## Architecture

Local classes in one program, in this order: `lcl_text` (text pool lookup) → `lcl_period` (analysis period) → `lcl_store` (result cluster in INDX, versioned by `gc_version`, raise it whenever a stored type changes) → `lcl_collector` → `lcl_output` → `lcl_app` (event flow).

**Collection model (`lcl_collector`).** Figures are rows of one sorted table `ms_res-figs`, keyed by text ID (`Qnn` questionnaire row, `Dnn` detail) plus an optional sub key (e.g. material type). `register` declares the detail headers (`add_detail`, ID and group `Gnn`) and the **steps** (`add_step`). A step is one pass over a table and lists the figure keys it feeds. `run_step` dispatches by step name inside `TRY ... CATCH cx_root`. On failure all its keys show "error", and the step is added to `ms_res-errors`, which view 4 lists under INFO. Steps without figure keys (organizational unit lists, G5–G7, application usage) rely on that list. Steps set values only through `set_b` (current number) and `set_c` (created in period, the total; the average is computed at display). Neither of them overwrites an "error" status, so a figure fed by several steps keeps a failure. N/A cells by design are fixed in `init_figures`. Values that depend on a skipped block show "not collected": G5–G7 via `ms_res-meta-g*_st`, organization rows via `ty_org-status`. If the source step failed instead, `src_status` finds it in `ms_res-errors` and the value shows "error".

Blocks run in the order BASE (always: active company codes, `mt_t001`, `mt_bukrs_act`, `mv_base_ok`), MD, FI, SD, MM, PP, ORG, INTF (scope checkboxes), DERV (always last; cross-block figures). Steps that depend on BASE return early if `mv_base_ok` is initial, so their figures stay "not collected".

To add a figure: write a `step_*` method (one pass per large table, aggregate on the database, `FOR ALL ENTRIES` only with a non-empty driver), add it to `register` and the `CASE` in `run_step`, add detail headers if needed (numbering follows design 8.2), add texts, and update the design.

**Output (`lcl_output`).** Five views built from the stored result: SALV fullscreen in dialog, WRITE list into the spool in background. The result holds keys and numbers only. Texts, including sub-key texts (`sub_text`, e.g. T134T, T001), are resolved at display time in the display language. Value columns are character fields, so "N/A" and numbers share one column.

## Verification

Without an SAP system, changes are checked by independent review against the ABAP rules, the ECC 6.0 DDIC and the design. What the real system already activated is the reliable baseline.
