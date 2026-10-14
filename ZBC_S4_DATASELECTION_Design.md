# ZBC_S4_DATASELECTION – Design Specification

**Purpose:** A single ABAP report that collects the figures of the "Data & Org Questionnaire" (S/4HANA evaluation) from an SAP ECC instance. The definitions are identical on every instance, so the results of all ICL ECC systems can be compared and reproduced. The report covers the questionnaire figures that the SAP Readiness Check does not provide. It complements the Readiness Check and does not replace it.

**Status:** Draft v0.2 – 2026-10-12 – J. Münch (BKG)

---

## 1. Scope

| Questionnaire area | Delivered by the report | Remains manual |
|---|---|---|
| Rows 3–29, columns B ("Current number") and C ("Average added per Month/Year") | All rows. Values where derivable, otherwise "N/A" with a remark | – |
| Column D (free note per row) | Short basis note per row (optional paste) | – |
| G5 countries, G6 languages, G7 currencies | One comma-separated list each (long lists wrap into further rows) | – |
| Ownership structure, "US Based" | – | Manual |
| Business functions (centralized / de-centralized) | Usage indicator per application area (documents in the period), to support "Not Applicable" | Centralized / de-centralized, comments |
| Plant table (Name of the Plant, Location, Approx Revenue, On SAP, On Legacy System) | Name, location, On SAP | Approx revenue, legacy flag |
| Organizational units (purchasing / sales organizations, distribution channels, divisions) | Lists with "used in period" flag | – |
| Sheet "Applications", sheet "Sample System Landscape" | Optional: list of technical connections as a candidate list | Classification, workstream, description, pain points, diagram |

---

## 2. Design principles

| # | Principle | Consequence |
|---|---|---|
| 1 | SAP standard only | Only SAP standard tables and fields. No Z-objects, no Dictionary objects, no dependency on add-on frameworks such as abap2xlsx. |
| 2 | No customer customizing values in the code | No order types, document types, account groups, partner functions, roles, posting keys or payment methods are hard-coded. Constants are restricted to **SAP-defined values**: document categories (VBTYP, BSTYP), order categories (AUTYP), user types, IDoc direction, the partner type "logical system", and SAP system statuses. |
| 3 | Customizing is classified through its SAP attributes, never through its key values | Incoming payments are identified by posting key attributes (account type, debit/credit, payment-transaction flag). EFT is identified by payment method classification ("bank transfer"). |
| 4 | Each definition travels with its number | Every output row carries its definition. Column D receives a short basis note. The full definition list goes to SAP together with the numbers. |
| 5 | One time logic for all figures | "Added" and "active" are always based on the **creation / entry date** of the record (ERDAT, ERSDA, CPUDT, AEDAT, CREDAT), never on document or posting dates. Backdated postings are therefore counted when they are entered, consistently on all instances. |
| 6 | Calendar months, complete months only | Fiscal year variants are customizing and differ between instances. The default period is the last 12 complete calendar months. Average per month = created in period ÷ number of months. |
| 7 | Documents, not line items | When a figure is based on line-item tables, distinct document keys are counted. |
| 8 | Portable syntax | Classic ABAP syntax that compiles on every ECC release in scope (see 13.1). One executable program with local classes, no includes. |
| 9 | All texts in the text pool, DE and EN | No user-visible literals in the source code. All texts are text elements, maintained completely in German and English (see 12). |
| 10 | Robust | Each figure is collected in its own exception handler. If a figure fails, it shows "error" plus the reason and the run continues. |
| 11 | Heavy run in background, display in dialog | The data collection runs as a background job and stores its result. It can then be displayed in dialog for copy and paste. |
| 12 | Read-only towards business data | The only write operation is the temporary result cluster (see 13.5). |
| 13 | Counts only | No amounts, no personal data, no names of customers, vendors or users are output. |

---

## 3. Basic definitions

| Term | Definition |
|---|---|
| Analysis period | From the 1st day of a month to the last day of a month, ending before the current month. Default: 12 complete months back from the current month. |
| Months | Number of calendar months in the analysis period, derived from the dates. |
| Created in period | Creation or entry date of the record within the analysis period. |
| Average added per month (column C) | Created in period ÷ months, rounded commercially to a whole number. |
| Current number (column B) | Stock figure on the run date. For master data this is the current count. For documents it is the number currently **open**. For pure flow figures, which have no stock, it is "N/A". |
| Total in period | Created in period (absolute). Shown as an extra column so that small averages (rounded to 0) stay visible. |
| Active company code | Company code with at least one FI document entered in the period. Charts of accounts, banks, plants and countries are derived from the active company codes. Unused and sample company codes are therefore excluded. |
| N/A | Output literally as "N/A" in the cells the questionnaire answers with N/A by design, and where a figure cannot be derived generically. |
| Number format | Digits only, without thousands separator or decimals, so that pasting into Excel works regardless of locale. |

---

## 4. Selection screen

All names have at most 8 characters, all texts are selection texts / text symbols (see 12).

| Block | Element | Type | Default | Remark |
|---|---|---|---|---|
| Mode | P_COLL – Collect data | Radio button (group MODE) | X | Background job for the official run. In dialog only for tests with reduced scope. |
| | P_SHOW – Display stored result | Radio button | | Shows the stored result of the last run without new selection. |
| | P_DEL – Delete stored result | Radio button | | Removes the stored result cluster. |
| Analysis period | P_DATFR – from | Date | empty → computed at runtime | If empty: 1st day of the month 12 months back. A job variant with empty dates therefore always uses the current default. |
| | P_DATTO – to | Date | empty → computed at runtime | If empty: last day of the previous month. |
| Scope | P_MD, P_FI, P_SD, P_MM, P_PP, P_ORG | Checkboxes | all X | Master data, financials, sales, purchasing/inventory, production/maintenance, organization/technical. Only for skipping heavy blocks in tests. Skipped figures show "not collected", never 0. |
| | P_INTF – Interfaces | Checkbox | space | Optional block (see 11). |
| Output | P_V1 … P_V5 | Radio buttons (group VIEW) | P_V1 | View to display: Questionnaire / Plants / Organization / Details / Interfaces. |
| | P_STORE – Store result | Checkbox | X | Store the result cluster after collection. |

Validation (AT SELECTION-SCREEN, also effective in background):
- "from" must be the 1st day of a month, "to" the last day of a month.
- "to" must lie before the current month (only complete months) and must not precede "from".
- If P_SHOW is selected and no stored result exists, a message is shown.

---

## 5. Processing model

```
INITIALIZATION        load texts: text pool of the logon language, missing entries from EN (12.3)
                      block titles from the lookup
                      defaults (period computed only if fields are initial)
AT SELECTION-SCREEN   period validation (empty dates = default period)
START-OF-SELECTION
  text check          message listing missing text IDs
  mode COLLECT        run blocks BASE, MD, FI, SD, MM, PP, ORG, (INTF), DERV
                      each step: TRY ... CATCH -> status "error" + exception text (13.3)
                      record runtime per block
                      store result cluster (if P_STORE)
  mode SHOW           import stored result cluster
  mode DELETE         delete stored result cluster
END-OF-SELECTION
  dialog              SALV fullscreen of the selected view
  background          WRITE list of all views into the spool; messages into the job log
```

Blocks:
- **BASE** is always collected: active company codes (row 3). Rows 4, 18 and 27 and the G5 countries depend on it.
- **MD … INTF** follow the scope checkboxes.
- **DERV** is always run last. It derives figures that combine several blocks (rows 7 and 9, G5–G7). A derived figure stays "not collected" if one of its source blocks was skipped, and shows "error" if one of its source steps failed.

A **step** is one pass over a table (see the rules below). Each step declares the figures it feeds.

Rules for collection:
- **One pass per large table.** Each large table is read once per run. Several figures are derived from that one pass (e.g. sales orders: count per category, distinct sold-to parties, sales organizations, currencies).
- **Aggregation on the database** (COUNT, COUNT DISTINCT, GROUP BY) wherever the result is a number. Only small result sets are transferred.
- **Distinct sets are merged in ABAP** (sorted tables, delete adjacent duplicates), e.g. active customers from sales orders plus FI line items. No SQL UNION.
- **No joins.** Small customizing and organizational tables are read completely and combined in ABAP.
- **Large scans with PACKAGE SIZE**, so that memory stays bounded.
- **FOR ALL ENTRIES only with a non-empty driver table.** If the driver table is empty, the select is skipped, because otherwise all rows would be read.
- The result stores **keys and numbers only, no texts**. Texts are resolved at display time in the display language (exception: master-data names such as plant names and organizational unit texts, which are stored as read).

---

## 6. Output views

Dialog: CL_SALV_TABLE fullscreen, standard toolbar (all functions incl. export), no sorting by default. Rows stay in questionnaire order so that a block of cells can be copied (Ctrl+C) and pasted as one block. Background: the same views as a WRITE list in the spool.

### 6.1 View 1 – Questionnaire (rows 3–29)

| Column | Content | Paste target |
|---|---|---|
| Row | Questionnaire row number (3–29) | – |
| Item | Item text (EN = questionnaire wording) | – |
| **Current number** | Column B value | **B** |
| **Avg added/month** | Column C value | **C** |
| **Basis** | Short basis note | **D** (optional) |
| Total in period | Created in period (absolute) | – |
| Definition | Full definition | – |
| Remark | Caveats | – |

Exactly 27 rows. Row 17 ("Banking") is an empty header row, so that B3:C29 (or B3:D29) can be pasted as one contiguous block.

### 6.2 View 2 – Plants

| Column | Content | Paste target |
|---|---|---|
| **Name of the Plant** | "WERKS - NAME1" | **F** |
| **Location** | Country key of the plant | **G** |
| **Approx Revenue** | empty (manual) | **H** |
| **On SAP** | X | **I** |
| **On Legacy System** | empty (manual) | **J** |
| City | City of the plant | – |
| Company code | Company code of the plant's valuation area | – |
| Counted in row 27 | X if the company code is active | – |
| Manufacturing | X if production or process orders were created for the plant in the period | – |

All plants are listed. The relevant rows are filtered with the "Counted in row 27" column. Paste position: first data row of the plant table in the questionnaire sheet of the instance.

### 6.3 View 3 – Organization

| Group | Key | Description | Value | Used in period |
|---|---|---|---|---|
| G5 Countries | number of entries | – | comma-separated country keys | – |
| G6 Languages | number of entries | – | comma-separated ISO language codes | – |
| G7 Currencies | number of entries | – | comma-separated currency keys | – |
| Purchasing organizations | EKORG | text | company code | X / space |
| Sales organizations | VKORG | text | company code | X / space |
| Distribution channels | VTWEG | text | – | X / space |
| Divisions | SPART | text | – | X / space |
| Application usage | area | text | documents created in period | X if > 0 |

G5–G7 are one list each, because the target cells are single (merged) cells. A list longer than 120 characters continues in further rows of the same group; each row except the last ends with a comma (spool column 120, ALV grid cell 128 characters). The key column of the first row shows the number of entries, so the pasted list can be checked. Each of G5–G7 and each "used" cell shows "not collected" if a source block was skipped (G5: BASE; G6: FI, SD and MM; G7: BASE, SD and MM; used: MM for purchasing organizations, SD for sales organizations, distribution channels and divisions; application usage: the block of the source figure) and "error" if a source step failed (taken from the failed-step list; "error" wins if one source was skipped and another failed).

### 6.4 View 4 – Details and definitions

Columns: Group | Item | Value | Avg added/month | Total in period | Definition | Remark.
The groups are INFO (run metadata, see 8.1) and all supporting figures (see 8.2). The supporting figures are sorted by group, within a group by detail number, each header before its sub rows, so every group appears once.

### 6.5 View 5 – Interfaces (optional)

Columns: Object type | Name | Type | Description | Release | SP level | IDocs in period. See 11. Rows are grouped by object type in the order of section 11. An object type whose step failed shows one row "error"; if the block was skipped, each object type shows one row "not collected".

---

## 7. Questionnaire figures (rows 3–29)

B = column "Current number", C = column "Average added per Month/Year". "Created ÷ months" always refers to the analysis period. View 1 shows the average with the suffix "(M)" (per month, text M16), e.g. "2703 (M)"; N/A, "error" and "not collected" get no suffix.

| Row | Item | B (Current number) | C (Average added per month) | Remark |
|---|---|---|---|---|
| 3 | No of Company Codes | Active company codes: company codes (T001) with at least one FI document entered in the period (BKPF, CPUDT). Existence check per company code (one row is enough). | N/A | All company codes in the details. |
| 4 | No. of Chart of Accounts | Distinct charts of accounts (T001-KTOPL) of the active company codes. Shown as "n (m local, x group)" with m = country charts (D28) and x = group charts (D29), e.g. "1 (4 local, 1 group)"; only the number if D28/D29 were not collected (text cell, texts M14/M15) | N/A | SAP-delivered charts that are not assigned to an active company code are not counted. Country and group charts of accounts in the details (D28, D29); view 1 adds their number and keys to the remark of row 4 at display time, e.g. "Country charts of accounts: 4 (CAFR, CAIN, CAPL, CARO); Group charts of accounts: 1 (ICLC)". |
| 5 | No. of G/L Accounts | G/L accounts at chart-of-accounts level (SKA1) for the charts of row 4, without deletion flag | SKA1 of the same charts created (ERDAT) ÷ months | Company-code level (SKB1) in the details. |
| 6 | No. of Customers | Customers (KNA1) without central deletion flag (LOEVM) | KNA1 created (ERDAT) ÷ months | No restriction by account group. |
| 7 | Active Customers | Distinct customers with a sales order created in the period (VBAK, VBTYP = C, ERDAT; sold-to party) **or** a customer line item entered in the period (BSID ∪ BSAD, CPUDT) | N/A | Union is built in ABAP. |
| 8 | No. of Vendors | Vendors (LFA1) without central deletion flag (LOEVM) | LFA1 created (ERDAT) ÷ months | No restriction by account group. |
| 9 | Active Vendors | Distinct vendors with a purchase order created in the period (EKKO, BSTYP = F, AEDAT) **or** a vendor line item entered in the period (BSIK ∪ BSAK, CPUDT) | N/A | Same logic as active customers. |
| 10 | No. of Products (SKUs) | Materials (MARA) without client-level deletion flag (LVORM) | MARA created (ERSDA) ÷ months | Distribution per material type and materials with goods movements in the details. |
| 11 | No. of Departments/Cost Centers | Cost centers (CSKS) with a validity record valid today (DATAB ≤ today ≤ DATBI) | Cost centers whose **first** creation date (earliest ERSDA over all validity records) lies in the period ÷ months | New validity records of existing cost centers are not counted as additions. Profit centers in the details. |
| 12 | No. of Assets | Main asset numbers (ANLA, sub-number 0000) that are not deactivated (DEAKT initial) | Main asset numbers created (ERDAT) ÷ months | Sub-numbers in the details. |
| 13 | No. of Customer Orders | **Open** sales orders: sales document status (VBUK) with VBTYP = C and overall status GBSTK ≠ C (not completely processed) | Sales orders (VBAK, VBTYP = C) created (ERDAT) ÷ months | Other sales document categories (inquiries, quotations, contracts, scheduling agreements, returns, free-of-charge orders) in the details. |
| 14 | No. of Customer Payments Received | N/A (flow figure without stock) | Distinct FI documents (BUKRS, BELNR, GJAHR) entered in the period (BSID ∪ BSAD, CPUDT) with a line item whose posting key is defined as customer / credit / payment transaction (TBSL attributes) ÷ months | Documents, not line items. No posting key value is hard-coded. |
| 15 | No. of Purchase Orders | **Open** purchase orders: distinct EBELN in EKPO with BSTYP = F, without delivery-completed indicator (ELIKZ) and without deletion indicator (LOEKZ) | Purchase orders (EKKO, BSTYP = F) created (AEDAT) ÷ months | Contracts, scheduling agreements and RFQs are excluded by BSTYP. Other categories in the details. |
| 16 | No. of P-Card Transactions | N/A | N/A | Not derivable generically. |
| 17 | Banking | – | – | Header row, left empty. |
| 18 | – No. of Banks used | Distinct banks (bank country + bank key) of the house banks (T012) of the active company codes | N/A | House banks have no creation date. House bank and account counts in the details. |
| 19 | – Checks Sent | N/A | Checks in the check register (PAYR) with payment date (ZALDT) in the period and not voided (VOIDR initial; VOIDR is NUMC 2, initial = '00') ÷ months | Covers checks from payment runs and manual checks. |
| 20 | – EFT | N/A | Payments of productive payment runs (REGUH: run date LAUFD in the period, not a proposal run (XVORL initial), payment document created (VBLNR filled), not an HR payroll run (6th character of LAUFI ≠ 'P', SAP convention)) whose payment method used (REGUH-RZAWE; REGUH has no ZLSCH) is an **outgoing bank transfer** in the payment method definition (T042Z, country of the paying company code): XEINZ initial and none of the check / bill of exchange classification indicators XSCHK, XWECH, XWANF, XWECS, XSWEC set ÷ months | T042Z has no own "bank transfer" field; the FBZP classification is stored as these indicators. Payment with printout (F-58, run ID ending in '*') is included; incoming methods (direct debit), HR payroll runs and manual payments without payment medium are not. All payment methods in the details. |
| 21 | – Checks Received | N/A | N/A | Not derivable generically. |
| 22 | – No. of Lock Boxes | N/A | N/A | Not derivable generically. |
| 23 | EDI Transactions | Configured EDI message flows with business partners: partner profile message lines outbound (EDP13) and inbound (EDP21) for all partner types except logical systems (LS) | IDocs created (EDIDC, CREDAT) in the period whose partner is not a logical system ÷ months. Partner = receiver for outbound, sender for inbound | ALE IDocs (logical systems), direction split and top message types in the details. |
| 24 | No. of Production Orders | **Open** production and process orders: orders (AUFK) with order category 10 or 40 that have none of the system statuses DLV, TECO, CLSD, DLFL | Production and process orders created (ERDAT) ÷ months | Split by order category in the details. |
| 25 | No. of Maintenance Orders | N/A | Orders with order category 30 created (ERDAT) ÷ months | Order category 30 includes service orders. Open maintenance orders in the details. |
| 26 | No of Warehouses | WM warehouse numbers assigned to a plant / storage location (distinct LGNUM in T320) | N/A | Systems without WM: 0. Storage locations in the details. |
| 27 | No of Plants/Manufacturing facilities* | Plants (T001W) whose valuation area belongs to an active company code (T001K). Shown as "n (p prod)", e.g. "227 (12 prod)", with p = counted plants marked "manufacturing" in the plant view; only the number if block PP was skipped or its order pass failed (text M17) | N/A | Plants have no creation date. Manufacturing plants (orders in period) in the plant view. |
| 28 | No. of SAP Users | Dialog users (USTYP = A), valid today (GLTGV / GLTGB), not locked by an administrator (lock value 0, or only the failed-logon lock 128), last logon (TRDAT) on or after the period start | Dialog users created (ERDAT) ÷ months | Not a license measurement. All valid users per user type in the details. |
| 29 | No. of Employees | N/A | N/A | HR data is not read (personal data, separate authorizations). |

N/A cells by design: B14, B16, C16, B19, B20, B21, C21, B22, C22, B25, B29, C29, plus C3, C4, C7, C9, C18, C26, C27.

---

## 8. Details (view 4)

### 8.1 INFO

System ID, client, SAP release, database system, logon language of the run, analysis period, months, run start and end, runtime per block, user, blocks collected or skipped, stored-result timestamp, and one line per failed collection step with its exception text (also for steps without a questionnaire row, e.g. the organizational unit lists or G5–G7).

### 8.2 Supporting figures

| Group | Figure | Definition |
|---|---|---|
| Company codes | All company codes | T001 count; one sub row per company code with value 1 = active, 0 = not active (name from T001 at display time) |
| G/L | G/L accounts at company-code level | SKB1 of active company codes without deletion flag and posting block |
| Materials | Materials per material type | MARA without deletion flag, grouped by MTART, text T134T |
| Materials | Materials with goods movements in the period | Material documents entered in the period (MKPF, CPUDT) → distinct materials of their items (MSEG via document key, FOR ALL ENTRIES per MKPF package). Distinct count over the whole period, shown as value without average |
| Controlling | Profit centers | CEPC records valid today |
| Assets | Asset sub-numbers | ANLA with sub-number ≠ 0000, not deactivated |
| Sales | Sales documents per category | VBAK created in the period, grouped by VBTYP (A inquiry, B quotation, C order, E scheduling agreement, G contract, H returns, I free-of-charge order) |
| Sales | Deliveries per category | LIKP created in the period, grouped by VBTYP (J outbound delivery, T returns delivery, 7 inbound delivery) |
| Sales | Billing documents per category | VBRK created in the period, grouped by VBTYP; cancelled documents (FKSTO) separately (sub key "<VBTYP> X") |
| Purchasing | Purchasing documents per category | EKKO created in the period, grouped by BSTYP (A RFQ, F purchase order, K contract, L scheduling agreement) |
| Purchasing | Vendor invoices (logistics invoice verification) | RBKP entered in the period (CPUDT), posted status only |
| Purchasing | Open purchase orders by age (D30) | POs of row 15 by creation date EKKO-AEDAT before today: < 1, 1–2, 2–5, > 5 years (same day 1, 2, 5 years ago); header = POs of row 15 |
| Purchasing | Open purchase orders by company code (D31) | POs of row 15 per EKKO-BUKRS, text T001 |
| Purchasing | Open PO items by closing pattern (D32) | Open items of row 15 (EKPO, BSTYP F, no ELIKZ, no LOEKZ): 1 no goods receipt expected (WEPOS empty; ELIKZ is never set automatically), 2 final invoice posted (EREKZ) but not delivery-completed, 3 goods receipt expected and not delivery-completed |
| Purchasing | Open PO items by item category (D33) | Open items of row 15 per EKPO-PSTYP, text T163Y |
| Purchasing | Open POs without activity since period start (D34) | POs of row 15 created before the period start without any PO history posting (EKBE, BUDAT) on or after the period start. EKBE is read per block of 5,000 POs (FOR ALL ENTRIES, key prefix EBELN); separate step MM_POHIST so its runtime and failures stay separate |
| Inventory | Material documents | MKPF entered in the period |
| Production | Production orders / process orders | Created in the period and open, separately for order category 10 and 40 (sub rows: value = open, total = created) |
| Maintenance | Open maintenance orders | Order category 30, open by the status rule of row 24 |
| Quality | Inspection lots created | QALS created in the period |
| Warehouse | Transfer orders created | LTAK with creation date (BDATU) in the period |
| Warehouse | Storage locations | T001L of the plants counted in row 27 |
| Production | Work centers | CRHD, object type work center, of the plants counted in row 27 |
| Banking | House banks / house bank accounts | T012 / T012K rows of active company codes |
| Banking | Payments per payment method | REGUH (as row 20, without classification and direction filter) grouped by paying company code country + payment method, text T042Z |
| EDI | IDocs per direction and partner type | EDIDC created in the period, grouped by DIRECT and partner type |
| EDI | ALE IDocs | As above, partner type logical system |
| EDI | Top 10 message types | EDIDC created in the period, grouped by MESTYP |
| Users | Users per user type | USR02 valid today, grouped by USTYP (A dialog, B system, C communication, L reference, S service) |
| Users | Valid dialog users regardless of logon | USTYP = A, valid today, not locked by an administrator |
| Financials | FI documents entered | BKPF entered in the period (CPUDT), one sub row per document status (BSTAT; "-" = normal document), text from the domain fixed values |
| G/L | Country charts of accounts | Distinct country charts (T001-KTOP2) of the active company codes; one sub row per chart: SKA1 without deletion flag (value), SKA1 created (ERDAT) in the period (total), text T004T |
| G/L | Group charts of accounts | Distinct group charts (T004-KKTPL) of the operational charts of row 4; sub rows as for country charts |

---

## 9. Organization (view 3)

| Item | Definition |
|---|---|
| G5 Countries | Distinct country keys of the active company codes (T001-LAND1) and of the plants counted in row 27 (T001W-LAND1) |
| G6 Languages | Distinct correspondence languages (SPRAS → ISO code via T002) of the active customers and active vendors (rows 7 and 9). This is an approximation of the languages business is transacted in. |
| G7 Currencies | Distinct local currencies of the active company codes (T001-WAERS) plus document currencies of the sales orders (VBAK-WAERK) and purchase orders (EKKO-WAERS) created in the period |
| Purchasing organizations | T024E (EKORG, EKOTX, BUKRS). Used = purchase orders created in the period. |
| Sales organizations | TVKO + text (VKORG, BUKRS). Used = sales orders created in the period. |
| Distribution channels | TVTW + text. Used = sales orders created in the period. |
| Divisions | TSPA + text. Used = sales orders created in the period. |
| Application usage | Documents created in the period per area: FI documents, sales orders, deliveries, billing documents, purchase orders, material documents, vendor invoices, production/process orders, maintenance/service orders, inspection lots, transfer orders, IDocs. Supports the "Not Applicable" column of the business function table. |

---

## 10. Plants (view 2)

Source T001W (WERKS, NAME1, LAND1, ORT01, BWKEY). Company code via T001K (BWKEY → BUKRS). "Manufacturing" is set when at least one order with order category 10 or 40 was created for the plant in the period. The plant name is output as "WERKS - NAME1" in one column.

Approx revenue is not derived. A revenue figure would need an agreed revenue definition and a currency conversion, and both would differ between instances.

The plant list and row 27 come from block ORG; "Manufacturing" comes from the order pass of block PP and stays blank if PP was skipped.

---

## 11. Interfaces (view 5, optional)

Candidate list for the "Applications" sheet (column System, Instances). Technical facts only, no classification.

| Object type | Source | Content |
|---|---|---|
| RFC destinations | RFCDES | Destination name and connection type (RFCTYPE, with the text of its domain fixed value in the display language) only. Connection options (host, user) and the destination description are not read. |
| Logical systems | TBDLS / TBDLST | Logical system and text in the logon language of the run |
| Partner profiles | EDPP1, EDIDC | Partner number, partner type, IDocs created in the period per partner (EDIDC-CREDAT, one aggregated pass; partner = receiver for outbound, sender for inbound IDocs, as in row 23). Logical systems (type LS) get the TBDLST text. Partners with IDocs in the period but without a partner profile are listed too, marked "(no partner profile)". |
| Software components | CVERS / CVERS_REF | Component, release, support package level (EXTRELEASE, as in System > Status), text in the logon language of the run, else English |

Default off. Some organizations treat RFC destination lists as security-relevant.

RFC destinations, logical systems and software components are system-wide (client-independent tables); partner profiles and IDocs belong to the client of the run. CVERS can differ from System > Status for HR sub-components after an upgrade (SAP KBA 2464887).

Steps: INTF_RFC, INTF_LOGSYS, INTF_PARTNER, INTF_CVERS, one per object type. Each collects into a local table and appends it at the end, so a failure leaves no partial list. Failures are also listed under INFO in view 4.

---

## 12. Texts and languages

### 12.1 Rules

- All user-visible texts are text elements of the program: selection texts, text symbols, program title. No literals in the source code. Technical keys (text IDs, field names, SAP-defined values) are not texts.
- The text pool is maintained **completely in German and English**.
- **English item texts = questionnaire wording.** The official run is executed with logon language EN, so that the output wording matches the questionnaire.
- "N/A" is a text symbol with the same value "N/A" in both languages, because it is pasted into the English questionnaire.
- Messages are built from text symbols. Dynamic parts (dates, keys, exception texts) are concatenated in the code.
- Length limits used in this design: selection texts ≤ 30 characters (screen label width), column headings ≤ 20 characters, view titles ≤ 70 characters (SALV list header), definition texts ≤ about 120 characters (one text symbol each).

### 12.2 Text ID scheme

Text symbol IDs have 3 characters (letters, digits, "_"). Letters are used as the group prefix.

| Prefix | Use | Count |
|---|---|---|
| Qnn | Questionnaire item text, nn = row 03–29 | 27 |
| Nnn | Short basis note (column D), nn = row | 26 |
| Lnn | Full definition, nn = row | 26 |
| Rnn | Remark, nn = row (only where needed) | ≈ 20 |
| Dnn / Enn | Detail item text / detail definition (D01–D79); D80–D90 are the INFO labels | ≈ 30 / 30, 11 |
| Gnn | Detail group (view 4); G00 = INFO | ≈ 15 |
| Onn | Organization view groups (O01–O08) and application usage areas (O11–O22) | 20 |
| Inn | Interfaces view object types | 4 |
| Hnn | Column headings | ≈ 30 |
| Tnn | Selection screen block titles | 4 |
| Vnn | View titles | 5 |
| Mnn | Messages | ≈ 13 |
| Snn | Status values (N/A, not collected, error) | 3 |

### 12.3 Text access and language fallback

- When a program starts, the text pool of the logon language is loaded. If it does not exist, the secondary language of the system is used. If that does not exist either, all texts stay empty. A missing text symbol is empty (initial), not an error.
- The other instances have users with logon languages other than DE/EN (e.g. ES, PT, HE). Their secondary language is not necessarily EN.
- Therefore, the report reads its own text pool explicitly (READ TEXTPOOL) in the logon language and fills missing entries from the **English** text pool. All output texts and messages are taken from this lookup by their text ID.
- At start, the report checks its expected text IDs and writes a message listing missing IDs (in background into the job log). This replaces the extended program check, which cannot detect dynamically addressed text symbols.
- Selection texts are not part of this fallback. They follow the system's standard rule. With an unsupported logon language, the parameter names appear on the selection screen.
- Organizational unit texts (sales organization etc.) are read in the logon language of the collection run.

---

## 13. Technical rules

### 13.1 Syntax level

The report must compile unchanged on every instance. Therefore it uses only classic syntax:

| Avoided | Available from | Used instead |
|---|---|---|
| Host variables with @, comma-separated SELECT lists, INTO after WHERE, inline DATA in SELECT | 7.40 SP05 / SP08 | Classic Open SQL (no @, blank-separated field lists, INTO after the field list) |
| UNION in SELECT | 7.50 | Merge of sorted internal tables |
| DATA( ), NEW, VALUE, CONV, COND, SWITCH, table expressions itab[ ], LINE_EXISTS | 7.40 SP02 | Explicit declarations, READ TABLE, MOVE |
| FOR, LET, CORRESPONDING operator, REDUCE, FILTER | 7.40 SP05 / SP08 | Loops |
| Method calls in operand positions of WRITE / MESSAGE | 7.40 SP02 | Result into a variable first |
| String templates, &&, string functions, method chaining, expressions as actual parameters | 7.02 | CONCATENATE, intermediate variables |

- Within one SQL statement, old and new syntax cannot be mixed. The program therefore uses classic syntax throughout. This deliberately deviates from the strict 7.50 Open SQL style.
- Lines up to 255 characters are allowed. There is no 72-character limit.
- Typed method parameters need an exact type match. Text symbols are copied into a typed variable before they are passed to SALV methods.
- Constants such as 'X' are used instead of type-pool constants. This keeps the program independent of TYPE-POOLS behaviour on older releases.

### 13.2 Open SQL rules

- Static SQL for all core tables. A table or field missing on an instance would be a syntax error at activation. This is detected at import into the instance's development system (see 14), before any productive run.
- No joins, no UNION, no subqueries across application tables.
- GROUP BY / COUNT only on application tables. Customizing and text tables are read completely and aggregated in ABAP, so that the table class of these tables does not matter.
- No access to the FI line-item table. The FI secondary index tables BSID, BSAD, BSIK and BSAK are used.
- FOR ALL ENTRIES: driver table never empty, driver split into packages (e.g. 5,000 keys), duplicates removed beforehand.

### 13.3 Error handling

- Each step (one pass over a table, see 5): TRY … CATCH CX_ROOT. This covers CX_SY_OPEN_SQL_DB, the dynamic SQL exceptions of the optional block, and arithmetic and conversion errors. All figures fed by the failed step show status "error", the exception text goes to the remark. A figure fed by several steps (e.g. row 13: B from VBUK, C from VBAK) keeps "error" even if another of its steps succeeds. In background, message M08 with the figure keys goes to the job log.
- Runtime limits and memory errors cannot be caught. Hence background processing for the official run (dialog work processes end at the profile runtime limit) and PACKAGE SIZE for large scans.

### 13.4 SALV

- CL_SALV_TABLE=>FACTORY without container → fullscreen grid. No own GUI status or screen is needed.
- GET_FUNCTIONS( )->SET_ALL( ). Otherwise the toolbar is empty, including the spreadsheet export.
- Column headings via CL_SALV_COLUMN SET_LONG_TEXT / SET_MEDIUM_TEXT / SET_SHORT_TEXT (short heading = first characters of the medium heading).
- View title via GET_DISPLAY_SETTINGS( )->SET_LIST_HEADER (max. 70 characters).
- Value columns are character fields, so that "N/A" and numbers share one column. Excel converts the pasted digits into numbers.

### 13.5 Result storage

- After collection the result is stored as a data cluster in the standard cluster table INDX (EXPORT … TO DATABASE). Fixed 2-character area and short fixed ID (≤ 12 characters), current client, followed by COMMIT WORK (the export holds a database lock until the commit).
- Each run overwrites the previous result. Mode "Delete stored result" removes it.
- The cluster carries a format version (constant in the program, increased whenever a stored structure changes). IMPORT checks the version first and is wrapped in TRY … CATCH CX_SY_IMPORT_MISMATCH_ERROR (superclass, also covers CX_SY_IMPORT_FORMAT_ERROR; naming both in one TRY is a syntax error). A version mismatch or a caught exception shows message M13 instead of a dump; the user then runs a new collection or deletes the stored result.
- Stored content: run metadata (incl. G5–G7 and their status), figure table (key, B, C, total, status, exception text), list tables (plants, organizational units with status, details, interfaces), failed steps. No texts except master-data names. Format version 0003 since the interfaces block (release, SP level and "no partner profile" flag added to the interface list; 0002: status fields and failed steps).
- INDX is a shared standard table that is meant for short-lived data only. Here it holds one small cluster per client for a few days. An own INDX-like table would avoid the shared table, but it would require a Dictionary object on every instance.

### 13.6 Background list

- One list with all views one after another, each with its view title and column headings from the text pool. LINE-SIZE 255 (spool-compatible).
- Messages of type S/I/W go to the job log and the run continues.

### 13.7 Authorization and client

- The program gets an authorization group in its attributes (checked against S_PROGRAM), so that only IT/Basis can execute it.
- No business-object authorization checks, because only counts are output (no amounts, no personal data).
- The report counts the logon client only. Instances with several productive clients run it once per client.

### 13.8 Performance

- Expected full or long range scans: BSID/BSAD/BSIK/BSAK (CPUDT), VBAK (ERDAT), EKKO (AEDAT), EKPO (open items), MKPF (CPUDT), RBKP (CPUDT), VBRK and LIKP (ERDAT), EDIDC (CREDAT), AUFK (ERDAT) plus status check, LTAK. No standard index supports these creation dates.
- Customer-specific secondary indexes differ per instance, so runtimes differ as well. The runtime is measured at BKG first and passed on with the rollout.
- Runtime per block is recorded in the INFO section.

---

## 14. Delivery and operation

### 14.1 Build (BKG)

1. Create the program in the BKG development system: executable program, local classes, authorization group, Unicode checks active. Package ZICL_BCS4, abapGit offline repository (original language EN, translation DE).
2. Text pool: `textpool.tsv` is the single source for all texts (EN and DE, appendices A to C plus the condensed Lnn/Rnn definitions). `make_abapgit_zip.py` (Claude Code: `/abapgit`) checks it against the source (every text ID and parameter used must exist, lengths, one DE translation per EN text, REPORT name), regenerates the program files under `src/` (TPOOL in `prog.xml`, DE as LXE `.po`) and writes `C:\claudeCode\Systemreport-abapgit.zip` with `.abapgit.xml` and `src/` only. Import it in the offline repository ZICL_BCS4_offline with "Import zip", then pull. The program files under `src/` are generated; change `zbc_s4_dataselection.abap` and `textpool.tsv` instead.
3. Test in the quality system with representative data volume. Measure the runtime per block. Check the plausibility (section 15).

### 14.2 Rollout to the other instances

- **Alternative route without transport:** import the abapGit ZIP (14.1) in an offline repository of the instance. Program and text pool in EN and DE arrive together.
- **Primary route:** transport of copies with the program (incl. text pool). Each landscape's Basis imports it as an external transport into its development system first. A successful import (activation) proves that all tables and fields exist on that release. Then import into production.
- After the import: check that both languages are present (text elements in DE and EN logon).
- **Fallback without transport:** create the program manually, paste the source, and maintain the text pool from appendices A and B in both languages.

### 14.3 Run and paste

1. Schedule a background job in the productive client: mode "Collect data", period empty (= default), store result, logon language EN.
2. After the job: start the report in dialog, mode "Display stored result", select the view.
3. View 1: select B3 … C29 (or … D29) in the ALV, copy, paste into the questionnaire at B3.
4. View 2: copy the five columns F–J of the counted plants, paste at the first plant row.
5. View 3: copy the value of G5 / G6 / G7 into the merged cell. If a list continues in further rows, paste the rows one after another into the cell in edit mode (F2), so that Excel keeps the text in one cell. Compare with the number of entries in the key column.
6. Submit view 4 (definitions) together with the questionnaire.
7. Optionally delete the stored result.

---

## 15. Plausibility and reproducibility

- Each figure can be reproduced with a table count (SE16N) using exactly the selection of its definition. This makes the result rebuildable on every instance.
- Spot checks against standard transactions during the BKG test: open sales orders (VA05), purchase orders (ME2N), IDocs (WE02/WE05), users (SUIM), customer/vendor line items (FBL5N/FBL1N), check register (FCHN).

---

## 16. Trade-offs and findings

| # | Topic | Decision | Trade-off |
|---|---|---|---|
| 1 | Texts in the text pool vs. single-file deployment | Text pool (DE/EN), delivered by transport | No longer one copy-and-paste file. The fallback needs manual text maintenance per instance. |
| 2 | Logon languages other than DE/EN | Own lookup with English fallback, official run in EN | Selection texts are not covered by the fallback. |
| 3 | Classic syntax | Compiles on all releases in scope | More verbose code. Deviates from the modern 7.50 style. |
| 4 | Static SQL | Errors surface at import, not at runtime | A missing field blocks the whole program on that release, instead of a single figure. |
| 5 | Result storage in INDX | Enables background run plus dialog copy and paste | Shared standard table meant for short-lived data. This is the only write operation. |
| 6 | Creation / entry dates throughout | Same time logic for all figures and instances | Differs from business date views (document date, posting date). |
| 7 | Documents instead of line items | Payment counts are documents | Requires distinct processing in ABAP. |
| 8 | Classification via SAP attributes | No posting keys or payment methods hard-coded | Correctness depends on the attribute maintenance in each instance's customizing. |
| 9 | Whole numbers | Paste works regardless of locale | Averages below 0.5 show as 0. The total column compensates. |
| 10 | Active company codes as the base | Sample and unused organizational units are excluded | Dormant company codes (no postings for 12 months) are excluded. They are visible in the details. |
| 11 | Open orders by system status | Language-independent, works for PP, PP-PI and PM | Orders with status DLV but no TECO count as done. |
| 12 | EDI vs. ALE by partner type | Business-partner EDI separated from system-to-system IDocs | Partner types other than LS that are used for ALE would count as EDI. |
| 13 | Active users = logon in period | Reflects actual usage | Not comparable with license counts. |
| 14 | HR not read | No personal data, no HR authorizations needed | Row 29 stays manual. |
| 15 | No joins, no UNION | Release-independent, table class irrelevant | More code, more memory for distinct sets. |
| 16 | Questionnaire cells that cannot be derived (C16, C21, B22, C18, C27, row 29) | "N/A" with remark | Cells the questionnaire would like filled stay N/A. |

---

## 17. Open points before build

### 17.1 Dictionary checks (BKG and lowest release in scope)

| Table | Fields / values to confirm |
|---|---|
| T001, T001K, T001W | BUKRS, BUTXT, LAND1, WAERS, KTOPL; BWKEY → BUKRS; WERKS, NAME1, LAND1, ORT01, BWKEY |
| SKA1, SKB1 | KTOPL, SAKNR, deletion flag, ERDAT; XLOEB, XSPEB |
| KNA1, LFA1 | LOEVM, ERDAT, SPRAS |
| BSIK, BSAK | LIFNR, CPUDT |
| CSKS, CEPC | DATAB, DATBI, ERSDA |
| ANLA | ANLN2 = 0000 for main numbers, DEAKT, ERDAT |
| VBUK | GBSTK value "C" = completely processed – resolved: VBUK has VBTYP (SD document category); LIKP-VBTYP, VBRK-VBTYP/FKSTO exist |
| EKPO | ELIKZ / LOEKZ values for "open" – resolved: EKPO has BSTYP, ELIKZ, LOEKZ (both initial = open); RBKP-RBSTAT 5 = posted; LTAK-BDATU = creation date; EKKO-AEDAT = created on |
| AUFK, JEST | AUTYP values 10 / 30 / 40, ERDAT, OBJNR, WERKS; JEST STAT, INACT; system status IDs for DLV, TECO, CLSD, DLFL – resolved: DLV = I0012, TECO = I0045, CLSD = I0046, DLFL = I0076 (SAP-delivered, TJ02); status active = INACT initial |
| TBSL | Fields for account type, debit/credit and payment-transaction flag |
| T042Z | ~~Field for the classification "bank transfer"~~ – resolved: no own field; classification = indicators XSCHK, XWECH, XWANF, XWECS, XSWEC (all initial = bank transfer), direction XEINZ (see row 20) |
| PAYR | ZALDT, VOIDR – resolved: VOIDR is NUMC 2, compared with a typed initial value |
| REGUH | LAUFD, proposal indicator, payment document number, payment method, paying company code – resolved: XVORL, VBLNR, ZBUKR; payment method used is RZAWE (no ZLSCH in REGUH); LAUFI 6th character 'P' = HR payroll DME pre-program |
| T012, T012K | BANKS, BANKL |
| EDP21, EDIDC | Inbound partner profile lines; RCVPRT / SNDPRT – resolved: EDP13 (RCVPRT), EDP21 (SNDPRT), EDIDC (DIRECT 1 = outbound / 2 = inbound, RCVPRT, SNDPRT, MESTYP, CREDAT); partner type LS = logical system |
| QALS, CRHD | Creation date of the inspection lot; object type of work centers – resolved: QALS-ENSTEHDAT (date of lot creation); CRHD-OBJTY 'A' = work center |
| TVKO/TVKOT, TVTW/TVTWT, TSPA/TSPAT, T002 | Keys, texts, ISO language field – resolved: text field VTEXT in TVKOT/TVTWT/TSPAT (key SPRAS + org key); T024E-EKOTX (no text table); T002-LAISO (2 characters, T002 client-independent) |
| RFCDES, TBDLS/TBDLST, EDPP1, CVERS/CVERS_REF | Resolved: RFCDES-RFCDEST (CHAR 32), RFCTYPE (data element RFCTYPE_D, domain RFCTYPE with fixed-value texts); TBDLST-LANGU/LOGSYS/STEXT (CHAR 40); EDPP1-PARNUM (CHAR 10, ALPHA, internal format as in EDIDC-RCVPRN/SNDPRN), PARTYP (CHAR 2); CVERS-COMPONENT/RELEASE/EXTRELEASE (support package level); CVERS_REF-COMPONENT/LANGU/DESC_TEXT (CHAR 80, key not documented – read into a standard table). RFCDES, TBDLS/TBDLST, CVERS and CVERS_REF are client-independent, EDPP1 and EDIDC client-dependent |
| INDX | Length of the ID field (≥ 12 characters) |
| SALV | Lengths of the short / medium / long column headings |
| Text elements | Maximum length of text symbols and selection texts |

### 17.2 Decisions

1. Result storage: standard INDX (as designed) or an own INDX-like table per instance.
2. Row 23, column B: partner profile lines as "current number" (as designed) or N/A.
3. ~~Optional interfaces block: build now or later~~ – decided: built (default off).
4. Lowest SAP_BASIS release of all ICL ECC instances, and availability of CL_SALV_TABLE there.
5. Transport route per landscape (external transport import by local Basis).
6. Authorization group for the program.
7. ~~Final program name~~ – decided: ZBC_S4_DATASELECTION (working name was ZS4_RC_QUESTIONNAIRE).

---

## Appendix A – Text pool: screen, headings, views, messages, status

### A.1 Selection texts (≤ 30 characters)

| Name | EN | DE |
|---|---|---|
| P_COLL | Collect data | Daten ermitteln |
| P_SHOW | Display stored result | Ergebnis anzeigen |
| P_DEL | Delete stored result | Ergebnis löschen |
| P_DATFR | Period from (1st of month) | Zeitraum von (Monatserster) |
| P_DATTO | Period to (end of month) | Zeitraum bis (Monatsletzter) |
| P_MD | Master data | Stammdaten |
| P_FI | Financials | Finanzwesen |
| P_SD | Sales and distribution | Vertrieb |
| P_MM | Purchasing and inventory | Einkauf und Bestandsführung |
| P_PP | Production and maintenance | Produktion und Instandhaltung |
| P_ORG | Organization and technical | Organisation und Technik |
| P_INTF | Interfaces (optional) | Schnittstellen (optional) |
| P_STORE | Store result | Ergebnis speichern |
| P_V1 | View: Questionnaire | Sicht: Fragebogen |
| P_V2 | View: Plants | Sicht: Werke |
| P_V3 | View: Organization | Sicht: Organisation |
| P_V4 | View: Details | Sicht: Details |
| P_V5 | View: Interfaces | Sicht: Schnittstellen |

### A.2 Block titles

| ID | EN | DE |
|---|---|---|
| T01 | Mode | Modus |
| T02 | Analysis period | Analysezeitraum |
| T03 | Scope | Umfang |
| T04 | Output | Ausgabe |

### A.3 View titles (≤ 70 characters)

| ID | EN | DE |
|---|---|---|
| V01 | Data & Org Questionnaire - rows 3 to 29 (paste B:C) | Fragebogen - Zeilen 3 bis 29 (Einfügen B:C) |
| V02 | Plant table (paste F:J) | Werkstabelle (Einfügen F:J) |
| V03 | Organization - G5 to G7 and organizational units | Organisation - G5 bis G7 und Organisationseinheiten |
| V04 | Supporting figures and definitions | Ergänzende Kennzahlen und Definitionen |
| V05 | Interfaces and technical connections | Schnittstellen und technische Verbindungen |

### A.4 Column headings (≤ 20 characters)

| ID | EN | DE |
|---|---|---|
| H01 | Row | Zeile |
| H02 | Item | Position |
| H03 | Current number | Aktueller Bestand |
| H04 | Avg added/month | Ø neu pro Monat |
| H05 | Basis | Basis |
| H06 | Total in period | Summe im Zeitraum |
| H07 | Definition | Definition |
| H08 | Remark | Bemerkung |
| H10 | Name of the Plant | Werk |
| H11 | Location | Standort |
| H12 | Approx Revenue | Umsatz (ca.) |
| H13 | On SAP | Im SAP |
| H14 | On Legacy System | Im Altsystem |
| H15 | City | Ort |
| H16 | Company code | Buchungskreis |
| H17 | Counted in row 27 | Gezählt in Zeile 27 |
| H18 | Manufacturing | Fertigung |
| H20 | Group | Gruppe |
| H21 | Key | Schlüssel |
| H22 | Description | Bezeichnung |
| H23 | Value | Wert |
| H24 | Used in period | Im Zeitraum genutzt |
| H30 | Object type | Objekttyp |
| H31 | Name | Name |
| H32 | Type | Typ |
| H33 | IDocs in period | IDocs im Zeitraum |
| H34 | Release | Release |
| H35 | SP level | SP-Stand |

### A.5 Messages

| ID | EN | DE |
|---|---|---|
| M01 | Period start must be the first day of a month | Zeitraumbeginn muss ein Monatserster sein |
| M02 | Period end must be the last day of a month | Zeitraumende muss ein Monatsletzter sein |
| M03 | Period must end before the current month | Zeitraum muss vor dem laufenden Monat enden |
| M04 | Period end lies before period start | Zeitraumende liegt vor Zeitraumbeginn |
| M05 | No stored result found | Kein gespeichertes Ergebnis vorhanden |
| M06 | Result stored | Ergebnis gespeichert |
| M07 | Stored result deleted | Gespeichertes Ergebnis gelöscht |
| M08 | Figure could not be determined: | Kennzahl nicht ermittelbar: |
| M09 | Stored result from | Gespeichertes Ergebnis vom |
| M10 | Data collection finished | Datenermittlung beendet |
| M11 | Text IDs missing in logon language: | Text-IDs fehlen in Anmeldesprache: |
| M12 | Runtime of block (seconds): | Laufzeit Block (Sekunden): |
| M13 | Stored result is from an older program version - please collect again | Gespeichertes Ergebnis stammt aus älterer Programmversion - bitte neu ermitteln |

### A.6 Status values

| ID | EN | DE |
|---|---|---|
| S01 | N/A | N/A |
| S02 | not collected | nicht ermittelt |
| S03 | error | Fehler |

---

## Appendix B – Text pool: questionnaire items and basis notes

EN item texts follow the questionnaire wording (multiple blanks normalized). Basis notes ≤ 40 characters.

| Row | Qnn EN | Qnn DE | Nnn EN | Nnn DE |
|---|---|---|---|---|
| 03 | No of Company Codes | Anzahl Buchungskreise | Active: FI documents in period | Aktiv: FI-Belege im Zeitraum |
| 04 | No. of Chart of Accounts | Anzahl Kontenpläne | Of active company codes | Der aktiven Buchungskreise |
| 05 | No. of G/L Accounts | Anzahl Sachkonten | Chart level, no deletion flag | Kontenplanebene, ohne Löschvormerkung |
| 06 | No. of Customers | Anzahl Kunden | No deletion flag; C = created/month | Ohne Löschvormerkung; C = neu/Monat |
| 07 | Active Customers | Aktive Kunden | Order or FI line item in period | Auftrag oder FI-Posten im Zeitraum |
| 08 | No. of Vendors | Anzahl Lieferanten | No deletion flag; C = created/month | Ohne Löschvormerkung; C = neu/Monat |
| 09 | Active Vendors | Aktive Lieferanten | PO or FI line item in period | Bestellung oder FI-Posten im Zeitraum |
| 10 | No. of Products (SKUs) | Anzahl Materialien (SKUs) | No deletion flag; C = created/month | Ohne Löschvormerkung; C = neu/Monat |
| 11 | No. of Departments/Cost Centers | Anzahl Abteilungen/Kostenstellen | Valid today; C = first created/month | Heute gültig; C = erstmals neu/Monat |
| 12 | No. of Assets | Anzahl Anlagen | Main numbers, not deactivated | Hauptnummern, nicht deaktiviert |
| 13 | No. of Customer Orders | Anzahl Kundenaufträge | B = open now; C = created/month | B = offen; C = angelegt/Monat |
| 14 | No. of Customer Payments Received | Anzahl Zahlungseingänge Kunden | Payment documents created/month | Zahlungsbelege angelegt/Monat |
| 15 | No. of Purchase Orders | Anzahl Bestellungen | B = open now; C = created/month | B = offen; C = angelegt/Monat |
| 16 | No. of P-Card Transactions | Anzahl P-Card-Transaktionen | Not derivable | Nicht ermittelbar |
| 17 | Banking | Bankverkehr | – | – |
| 18 | - No. of Banks used | - Anzahl genutzter Banken | Distinct banks of house banks | Banken der Hausbanken (eindeutig) |
| 19 | - Checks Sent | - Versendete Schecks | Check register, not voided | Scheckregister, nicht entwertet |
| 20 | - EFT | - Elektronische Zahlungen (EFT) | Payment runs, bank transfer methods | Zahllauf, Zahlwege Überweisung |
| 21 | - Checks Received | - Erhaltene Schecks | Not derivable | Nicht ermittelbar |
| 22 | - No. of Lock Boxes | - Anzahl Lockboxen | Not derivable | Nicht ermittelbar |
| 23 | EDI Transactions | EDI-Transaktionen | B = partner profiles; C = IDocs/month | B = Partnervereinb.; C = IDocs/Monat |
| 24 | No. of Production Orders | Anzahl Fertigungs-/Prozessaufträge | B = open now; C = created/month | B = offen; C = angelegt/Monat |
| 25 | No. of Maintenance Orders | Anzahl Instandhaltungsaufträge | Created/month incl. service orders | Angelegt/Monat inkl. Serviceaufträge |
| 26 | No of Warehouses | Anzahl Lagernummern | WM warehouse numbers assigned | Zugeordnete WM-Lagernummern |
| 27 | No of Plants/Manufacturing facilities* | Anzahl Werke/Produktionsstandorte* | Plants of active company codes | Werke aktiver Buchungskreise |
| 28 | No. of SAP Users | Anzahl SAP-Benutzer | Dialog users, logon in period | Dialogbenutzer, Anmeldung im Zeitraum |
| 29 | No. of Employees | Anzahl Mitarbeiter | Not read (personal data) | Nicht gelesen (Personaldaten) |

Lnn (full definitions) and Rnn (remarks) are taken from section 7 (EN, condensed to ≤ about 120 characters). EN and DE texts of Lnn and Rnn are maintained in `textpool.tsv` (see 14.1).

---

## Appendix C – Text pool: organization, details, INFO, interfaces

Further Dnn/Enn/Gnn entries are added with the detail figures of section 8.2.

### C.1 Organization view (Onn)

| ID | EN | DE |
|---|---|---|
| O01 | G5 Countries | G5 Länder |
| O02 | G6 Languages | G6 Sprachen |
| O03 | G7 Currencies | G7 Währungen |
| O04 | Purchasing organizations | Einkaufsorganisationen |
| O05 | Sales organizations | Verkaufsorganisationen |
| O06 | Distribution channels | Vertriebswege |
| O07 | Divisions | Sparten |
| O08 | Application usage | Anwendungsnutzung |
| O11 | FI documents | FI-Belege |
| O12 | Sales orders | Kundenaufträge |
| O13 | Deliveries | Lieferungen |
| O14 | Billing documents | Fakturen |
| O15 | Purchase orders | Bestellungen |
| O16 | Material documents | Materialbelege |
| O17 | Vendor invoices | Lieferantenrechnungen |
| O18 | Production/process orders | Fertigungs-/Prozessaufträge |
| O19 | Maintenance/service orders | Instandhaltungs-/Serviceaufträge |
| O20 | Inspection lots | Prüflose |
| O21 | Transfer orders | Transportaufträge |
| O22 | IDocs | IDocs |

### C.2 Detail groups and items (Gnn, Dnn, Enn)

| ID | EN | DE |
|---|---|---|
| G00 | INFO | INFO |
| G01 | Company codes | Buchungskreise |
| G02 | G/L accounts | Sachkonten |
| G03 | Materials | Materialien |
| G04 | Controlling | Controlling |
| G05 | Assets | Anlagen |
| D01 | All company codes | Alle Buchungskreise |
| E01 | T001 count; per company code: 1 = active, 0 = not active | Anzahl T001; je Buchungskreis: 1 = aktiv, 0 = nicht aktiv |
| D02 | G/L accounts at company-code level | Sachkonten auf Buchungskreisebene |
| E02 | SKB1 of the active company codes without deletion flag and posting block | SKB1 der aktiven Buchungskreise ohne Löschvormerkung und Buchungssperre |
| D03 | Materials per material type | Materialien je Materialart |
| E03 | MARA without deletion flag, grouped by material type (MTART) | MARA ohne Löschvormerkung, gruppiert nach Materialart (MTART) |
| D05 | Profit centers valid today | Heute gültige Profitcenter |
| E05 | CEPC records valid today (DATAB <= today <= DATBI) | Heute gültige CEPC-Sätze (DATAB <= heute <= DATBI) |
| D06 | Asset sub-numbers | Anlagenunternummern |
| E06 | ANLA with sub-number other than 0000, not deactivated | ANLA mit Unternummer ungleich 0000, nicht deaktiviert |
| G06 | Sales | Vertrieb |
| D07 | Sales documents per category | Verkaufsbelege je Belegtyp |
| E07 | VBAK created in the period (ERDAT), per SD document category (VBTYP) | VBAK im Zeitraum angelegt (ERDAT), je Vertriebsbelegtyp (VBTYP) |
| D08 | Deliveries per category | Lieferungen je Belegtyp |
| E08 | LIKP created in the period (ERDAT), per SD document category (VBTYP) | LIKP im Zeitraum angelegt (ERDAT), je Vertriebsbelegtyp (VBTYP) |
| D09 | Billing documents per category | Fakturen je Belegtyp |
| E09 | VBRK created in the period (ERDAT), per category (VBTYP); X after the category = cancelled (FKSTO) | VBRK im Zeitraum angelegt (ERDAT), je Belegtyp (VBTYP); X nach dem Belegtyp = storniert (FKSTO) |
| G07 | Purchasing | Einkauf |
| G08 | Inventory | Bestandsführung |
| G12 | Warehouse | Lagerverwaltung |
| D04 | Materials with goods movements in the period | Materialien mit Warenbewegungen im Zeitraum |
| E04 | Distinct materials (MSEG) of the material documents entered in the period (MKPF-CPUDT) | Eindeutige Materialien (MSEG) der im Zeitraum erfassten Materialbelege (MKPF-CPUDT) |
| D10 | Purchasing documents per category | Einkaufsbelege je Belegtyp |
| E10 | EKKO created in the period (AEDAT), per purchasing document category (BSTYP) | EKKO im Zeitraum angelegt (AEDAT), je Einkaufsbelegtyp (BSTYP) |
| D11 | Vendor invoices (logistics invoice verification) | Lieferantenrechnungen (Logistik-Rechnungsprüfung) |
| E11 | RBKP entered in the period (CPUDT), status posted (RBSTAT 5) | RBKP im Zeitraum erfasst (CPUDT), Status gebucht (RBSTAT 5) |
| D12 | Material documents | Materialbelege |
| E12 | MKPF entered in the period (CPUDT) | MKPF im Zeitraum erfasst (CPUDT) |
| D16 | Transfer orders created | Angelegte Transportaufträge |
| E16 | LTAK with creation date (BDATU) in the period | LTAK mit Anlagedatum (BDATU) im Zeitraum |
| G09 | Production | Produktion |
| G10 | Maintenance | Instandhaltung |
| G11 | Quality | Qualitätsmanagement |
| D13 | Production / process orders: open (value), created (total) | Fertigungs-/Prozessaufträge: offen (Wert), angelegt (Summe) |
| E13 | AUFK order category 10/40; open = no active status DLV, TECO, CLSD, DLFL (JEST); created = ERDAT in period | AUFK Auftragstyp 10/40; offen = kein aktiver Status LIEF, TABG, ABGS, LÖVM (JEST); angelegt = ERDAT im Zeitraum |
| D14 | Open maintenance orders | Offene Instandhaltungsaufträge |
| E14 | AUFK order category 30 without active status DLV, TECO, CLSD, DLFL (JEST) | AUFK Auftragstyp 30 ohne aktiven Status LIEF, TABG, ABGS, LÖVM (JEST) |
| D15 | Inspection lots created | Angelegte Prüflose |
| E15 | QALS with lot creation date (ENSTEHDAT) in the period | QALS mit Anlagedatum des Loses (ENSTEHDAT) im Zeitraum |
| D18 | Work centers | Arbeitsplätze |
| E18 | CRHD object type A (work center) of the plants counted in row 27 | CRHD Objekttyp A (Arbeitsplatz) der in Zeile 27 gezählten Werke |
| G14 | EDI | EDI |
| G15 | Users | Benutzer |
| D17 | Storage locations | Lagerorte |
| E17 | T001L of the plants counted in row 27 | T001L der in Zeile 27 gezählten Werke |
| D22 | IDocs per direction and partner type | IDocs je Richtung und Partnerart |
| E22 | EDIDC created in the period (CREDAT); sub key direction/partner type, 1 = outbound, 2 = inbound | EDIDC im Zeitraum angelegt (CREDAT); Unterschlüssel Richtung/Partnerart, 1 = ausgehend, 2 = eingehend |
| D23 | ALE IDocs (partner type LS) | ALE-IDocs (Partnerart LS) |
| E23 | EDIDC created in the period whose partner is a logical system | EDIDC im Zeitraum angelegt, deren Partner ein logisches System ist |
| D24 | Top 10 message types | Top 10 Nachrichtentypen |
| E24 | EDIDC created in the period per message type, the 10 largest; header = all IDocs | EDIDC im Zeitraum angelegt je Nachrichtentyp, die 10 größten; Kopf = alle IDocs |
| D25 | Users per user type (valid today) | Benutzer je Benutzertyp (heute gültig) |
| E25 | USR02 valid today (GLTGV/GLTGB), per user type (USTYP) | USR02 heute gültig (GLTGV/GLTGB), je Benutzertyp (USTYP) |
| D26 | Valid dialog users regardless of logon | Gültige Dialogbenutzer unabhängig von der Anmeldung |
| E26 | USTYP A, valid today, not locked by an administrator (UFLAG 0 or 128) | USTYP A, heute gültig, nicht vom Administrator gesperrt (UFLAG 0 oder 128) |
| G13 | Banking | Bankverkehr |
| G16 | Financials | Finanzwesen |
| D19 | House banks of the active company codes | Hausbanken der aktiven Buchungskreise |
| E19 | T012 rows of the active company codes | T012-Sätze der aktiven Buchungskreise |
| D20 | House bank accounts of the active company codes | Hausbankkonten der aktiven Buchungskreise |
| E20 | T012K rows of the active company codes | T012K-Sätze der aktiven Buchungskreise |
| D21 | Payments per payment method | Zahlungen je Zahlweg |
| E21 | REGUH as row 20 (RZAWE), all payment methods incl. incoming, per country/payment method | REGUH wie Zeile 20 (RZAWE), alle Zahlwege inkl. eingehender, je Land/Zahlweg |
| D27 | FI documents entered | Erfasste FI-Belege |
| E27 | BKPF entered in the period (CPUDT), per document status (BSTAT, - = normal) | BKPF im Zeitraum erfasst (CPUDT), je Belegstatus (BSTAT, - = normal) |
| D28 | Country charts of accounts | Landeskontenpläne |
| E28 | T001-KTOP2 of the active company codes; per chart: SKA1 without deletion flag, created (ERDAT) | T001-KTOP2 der aktiven Buchungskreise; je Kontenplan: SKA1 ohne Löschvormerkung, angelegt (ERDAT) |
| D29 | Group charts of accounts | Konzernkontenpläne |
| E29 | T004-KKTPL of the charts of row 4; per chart: SKA1 without deletion flag, created (ERDAT) | T004-KKTPL der Kontenpläne aus Zeile 4; je Kontenplan: SKA1 ohne Löschvormerkung, angelegt (ERDAT) |

Detail numbering follows the order of section 8.2; IDs are fixed so that later blocks do not renumber:

| ID | Detail | Group | Block |
|---|---|---|---|
| D01 | All company codes | G01 Company codes | BASE |
| D02 | G/L accounts at company-code level | G02 G/L | MD |
| D03 | Materials per material type | G03 Materials | MD |
| D04 | Materials with goods movements | G03 Materials | MM |
| D05 | Profit centers | G04 Controlling | MD |
| D06 | Asset sub-numbers | G05 Assets | MD |
| D07–D09 | Sales documents / deliveries / billing documents per category | G06 Sales | SD |
| D10–D11 | Purchasing documents per category / vendor invoices | G07 Purchasing | MM |
| D12 | Material documents | G08 Inventory | MM |
| D13 | Production / process orders | G09 Production | PP |
| D14 | Open maintenance orders | G10 Maintenance | PP |
| D15 | Inspection lots | G11 Quality | PP |
| D16–D17 | Transfer orders / storage locations | G12 Warehouse | MM / ORG |
| D18 | Work centers | G09 Production | PP |
| D19–D21 | House banks / house bank accounts / payments per payment method | G13 Banking | FI |
| D22–D24 | IDocs per direction and partner type / ALE IDocs / top 10 message types | G14 EDI | ORG |
| D25–D26 | Users per user type / valid dialog users regardless of logon | G15 Users | ORG |
| D27 | FI documents entered | G16 Financials | FI |
| D28–D29 | Country charts of accounts / group charts of accounts | G02 G/L | MD |
| D30–D34 | Open POs by age / by company code / items by closing pattern / items by item category / POs without activity | G07 Purchasing | MM |

Sub rows (e.g. one per material type) carry the key; its text is read at display time (T001 for D01, T134T for D03, domain fixed values of VBTYP for D07–D09, of the domain of data element EBSTYP (looked up in DD04L) for D10, of data element AUFTYP for D13, T042Z for D21, domain fixed values of BSTAT for D27, T004T for D28 and D29, text IDs M21–M24 for the age buckets of D30, T001 for D31, M18–M20 for the closing patterns of D32, T163Y for D33).

Row 26 (WM warehouse numbers, T320) is collected in block MM together with the transfer orders (D16).

### C.3 INFO labels (D80–D90)

| ID | EN | DE |
|---|---|---|
| D80 | System ID | System-ID |
| D81 | Client | Mandant |
| D82 | SAP release | SAP-Release |
| D83 | Database system | Datenbanksystem |
| D84 | Logon language | Anmeldesprache |
| D85 | Analysis period | Analysezeitraum |
| D86 | Months | Monate |
| D87 | Run start | Laufbeginn |
| D88 | Run end | Laufende |
| D89 | User | Benutzer |
| D90 | Result stored at | Ergebnis gespeichert am |

The runtime rows use M12 followed by the block name (BASE, MD, FI, SD, MM, PP, ORG, INTF, DERV).

### C.4 Interfaces view (Inn)

| ID | EN | DE |
|---|---|---|
| I01 | RFC destination | RFC-Destination |
| I02 | Logical system | Logisches System |
| I03 | Partner profile | Partnervereinbarung |
| I04 | Software component | Softwarekomponente |
| I05 | (no partner profile) | (keine Partnervereinbarung) |
