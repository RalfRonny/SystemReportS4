---
name: abapgit
description: Build the abapGit offline ZIP of ZICL_BCS4 (program ZBC_S4_DATASELECTION; .abapgit.xml + src/, from main, program files regenerated from zbc_s4_dataselection.abap and textpool.tsv) into C:\claudeCode\Systemreport-abapgit.zip. Use when the user types /abapgit or asks for the abapGit ZIP.
disable-model-invocation: true
---

# /abapgit — build the abapGit ZIP

Run the project script from the repository root and report its result:

```bash
python make_abapgit_zip.py
```

- It first regenerates `src/zbc_s4_dataselection.prog.abap`, `.prog.xml` (text pool EN) and
  `.prog.i18n.de.po` (DE) from `zbc_s4_dataselection.abap` and `textpool.tsv`. Never edit those
  three files under `src/` by hand; change the two sources instead.
- Then it builds `C:\claudeCode\Systemreport-abapgit.zip` from **`main`** with `git archive`,
  containing only `.abapgit.xml` and `src/` (what abapGit reads), overwriting the previous one.
- If the user named a branch or commit (e.g. `/abapgit HEAD`, `/abapgit my-branch`), pass it:
  `python make_abapgit_zip.py --ref <ref>`.
- Do **not** commit, merge, pull or switch branches on your own. If the script prints a `NOTE`
  (files that differ from the commit — typically sources changed and `src/` regenerated but not
  committed —, working copy on another branch, local `main` behind `origin/main`), tell the user
  what it means and ask whether to commit (sources and regenerated `src/` files together) or pull
  first, then run the script again.
- If it prints an `ERROR` or exits 1 (text ID or selection text missing in `textpool.tsv`, text too
  long, two DE translations for one EN text, REPORT name wrong, malformed XML), show the findings
  and do not call the ZIP usable. Offer to fix `textpool.tsv` or the source, but do not change
  texts on your own.

Reply briefly, in the user's language: the ZIP path, the commit it holds (short hash + subject),
text counts, file count and size, any NOTE/ERROR — and the next step in SAP: abapGit → offline
repo *ZICL_BCS4_offline* → *Import zip* → *Pull* → activate `ZBC_S4_DATASELECTION`.
