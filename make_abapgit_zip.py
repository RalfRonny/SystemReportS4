"""
Build the abapGit offline ZIP for ZICL_BCS4 (program ZBC_S4_DATASELECTION).

    python make_abapgit_zip.py              # from main, into the parent folder
    python make_abapgit_zip.py --ref HEAD   # from the checked-out commit instead
    python make_abapgit_zip.py --out D:\\x   # into another folder

Two steps:

1. Regenerate the program files under src/ from the two maintained sources:
     zbc_s4_dataselection.abap  -> src/zbc_s4_dataselection.prog.abap
     textpool.tsv (EN + DE)     -> src/zbc_s4_dataselection.prog.xml (TPOOL, EN)
                                   src/zbc_s4_dataselection.prog.i18n.de.po (DE, LXE)
                                   src/zbc_s4_dataselection.prog.i18n.es.po (ES, empty)
   The text pool is checked first: every text ID and parameter used in the
   source has a text, lengths fit (text symbol 132, selection text 30, title 70),
   and one EN text has one DE translation (the .po maps source text -> translation).
   The .po is sorted by msgid in binary order, as abapGit exports it, so the
   next export from SAP shows no difference.

2. ZIP only what abapGit reads: `.abapgit.xml` at the root and `src/` (its
   STARTING_FOLDER), taken with `git archive` from a COMMIT, never from the
   working tree: what goes to SAP is exactly what is versioned. Changes that
   are not committed (sources or regenerated src/) are therefore NOT in it --
   the script says so rather than silently leaving them out. The file name is
   fixed (`Systemreport-abapgit.zip`) and overwritten on every run, so there is
   only ever one to pick in abapGit's "Import zip"; the commit it holds is
   printed and written into the ZIP comment.

Checks before it reports success: the REPORT statement names the program,
`.abapgit.xml` sits at the root, and every XML in the ZIP is well-formed
(abapGit refuses a malformed one with "XML parser error, unexpected symbol").
Exit code 1 on any failure.
"""
import argparse
import csv
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent
NAME = "Systemreport-abapgit.zip"
PATHS = [".abapgit.xml", "src"]
SOURCES = ["zbc_s4_dataselection.abap", "textpool.tsv"]
PROG = "ZBC_S4_DATASELECTION"
ABAP_SRC = ROOT / "zbc_s4_dataselection.abap"
TEXTS = ROOT / "textpool.tsv"

MAX_LEN = {"I": 132, "S": 30, "R": 70}   # text symbol, selection text, title
SEL_LENGTH = 38                            # LENGTH abapGit writes for selection texts (30 + 8)


# --- step 1: generate src/ ---------------------------------------------------

def load_texts():
    # utf-8-sig: Excel and Windows editors save the TSV with a BOM
    with TEXTS.open(encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE))


def check_texts(rows, abap):
    errors = []
    keys = set()
    translation = {}
    for r in rows:
        key = (r["ID"], r["KEY"])
        if r["ID"] not in MAX_LEN:
            errors.append(f"{key}: unknown text type")
            continue
        if key in keys:
            errors.append(f"{key}: duplicate")
        keys.add(key)
        if r["ID"] == "I" and not re.fullmatch(r"[A-Z0-9_]{3}", r["KEY"]):
            errors.append(f"{key}: text symbol ID must have 3 characters")
        if r["ID"] == "S" and not re.fullmatch(r"[A-Z0-9_]{1,8}", r["KEY"]):
            errors.append(f"{key}: selection text name must have 1-8 characters")
        for lang in ("EN", "DE"):
            if not r[lang]:
                errors.append(f"{key}: {lang} empty")
            elif len(r[lang]) > MAX_LEN[r["ID"]]:
                errors.append(f"{key}: {lang} has {len(r[lang])} characters, max {MAX_LEN[r['ID']]}")
        if translation.setdefault(r["EN"], r["DE"]) != r["DE"]:
            errors.append(f"{key}: EN text {r['EN']!r} already has a different DE translation")

    symbols = {k for t, k in keys if t == "I"}
    selections = {k for t, k in keys if t == "S"}

    # Every literal text ID in the source must exist
    for tid in sorted(set(re.findall(r"'([A-Z][0-9]{2})'", abap))):
        if tid not in symbols:
            errors.append(f"text ID '{tid}' used in the source but missing in textpool.tsv")
    # Every ID the program's completeness check (lcl_text=>get_missing) expects must exist
    for prefix, frm, to in re.findall(r"iv_prefix = '(\w)' iv_from = (\d+)\s+iv_to = (\d+)", abap):
        for nr in range(int(frm), int(to) + 1):
            tid = f"{prefix}{nr:02d}"
            if tid not in symbols:
                errors.append(f"text ID '{tid}' expected by get_missing but missing in textpool.tsv")
    # Every parameter needs a selection text
    for name in re.findall(r"^\s*(?:PARAMETERS:)?\s*(p_\w+)\s+(?:TYPE|RADIOBUTTON|AS)\b", abap, re.M | re.I):
        if name.upper() not in selections:
            errors.append(f"parameter {name.upper()} has no selection text")
    return errors


def symbol_length(r):
    return max(len(r["EN"]), len(r["DE"]))


def build_prog_xml(rows):
    def item(lines, **fields):
        lines.append("    <item>")
        for tag, value in fields.items():
            lines.append(f"     <{tag}>{escape(str(value))}</{tag}>")
        lines.append("    </item>")

    lines = [
        '<?xml version="1.0" encoding="utf-8"?>',
        '<abapGit version="v1.0.0" serializer="LCL_OBJECT_PROG" serializer_version="v1.0.0">',
        ' <asx:abap xmlns:asx="http://www.sap.com/abapxml" version="1.0">',
        "  <asx:values>",
        "   <PROGDIR>",
        f"    <NAME>{PROG}</NAME>",
        "    <SUBC>1</SUBC>",
        "    <RLOAD>E</RLOAD>",
        "    <FIXPT>X</FIXPT>",
        "    <UCCHECK>X</UCCHECK>",
        "   </PROGDIR>",
        "   <TPOOL>",
    ]
    for r in sorted((r for r in rows if r["ID"] == "I"), key=lambda r: r["KEY"]):
        item(lines, ID="I", KEY=r["KEY"], ENTRY=r["EN"], LENGTH=symbol_length(r))
    for r in (r for r in rows if r["ID"] == "R"):
        item(lines, ID="R", ENTRY=r["EN"], LENGTH=MAX_LEN["R"])
    for r in sorted((r for r in rows if r["ID"] == "S"), key=lambda r: r["KEY"]):
        item(lines, ID="S", KEY=r["KEY"], ENTRY=r["EN"], LENGTH=SEL_LENGTH)
    lines += [
        "   </TPOOL>",
        "  </asx:values>",
        " </asx:abap>",
        "</abapGit>",
    ]
    return "\n".join(lines) + "\n"


def build_po(rows, lang):
    """LXE .po for one language. lang "DE" carries the translations from the
    TSV; any other language (e.g. "ES", listed in .abapgit.xml) is exported by
    abapGit with empty msgstr until it is translated in SAP, so it is generated
    the same way. References of one msgid are sorted, as SAP lists them."""
    def quote(text):
        return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'

    refs = {}
    for r in rows:
        if r["ID"] == "I":
            length = symbol_length(r)
            ref = f"RPT4/{PROG}/TEXT {r['KEY']} {length}, maxlen={length}"
        elif r["ID"] == "S":
            ref = f"RPT4/{PROG}/SELECT {r['KEY']}, maxlen={MAX_LEN['S']}"
        else:
            ref = f"RPT4/{PROG}/TITLE, maxlen={MAX_LEN['R']}"
        target = r["DE"] if lang == "DE" else ""
        refs.setdefault((r["EN"], target), []).append(ref)

    lines = [
        "#, fuzzy",
        'msgid ""',
        'msgstr ""',
        '"MIME-Version: 1.0\\n"',
        '"Content-Type: text/plain; charset=UTF-8\\n"',
        '"Content-Transfer-Encoding: 8bit\\n"',
    ]
    for (en, de), ref_list in sorted(refs.items()):
        lines.append("")
        lines += [f"#: {ref}" for ref in sorted(ref_list)]
        lines.append(f"msgid {quote(en)}")
        lines.append(f"msgstr {quote(de)}")
    return "\n".join(lines) + "\n"


def generate():
    """Write the program files into src/. Returns (errors, generated contents)."""
    abap = ABAP_SRC.read_text(encoding="utf-8").replace("\r\n", "\n")
    if not abap.endswith("\n"):
        abap += "\n"
    rows = load_texts()

    errors = check_texts(rows, abap)
    report = re.search(r"^\s*REPORT\s+(\w+)", abap, re.M | re.I)
    if not report or report.group(1).upper() != PROG:
        errors.append(f"REPORT statement does not name {PROG}")
    if errors:
        return errors, rows, {}

    stem = PROG.lower() + ".prog"
    files = {
        f"{stem}.abap": (abap, "utf-8"),
        f"{stem}.xml": (build_prog_xml(rows), "utf-8-sig"),   # abapGit XML carries a BOM
        f"{stem}.i18n.de.po": (build_po(rows, "DE"), "utf-8"),
        f"{stem}.i18n.es.po": (build_po(rows, "ES"), "utf-8"),
    }
    for name, (text, encoding) in files.items():
        (ROOT / "src" / name).write_text(text, encoding=encoding, newline="\n")
    return [], rows, files


# --- step 2: ZIP from a commit -------------------------------------------------

def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True,
                          text=True, encoding="utf-8").stdout.strip()


def main():
    ap = argparse.ArgumentParser(description=__doc__.strip().split("\n\n")[0])
    ap.add_argument("--ref", default="main", help="commit or branch (default: main)")
    ap.add_argument("--out", default=str(ROOT.parent), help="target folder (default: parent of the project)")
    a = ap.parse_args()

    errors, rows, _ = generate()
    if errors:
        for m in errors:
            print(f"ERROR   : {m}")
        print("ERROR   : src/ not regenerated, no ZIP written")
        sys.exit(1)

    sha = git("rev-parse", "--short", a.ref)
    if not sha:
        sys.exit(f"ERROR   : unknown ref {a.ref!r}")
    subject = git("log", "-1", "--format=%s", a.ref)
    date = git("log", "-1", "--format=%ci", a.ref)

    notes = []
    # Working tree (after regeneration) against the commit the ZIP is built from
    tracked = PATHS + SOURCES
    changed = git("diff", "--name-only", a.ref, "--", *tracked).splitlines()
    changed += git("ls-files", "--others", "--exclude-standard", "--", *tracked).splitlines()
    if changed:
        notes.append(f"{len(changed)} file(s) differ from {a.ref} and are NOT in the ZIP: "
                     f"{', '.join(sorted(set(changed)))} -- commit them first if SAP needs them "
                     "(regenerated src/ files belong in the same commit as their sources)")
    current = git("rev-parse", "--abbrev-ref", "HEAD")
    if a.ref == "main" and current != "main":
        notes.append(f"the working copy is on branch {current!r}; the ZIP holds main, not that branch")
    if a.ref == "main" and git("rev-parse", "--verify", "-q", "origin/main"):
        behind = git("rev-list", "--count", "main..origin/main")
        if behind and behind != "0":
            notes.append(f"local main is {behind} commit(s) behind origin/main "
                         "(last fetch) -- run `git pull` on main first to include them")

    out = Path(a.out) / NAME
    r = subprocess.run(["git", "archive", "--format=zip", "-o", str(out), a.ref, "--", *PATHS],
                       cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"ERROR   : git archive failed: {r.stderr.strip()}")

    with zipfile.ZipFile(out, "a") as z:
        names = z.namelist()
        if ".abapgit.xml" not in names:
            errors.append(".abapgit.xml is not at the root of the ZIP")
        xmls = [n for n in names if n.endswith(".xml")]
        for n in xmls:
            try:
                ET.fromstring(z.read(n))
            except ET.ParseError as e:
                errors.append(f"not well-formed: {n}: {e}")
        z.comment = f"ZICL_BCS4 abapGit {a.ref} {sha} {date} {subject}".encode("utf-8")[:65535]

    files = [n for n in names if not n.endswith("/")]
    counts = {t: sum(1 for r in rows if r["ID"] == t) for t in MAX_LEN}
    size = out.stat().st_size / 1e6
    print(f"ZIP     : {out}")
    print(f"Commit  : {sha}  {date}  {subject}")
    print(f"Texts   : {counts['I']} text symbols, {counts['S']} selection texts, {counts['R']} title (EN + DE)")
    print(f"Content : {len(files)} files ({len(xmls)} XML), {size:.2f} MB -- .abapgit.xml + src/")
    for m in notes:
        print(f"NOTE    : {m}")
    for m in errors:
        print(f"ERROR   : {m}")
    if errors:
        sys.exit(1)
    print("OK      : all XML well-formed -- abapGit: Import zip, then Pull")


if __name__ == "__main__":
    main()
