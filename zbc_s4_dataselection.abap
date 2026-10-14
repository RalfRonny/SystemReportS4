*&---------------------------------------------------------------------*
*& Report ZBC_S4_DATASELECTION
*&---------------------------------------------------------------------*
*& Data & Org Questionnaire (S/4HANA evaluation): figures from ECC.
*& Specification: ZBC_S4_DATASELECTION_Design.md
*& Classic ABAP syntax only (design 13.1). All user-visible texts come
*& from the text pool (design 12). Read-only towards business data; the
*& only write operation is the result cluster in INDX (design 13.5).
*&---------------------------------------------------------------------*
REPORT zbc_s4_dataselection LINE-SIZE 255 NO STANDARD PAGE HEADING.

*----------------------------------------------------------------------*
* Constants and types
*----------------------------------------------------------------------*
CONSTANTS: gc_x          TYPE c LENGTH 1  VALUE 'X',
           gc_version    TYPE c LENGTH 4  VALUE '0003',  " increase whenever a stored type changes
           gc_cluster_id TYPE c LENGTH 12 VALUE 'ZS4_RC_QUEST',
           gc_st_ok      TYPE c LENGTH 1  VALUE 'O',     " figure collected
           gc_st_err     TYPE c LENGTH 1  VALUE 'E'.     " figure failed; space = not collected

TYPES: ty_flag   TYPE c LENGTH 1,
       ty_textid TYPE c LENGTH 3,
       ty_num    TYPE p LENGTH 8 DECIMALS 0.

TYPES: BEGIN OF ty_meta,
         version  TYPE c LENGTH 4,
         sysid    TYPE sysysid,
         mandt    TYPE symandt,
         saprl    TYPE sysaprl,
         dbsys    TYPE sydbsys,
         langu    TYPE sylangu,
         uname    TYPE syuname,
         datfr    TYPE d,
         datto    TYPE d,
         months   TYPE i,
         startd   TYPE d,
         startt   TYPE t,
         endd     TYPE d,
         endt     TYPE t,
         stored_d TYPE d,
         stored_t TYPE t,
         g5       TYPE string,       " countries, comma-separated
         g6       TYPE string,       " ISO languages, comma-separated
         g7       TYPE string,       " currencies, comma-separated
         g5_st    TYPE ty_flag,      " status of G5 to G7 as for figures:
         g6_st    TYPE ty_flag,      " O collected, E error, space not collected
         g7_st    TYPE ty_flag,
       END OF ty_meta.

TYPES: BEGIN OF ty_block,
         block   TYPE c LENGTH 4,
         active  TYPE ty_flag,       " X = collected, space = skipped
         seconds TYPE i,
       END OF ty_block,
       ty_block_t TYPE STANDARD TABLE OF ty_block WITH DEFAULT KEY.

* One table for questionnaire rows (key Qnn) and supporting figures (key Dnn).
* The key is also the text ID of the item.
TYPES: BEGIN OF ty_fig,
         fkey    TYPE ty_textid,
         sub     TYPE c LENGTH 30,   " sub key of a detail (e.g. material type), space = header row
         grp     TYPE ty_textid,     " detail group text ID (Gnn)
         b_val   TYPE ty_num,        " current number / value
         c_total TYPE ty_num,        " created in period
         b_na    TYPE ty_flag,       " B is N/A
         c_na    TYPE ty_flag,       " C and total are N/A
         status  TYPE ty_flag,
         errtext TYPE c LENGTH 255,
       END OF ty_fig,
       ty_fig_t TYPE SORTED TABLE OF ty_fig WITH UNIQUE KEY fkey sub.

TYPES: BEGIN OF ty_plant,
         werks   TYPE t001w-werks,
         name1   TYPE t001w-name1,
         land1   TYPE t001w-land1,
         ort01   TYPE t001w-ort01,
         bukrs   TYPE t001k-bukrs,
         counted TYPE ty_flag,       " company code is active (row 27)
         manuf   TYPE ty_flag,       " production / process orders created in period
       END OF ty_plant,
       ty_plant_t TYPE STANDARD TABLE OF ty_plant WITH DEFAULT KEY.

TYPES: BEGIN OF ty_org,
         grp   TYPE ty_flag,         " P purch. org, S sales org, D distr. channel, V division, A application usage
         okey  TYPE c LENGTH 10,     " org unit key; for A the text ID of the area (Onn)
         otext TYPE c LENGTH 40,     " org unit text as read
         bukrs TYPE bukrs,
         cnt   TYPE ty_num,          " A: documents created in period
         used  TYPE ty_flag,
         status TYPE ty_flag,        " O: "used" / count known; space: source block not collected; E: error
       END OF ty_org,
       ty_org_t TYPE STANDARD TABLE OF ty_org WITH DEFAULT KEY.

TYPES: BEGIN OF ty_intf,
         otype  TYPE ty_flag,        " R RFC destination, L logical system, P partner profile, C software component
         name   TYPE c LENGTH 40,
         itype  TYPE c LENGTH 20,    " R connection type, P partner type
         descr  TYPE c LENGTH 80,    " L/P(LS) logical system text, C component text; R: type text at display
         rel    TYPE c LENGTH 10,    " C release
         splev  TYPE c LENGTH 10,    " C support package level
         idocs  TYPE ty_num,         " P IDocs created in period
         noprof TYPE ty_flag,        " P: X = IDocs in period, but no partner profile
       END OF ty_intf,
       ty_intf_t TYPE STANDARD TABLE OF ty_intf WITH DEFAULT KEY.

* Failed collection steps, shown in the INFO part of view 4 (also for steps
* that feed no questionnaire row, e.g. the organizational unit lists)
TYPES: BEGIN OF ty_error,
         step TYPE c LENGTH 20,
         text TYPE c LENGTH 255,
       END OF ty_error,
       ty_error_t TYPE STANDARD TABLE OF ty_error WITH DEFAULT KEY.

TYPES: BEGIN OF ty_result,
         meta   TYPE ty_meta,
         blocks TYPE ty_block_t,
         figs   TYPE ty_fig_t,
         plants TYPE ty_plant_t,
         orgs   TYPE ty_org_t,
         intfs  TYPE ty_intf_t,
         errors TYPE ty_error_t,
       END OF ty_result.

TYPES: BEGIN OF ty_scope,
         md   TYPE ty_flag,
         fi   TYPE ty_flag,
         sd   TYPE ty_flag,
         mm   TYPE ty_flag,
         pp   TYPE ty_flag,
         org  TYPE ty_flag,
         intf TYPE ty_flag,
       END OF ty_scope.

*----------------------------------------------------------------------*
* Selection screen (design 4)
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK bmode WITH FRAME TITLE gv_tb01.
PARAMETERS: p_coll RADIOBUTTON GROUP mode DEFAULT 'X',
            p_show RADIOBUTTON GROUP mode,
            p_del  RADIOBUTTON GROUP mode.
SELECTION-SCREEN END OF BLOCK bmode.

SELECTION-SCREEN BEGIN OF BLOCK bper WITH FRAME TITLE gv_tb02.
PARAMETERS: p_datfr TYPE sydatum,
            p_datto TYPE sydatum.
SELECTION-SCREEN END OF BLOCK bper.

SELECTION-SCREEN BEGIN OF BLOCK bscope WITH FRAME TITLE gv_tb03.
PARAMETERS: p_md   AS CHECKBOX DEFAULT 'X',
            p_fi   AS CHECKBOX DEFAULT 'X',
            p_sd   AS CHECKBOX DEFAULT 'X',
            p_mm   AS CHECKBOX DEFAULT 'X',
            p_pp   AS CHECKBOX DEFAULT 'X',
            p_org  AS CHECKBOX DEFAULT 'X',
            p_intf AS CHECKBOX.
SELECTION-SCREEN END OF BLOCK bscope.

SELECTION-SCREEN BEGIN OF BLOCK bout WITH FRAME TITLE gv_tb04.
PARAMETERS: p_v1    RADIOBUTTON GROUP view DEFAULT 'X',
            p_v2    RADIOBUTTON GROUP view,
            p_v3    RADIOBUTTON GROUP view,
            p_v4    RADIOBUTTON GROUP view,
            p_v5    RADIOBUTTON GROUP view,
            p_store AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN END OF BLOCK bout.

*----------------------------------------------------------------------*
* Text pool lookup: logon language, gaps filled from EN (design 12.3)
*----------------------------------------------------------------------*
CLASS lcl_text DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS load.
    CLASS-METHODS get
      IMPORTING iv_id          TYPE c
      RETURNING value(rv_text) TYPE string.
    CLASS-METHODS get_missing
      RETURNING value(rv_list) TYPE string.
  PRIVATE SECTION.
    TYPES ty_pool_t TYPE SORTED TABLE OF textpool WITH UNIQUE KEY id key.
    CLASS-DATA: gt_text  TYPE ty_pool_t,     " lookup table
                gt_check TYPE ty_pool_t.     " pool the completeness check runs against
    CLASS-METHODS add_range
      IMPORTING iv_prefix TYPE c
                iv_from   TYPE i
                iv_to     TYPE i
      CHANGING  ct_ids    TYPE string_table.
ENDCLASS.

CLASS lcl_text IMPLEMENTATION.

  METHOD load.
    DATA: lt_pool TYPE STANDARD TABLE OF textpool,
          ls_pool TYPE textpool,
          lv_lang TYPE sylangu.

    CLEAR: gt_text, gt_check.
    READ TEXTPOOL sy-repid INTO lt_pool LANGUAGE sy-langu.
    LOOP AT lt_pool INTO ls_pool WHERE id = 'I' AND entry IS NOT INITIAL.
      INSERT ls_pool INTO TABLE gt_text.
    ENDLOOP.
* DE and EN must be complete themselves; other logon languages rely on EN
    IF sy-langu = 'D' OR sy-langu = 'E'.
      gt_check = gt_text.
    ENDIF.
    IF sy-langu <> 'E'.
      lv_lang = 'E'.
      READ TEXTPOOL sy-repid INTO lt_pool LANGUAGE lv_lang.
      LOOP AT lt_pool INTO ls_pool WHERE id = 'I' AND entry IS NOT INITIAL.
        IF sy-langu <> 'D'.
          INSERT ls_pool INTO TABLE gt_check.
        ENDIF.
        INSERT ls_pool INTO TABLE gt_text.   " an existing logon-language entry wins
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD get.
    DATA: ls_pool TYPE textpool,
          lv_key  TYPE textpool-key.

    lv_key = iv_id.
    READ TABLE gt_text INTO ls_pool WITH TABLE KEY id = 'I' key = lv_key.
    IF sy-subrc = 0.
      rv_text = ls_pool-entry.
    ENDIF.
  ENDMETHOD.

  METHOD get_missing.
    DATA: lt_ids TYPE string_table,
          lv_id  TYPE string,
          lv_key TYPE textpool-key.

* Expected text IDs (design 12.2, appendices A to C); Rnn remarks are optional
    add_range( EXPORTING iv_prefix = 'T' iv_from = 1  iv_to = 4  CHANGING ct_ids = lt_ids ).
    add_range( EXPORTING iv_prefix = 'V' iv_from = 1  iv_to = 5  CHANGING ct_ids = lt_ids ).
    add_range( EXPORTING iv_prefix = 'H' iv_from = 1  iv_to = 8  CHANGING ct_ids = lt_ids ).
    add_range( EXPORTING iv_prefix = 'H' iv_from = 10 iv_to = 18 CHANGING ct_ids = lt_ids ).
    add_range( EXPORTING iv_prefix = 'H' iv_from = 20 iv_to = 24 CHANGING ct_ids = lt_ids ).
    add_range( EXPORTING iv_prefix = 'H' iv_from = 30 iv_to = 35 CHANGING ct_ids = lt_ids ).
    add_range( EXPORTING iv_prefix = 'M' iv_from = 1  iv_to = 17 CHANGING ct_ids = lt_ids ).
    add_range( EXPORTING iv_prefix = 'S' iv_from = 1  iv_to = 3  CHANGING ct_ids = lt_ids ).
    add_range( EXPORTING iv_prefix = 'Q' iv_from = 3  iv_to = 29 CHANGING ct_ids = lt_ids ).
    add_range( EXPORTING iv_prefix = 'N' iv_from = 3  iv_to = 16 CHANGING ct_ids = lt_ids ).
    add_range( EXPORTING iv_prefix = 'N' iv_from = 18 iv_to = 29 CHANGING ct_ids = lt_ids ).
    add_range( EXPORTING iv_prefix = 'L' iv_from = 3  iv_to = 16 CHANGING ct_ids = lt_ids ).
    add_range( EXPORTING iv_prefix = 'L' iv_from = 18 iv_to = 29 CHANGING ct_ids = lt_ids ).
    add_range( EXPORTING iv_prefix = 'O' iv_from = 1  iv_to = 8  CHANGING ct_ids = lt_ids ).
    add_range( EXPORTING iv_prefix = 'O' iv_from = 11 iv_to = 22 CHANGING ct_ids = lt_ids ).
    add_range( EXPORTING iv_prefix = 'G' iv_from = 0  iv_to = 16 CHANGING ct_ids = lt_ids ).
    add_range( EXPORTING iv_prefix = 'D' iv_from = 1  iv_to = 29 CHANGING ct_ids = lt_ids ).
    add_range( EXPORTING iv_prefix = 'E' iv_from = 1  iv_to = 29 CHANGING ct_ids = lt_ids ).
    add_range( EXPORTING iv_prefix = 'D' iv_from = 80 iv_to = 90 CHANGING ct_ids = lt_ids ).
    add_range( EXPORTING iv_prefix = 'I' iv_from = 1  iv_to = 5  CHANGING ct_ids = lt_ids ).

    LOOP AT lt_ids INTO lv_id.
      lv_key = lv_id.
      READ TABLE gt_check TRANSPORTING NO FIELDS WITH TABLE KEY id = 'I' key = lv_key.
      IF sy-subrc <> 0.
        CONCATENATE rv_list lv_id INTO rv_list SEPARATED BY space.
      ENDIF.
    ENDLOOP.
    SHIFT rv_list LEFT DELETING LEADING space.
  ENDMETHOD.

  METHOD add_range.
    DATA: lv_nr TYPE n LENGTH 2,
          lv_id TYPE string.

    lv_nr = iv_from.
    WHILE lv_nr <= iv_to.
      CONCATENATE iv_prefix lv_nr INTO lv_id.
      APPEND lv_id TO ct_ids.
      lv_nr = lv_nr + 1.
    ENDWHILE.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Analysis period (design 3 and 4)
*----------------------------------------------------------------------*
CLASS lcl_period DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS effective
      IMPORTING iv_datfr TYPE d
                iv_datto TYPE d
      EXPORTING ev_datfr TYPE d
                ev_datto TYPE d.
    CLASS-METHODS check
      IMPORTING iv_datfr        TYPE d
                iv_datto        TYPE d
      RETURNING value(rv_msgid) TYPE ty_textid.
    CLASS-METHODS months
      IMPORTING iv_datfr         TYPE d
                iv_datto         TYPE d
      RETURNING value(rv_months) TYPE i.
ENDCLASS.

CLASS lcl_period IMPLEMENTATION.

  METHOD effective.
    DATA: lv_first TYPE d,
          lv_year  TYPE n LENGTH 4,
          lv_date  TYPE c LENGTH 8.

    lv_first = sy-datum.
    lv_first+6(2) = '01'.
    ev_datto = iv_datto.
    IF ev_datto IS INITIAL.
      ev_datto = lv_first - 1.                " last day of the previous month
    ENDIF.
    ev_datfr = iv_datfr.
    IF ev_datfr IS INITIAL.
      lv_year = lv_first(4).                  " 1st day of the month 12 months back
      lv_year = lv_year - 1.
      CONCATENATE lv_year lv_first+4(4) INTO lv_date.
      ev_datfr = lv_date.
    ENDIF.
  ENDMETHOD.

  METHOD check.
    DATA: lv_first TYPE d,
          lv_next  TYPE d.

    lv_first = sy-datum.
    lv_first+6(2) = '01'.
    IF iv_datfr+6(2) <> '01'.
      rv_msgid = 'M01'.
      RETURN.
    ENDIF.
    lv_next = iv_datto + 1.
    IF lv_next+6(2) <> '01'.
      rv_msgid = 'M02'.
      RETURN.
    ENDIF.
    IF iv_datto >= lv_first.
      rv_msgid = 'M03'.
      RETURN.
    ENDIF.
    IF iv_datto < iv_datfr.
      rv_msgid = 'M04'.
    ENDIF.
  ENDMETHOD.

  METHOD months.
    DATA: lv_y1 TYPE n LENGTH 4,
          lv_y2 TYPE n LENGTH 4,
          lv_m1 TYPE n LENGTH 2,
          lv_m2 TYPE n LENGTH 2.

    lv_y1 = iv_datfr(4).
    lv_m1 = iv_datfr+4(2).
    lv_y2 = iv_datto(4).
    lv_m2 = iv_datto+4(2).
    rv_months = ( lv_y2 - lv_y1 ) * 12 + lv_m2 - lv_m1 + 1.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Result storage in INDX (design 13.5)
*----------------------------------------------------------------------*
CLASS lcl_store DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS exists
      RETURNING value(rv_exists) TYPE ty_flag.
    CLASS-METHODS save
      IMPORTING is_result TYPE ty_result.
    " ev_rc: 0 = loaded, 4 = nothing stored, 8 = stored by another program version
    CLASS-METHODS load
      EXPORTING es_result TYPE ty_result
                ev_rc     TYPE i.
    CLASS-METHODS delete.
ENDCLASS.

CLASS lcl_store IMPLEMENTATION.

  METHOD exists.
    DATA lv_version TYPE c LENGTH 4.

    IMPORT version = lv_version FROM DATABASE indx(zq) ID gc_cluster_id.
    IF sy-subrc = 0.
      rv_exists = gc_x.
    ENDIF.
  ENDMETHOD.

  METHOD save.
    DATA ls_indx TYPE indx.

    ls_indx-aedat = sy-datum.
    ls_indx-usera = sy-uname.
    ls_indx-pgmid = sy-repid.
    EXPORT version = gc_version
           meta    = is_result-meta
           blocks  = is_result-blocks
           figs    = is_result-figs
           plants  = is_result-plants
           orgs    = is_result-orgs
           intfs   = is_result-intfs
           errors  = is_result-errors
      TO DATABASE indx(zq) FROM ls_indx ID gc_cluster_id.
    COMMIT WORK.                              " releases the lock held by EXPORT
  ENDMETHOD.

  METHOD load.
    DATA lv_version TYPE c LENGTH 4.

    CLEAR es_result.
    ev_rc = 0.
    TRY.
        IMPORT version = lv_version FROM DATABASE indx(zq) ID gc_cluster_id.
        IF sy-subrc <> 0.
          ev_rc = 4.
          RETURN.
        ENDIF.
        IF lv_version <> gc_version.
          ev_rc = 8.
          RETURN.
        ENDIF.
        IMPORT meta   = es_result-meta
               blocks = es_result-blocks
               figs   = es_result-figs
               plants = es_result-plants
               orgs   = es_result-orgs
               intfs  = es_result-intfs
               errors = es_result-errors
          FROM DATABASE indx(zq) ID gc_cluster_id.
      CATCH cx_sy_import_mismatch_error.      " superclass, also covers CX_SY_IMPORT_FORMAT_ERROR
        CLEAR es_result.
        ev_rc = 8.
    ENDTRY.
  ENDMETHOD.

  METHOD delete.
    DELETE FROM DATABASE indx(zq) ID gc_cluster_id.
    COMMIT WORK.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Data collection (design 5, 7 to 11)
*----------------------------------------------------------------------*
CLASS lcl_collector DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS constructor
      IMPORTING iv_datfr TYPE d
                iv_datto TYPE d.
    METHODS run
      IMPORTING is_scope TYPE ty_scope.
    METHODS get_result
      RETURNING value(rs_result) TYPE ty_result.
  PRIVATE SECTION.
    TYPES: BEGIN OF ty_step,
             step  TYPE c LENGTH 20,
             block TYPE c LENGTH 4,
             keys  TYPE string,               " figure keys fed by the step, blank-separated
           END OF ty_step,
           ty_step_t TYPE STANDARD TABLE OF ty_step WITH DEFAULT KEY,
           BEGIN OF ty_detreg,
             fkey TYPE ty_textid,
             grp  TYPE ty_textid,
           END OF ty_detreg,
           ty_detreg_t TYPE STANDARD TABLE OF ty_detreg WITH DEFAULT KEY,
           ty_bukrs_t  TYPE SORTED TABLE OF bukrs WITH UNIQUE KEY table_line,
           BEGIN OF ty_t001,
             bukrs TYPE t001-bukrs,
             land1 TYPE t001-land1,
             waers TYPE t001-waers,
             ktopl TYPE t001-ktopl,
             ktop2 TYPE t001-ktop2,
           END OF ty_t001,
           ty_t001_t TYPE SORTED TABLE OF ty_t001 WITH UNIQUE KEY bukrs,
           BEGIN OF ty_cust_item,
             kunnr TYPE bsid-kunnr,
             bukrs TYPE bsid-bukrs,
             belnr TYPE bsid-belnr,
             gjahr TYPE bsid-gjahr,
             bschl TYPE bsid-bschl,
           END OF ty_cust_item,
           ty_cust_item_t TYPE STANDARD TABLE OF ty_cust_item WITH DEFAULT KEY,
           BEGIN OF ty_doc,
             bukrs TYPE bkpf-bukrs,
             belnr TYPE bkpf-belnr,
             gjahr TYPE bkpf-gjahr,
           END OF ty_doc,
           ty_doc_t   TYPE HASHED TABLE OF ty_doc WITH UNIQUE KEY bukrs belnr gjahr,
           ty_bschl_t TYPE HASHED TABLE OF bschl WITH UNIQUE KEY table_line,
           ty_kunnr_t TYPE HASHED TABLE OF kunnr WITH UNIQUE KEY table_line,
           ty_lifnr_t TYPE HASHED TABLE OF lifnr WITH UNIQUE KEY table_line,
           ty_vkorg_t TYPE HASHED TABLE OF vkorg WITH UNIQUE KEY table_line,
           ty_vtweg_t TYPE HASHED TABLE OF vtweg WITH UNIQUE KEY table_line,
           ty_spart_t TYPE HASHED TABLE OF spart WITH UNIQUE KEY table_line,
           ty_waers_t TYPE HASHED TABLE OF waers WITH UNIQUE KEY table_line,
           ty_ekorg_t TYPE HASHED TABLE OF ekorg WITH UNIQUE KEY table_line,
           ty_werks_t TYPE HASHED TABLE OF werks_d WITH UNIQUE KEY table_line.
    DATA: ms_res       TYPE ty_result,
          mv_datfr     TYPE d,
          mv_datto     TYPE d,
          mt_steps     TYPE ty_step_t,
          mt_detreg    TYPE ty_detreg_t,
          mt_t001      TYPE ty_t001_t,        " all company codes, read once in BASE
          mt_bukrs_act TYPE ty_bukrs_t,       " active company codes (row 3), base of rows 4, 18, 27
          mv_base_ok   TYPE ty_flag,          " BASE succeeded; dependent steps stay "not collected" otherwise
* Distinct partner sets for rows 7 and 9, merged in DERV (design 5: no UNION)
          mt_kunnr_fi  TYPE ty_kunnr_t,       " customers with a line item entered in the period
          mt_kunnr_sd  TYPE ty_kunnr_t,       " sold-to parties of sales orders created in the period
          mt_lifnr_fi  TYPE ty_lifnr_t,       " vendors with a line item entered in the period
          mt_lifnr_mm  TYPE ty_lifnr_t,       " vendors of purchase orders created in the period
          mv_fi_cust_ok TYPE ty_flag,
          mv_fi_vend_ok TYPE ty_flag,
          mv_sd_cust_ok TYPE ty_flag,         " also: the SD sets below are complete
          mv_mm_vend_ok TYPE ty_flag,
* Used organizational units and document currencies of the sales orders
* created in the period, for the organization view and G7 (design 9)
          mt_vkorg_used TYPE ty_vkorg_t,
          mt_vtweg_used TYPE ty_vtweg_t,
          mt_spart_used TYPE ty_spart_t,
          mt_waers_sd   TYPE ty_waers_t,
* Used purchasing organizations and document currencies of the purchase
* orders created in the period (design 9); complete if mv_mm_vend_ok is set
          mt_ekorg_used TYPE ty_ekorg_t,
          mt_waers_mm   TYPE ty_waers_t,
* Plants counted in row 27 (computed once by counted_plants) and plants with
* production or process orders created in the period (plant view, design 10)
          mt_werks_cnt   TYPE ty_werks_t,
          mv_werks_cnt_ok TYPE ty_flag,
          mt_werks_manuf TYPE ty_werks_t,
          mv_pp_manuf_ok TYPE ty_flag.
    METHODS register.
    METHODS add_step
      IMPORTING iv_step  TYPE c
                iv_block TYPE c
                iv_keys  TYPE c.
    METHODS add_detail
      IMPORTING iv_fkey TYPE c
                iv_grp  TYPE c.
    METHODS init_figures.
    METHODS run_block
      IMPORTING iv_block TYPE c.
    METHODS run_step
      IMPORTING is_step TYPE ty_step.
    METHODS prepare_fig
      IMPORTING iv_fkey       TYPE c
                iv_sub        TYPE c
      RETURNING value(rs_fig) TYPE ty_fig.
    METHODS store_fig
      IMPORTING is_fig TYPE ty_fig.
    METHODS set_b
      IMPORTING iv_fkey TYPE c
                iv_sub  TYPE c OPTIONAL
                iv_val  TYPE ty_num.
    METHODS set_c
      IMPORTING iv_fkey  TYPE c
                iv_sub   TYPE c OPTIONAL
                iv_total TYPE ty_num.
    METHODS mark_ok
      IMPORTING iv_fkey TYPE c.
    METHODS set_error
      IMPORTING iv_keys TYPE string
                iv_text TYPE string.
    METHODS step_base_bukrs.
    METHODS step_md_gl.
    METHODS step_md_coa.
    METHODS set_coa_sub
      IMPORTING iv_fkey  TYPE c
                iv_ktopl TYPE ktopl.
    METHODS step_md_skb1.
    METHODS step_md_kna1.
    METHODS step_md_lfa1.
    METHODS step_md_mara.
    METHODS step_md_csks.
    METHODS step_md_cepc.
    METHODS step_md_anla.
    METHODS step_fi_cust.
    METHODS add_cust_items
      IMPORTING it_item TYPE ty_cust_item_t
                it_pay  TYPE ty_bschl_t
      CHANGING  ct_doc  TYPE ty_doc_t.
    METHODS step_fi_vend.
    METHODS step_fi_banks.
    METHODS step_fi_payr.
    METHODS step_fi_reguh.
    METHODS step_fi_bkpf.
    METHODS step_sd_vbak.
    METHODS step_sd_vbuk.
    METHODS step_sd_likp.
    METHODS step_sd_vbrk.
    METHODS step_mm_ekko.
    METHODS step_mm_ekpo.
    METHODS step_mm_rbkp.
    METHODS step_mm_mkpf.
    METHODS step_mm_ltak.
    METHODS step_mm_t320.
    METHODS step_pp_aufk.
    METHODS step_pp_qals.
    METHODS step_pp_crhd.
    METHODS counted_plants.
    METHODS step_org_plants.
    METHODS step_org_edi.
    METHODS step_org_users.
    METHODS step_org_units.
    METHODS step_intf_rfc.
    METHODS step_intf_logsys.
    METHODS step_intf_partner.
    METHODS step_intf_cvers.
    METHODS step_derv_active.
    METHODS step_derv_g567.
    METHODS add_to_list
      IMPORTING iv_value TYPE c
      CHANGING  cv_list  TYPE string.
    METHODS src_status
      IMPORTING iv_steps         TYPE c
      RETURNING value(rv_status) TYPE ty_flag.
    METHODS step_derv_usage.
    METHODS add_usage
      IMPORTING iv_area TYPE c
                iv_fkey TYPE c.
ENDCLASS.

CLASS lcl_collector IMPLEMENTATION.

  METHOD constructor.
    mv_datfr = iv_datfr.
    mv_datto = iv_datto.
    ms_res-meta-version = gc_version.
    ms_res-meta-sysid   = sy-sysid.
    ms_res-meta-mandt   = sy-mandt.
    ms_res-meta-saprl   = sy-saprl.
    ms_res-meta-dbsys   = sy-dbsys.
    ms_res-meta-langu   = sy-langu.
    ms_res-meta-uname   = sy-uname.
    ms_res-meta-datfr   = iv_datfr.
    ms_res-meta-datto   = iv_datto.
    ms_res-meta-months  = lcl_period=>months( iv_datfr = iv_datfr iv_datto = iv_datto ).
  ENDMETHOD.

  METHOD run.
    DATA: lt_blocks TYPE ty_block_t,
          ls_block  TYPE ty_block,
          lv_d0     TYPE d,
          lv_t0     TYPE t.

    GET TIME.
    ms_res-meta-startd = sy-datum.
    ms_res-meta-startt = sy-uzeit.
    register( ).
    init_figures( ).

* Block order. BASE (active company codes) is always collected because the
* other blocks depend on it; DERV derives cross-block figures at the end.
    ls_block-block = 'BASE'.
    ls_block-active = gc_x.
    APPEND ls_block TO lt_blocks.
    ls_block-block = 'MD'.
    ls_block-active = is_scope-md.
    APPEND ls_block TO lt_blocks.
    ls_block-block = 'FI'.
    ls_block-active = is_scope-fi.
    APPEND ls_block TO lt_blocks.
    ls_block-block = 'SD'.
    ls_block-active = is_scope-sd.
    APPEND ls_block TO lt_blocks.
    ls_block-block = 'MM'.
    ls_block-active = is_scope-mm.
    APPEND ls_block TO lt_blocks.
    ls_block-block = 'PP'.
    ls_block-active = is_scope-pp.
    APPEND ls_block TO lt_blocks.
    ls_block-block = 'ORG'.
    ls_block-active = is_scope-org.
    APPEND ls_block TO lt_blocks.
    ls_block-block = 'INTF'.
    ls_block-active = is_scope-intf.
    APPEND ls_block TO lt_blocks.
    ls_block-block = 'DERV'.
    ls_block-active = gc_x.
    APPEND ls_block TO lt_blocks.

    LOOP AT lt_blocks INTO ls_block.
      IF ls_block-active = gc_x.
        GET TIME.
        lv_d0 = sy-datum.
        lv_t0 = sy-uzeit.
        run_block( ls_block-block ).
        GET TIME.
        ls_block-seconds = ( sy-datum - lv_d0 ) * 86400 + ( sy-uzeit - lv_t0 ).
      ENDIF.
      APPEND ls_block TO ms_res-blocks.
    ENDLOOP.

    GET TIME.
    ms_res-meta-endd = sy-datum.
    ms_res-meta-endt = sy-uzeit.
  ENDMETHOD.

  METHOD get_result.
    rs_result = ms_res.
  ENDMETHOD.

  METHOD register.
* Detail items of view 4: item text ID and group text ID (numbering follows design 8.2)
    add_detail( iv_fkey = 'D01' iv_grp = 'G01' ).
    add_detail( iv_fkey = 'D02' iv_grp = 'G02' ).
    add_detail( iv_fkey = 'D03' iv_grp = 'G03' ).
    add_detail( iv_fkey = 'D04' iv_grp = 'G03' ).
    add_detail( iv_fkey = 'D05' iv_grp = 'G04' ).
    add_detail( iv_fkey = 'D06' iv_grp = 'G05' ).
    add_detail( iv_fkey = 'D07' iv_grp = 'G06' ).
    add_detail( iv_fkey = 'D08' iv_grp = 'G06' ).
    add_detail( iv_fkey = 'D09' iv_grp = 'G06' ).
    add_detail( iv_fkey = 'D10' iv_grp = 'G07' ).
    add_detail( iv_fkey = 'D11' iv_grp = 'G07' ).
    add_detail( iv_fkey = 'D12' iv_grp = 'G08' ).
    add_detail( iv_fkey = 'D13' iv_grp = 'G09' ).
    add_detail( iv_fkey = 'D14' iv_grp = 'G10' ).
    add_detail( iv_fkey = 'D15' iv_grp = 'G11' ).
    add_detail( iv_fkey = 'D16' iv_grp = 'G12' ).
    add_detail( iv_fkey = 'D17' iv_grp = 'G12' ).
    add_detail( iv_fkey = 'D18' iv_grp = 'G09' ).
    add_detail( iv_fkey = 'D19' iv_grp = 'G13' ).
    add_detail( iv_fkey = 'D20' iv_grp = 'G13' ).
    add_detail( iv_fkey = 'D21' iv_grp = 'G13' ).
    add_detail( iv_fkey = 'D22' iv_grp = 'G14' ).
    add_detail( iv_fkey = 'D23' iv_grp = 'G14' ).
    add_detail( iv_fkey = 'D24' iv_grp = 'G14' ).
    add_detail( iv_fkey = 'D25' iv_grp = 'G15' ).
    add_detail( iv_fkey = 'D26' iv_grp = 'G15' ).
    add_detail( iv_fkey = 'D27' iv_grp = 'G16' ).
    add_detail( iv_fkey = 'D28' iv_grp = 'G02' ).
    add_detail( iv_fkey = 'D29' iv_grp = 'G02' ).

* Collection steps. One step per pass over a table (design 5); the keys are
* the figures the step feeds. If the step fails, all of them show "error".
    add_step( iv_step = 'BASE_BUKRS' iv_block = 'BASE' iv_keys = 'Q03 D01' ).
    add_step( iv_step = 'MD_GL'      iv_block = 'MD'   iv_keys = 'Q04 Q05' ).
    add_step( iv_step = 'MD_COA'     iv_block = 'MD'   iv_keys = 'D28 D29' ).
    add_step( iv_step = 'MD_SKB1'    iv_block = 'MD'   iv_keys = 'D02' ).
    add_step( iv_step = 'MD_KNA1'    iv_block = 'MD'   iv_keys = 'Q06' ).
    add_step( iv_step = 'MD_LFA1'    iv_block = 'MD'   iv_keys = 'Q08' ).
    add_step( iv_step = 'MD_MARA'    iv_block = 'MD'   iv_keys = 'Q10 D03' ).
    add_step( iv_step = 'MD_CSKS'    iv_block = 'MD'   iv_keys = 'Q11' ).
    add_step( iv_step = 'MD_CEPC'    iv_block = 'MD'   iv_keys = 'D05' ).
    add_step( iv_step = 'MD_ANLA'    iv_block = 'MD'   iv_keys = 'Q12 D06' ).
    add_step( iv_step = 'FI_CUST'    iv_block = 'FI'   iv_keys = 'Q14 Q07' ).
    add_step( iv_step = 'FI_VEND'    iv_block = 'FI'   iv_keys = 'Q09' ).
    add_step( iv_step = 'FI_BANKS'   iv_block = 'FI'   iv_keys = 'Q18 D19 D20' ).
    add_step( iv_step = 'FI_PAYR'    iv_block = 'FI'   iv_keys = 'Q19' ).
    add_step( iv_step = 'FI_REGUH'   iv_block = 'FI'   iv_keys = 'Q20 D21' ).
    add_step( iv_step = 'FI_BKPF'    iv_block = 'FI'   iv_keys = 'D27' ).
    add_step( iv_step = 'SD_VBAK'    iv_block = 'SD'   iv_keys = 'Q13 D07 Q07' ).
    add_step( iv_step = 'SD_VBUK'    iv_block = 'SD'   iv_keys = 'Q13' ).
    add_step( iv_step = 'SD_LIKP'    iv_block = 'SD'   iv_keys = 'D08' ).
    add_step( iv_step = 'SD_VBRK'    iv_block = 'SD'   iv_keys = 'D09' ).
    add_step( iv_step = 'MM_EKKO'    iv_block = 'MM'   iv_keys = 'Q15 D10 Q09' ).
    add_step( iv_step = 'MM_EKPO'    iv_block = 'MM'   iv_keys = 'Q15' ).
    add_step( iv_step = 'MM_RBKP'    iv_block = 'MM'   iv_keys = 'D11' ).
    add_step( iv_step = 'MM_MKPF'    iv_block = 'MM'   iv_keys = 'D12 D04' ).
    add_step( iv_step = 'MM_LTAK'    iv_block = 'MM'   iv_keys = 'D16' ).
    add_step( iv_step = 'MM_T320'    iv_block = 'MM'   iv_keys = 'Q26' ).
    add_step( iv_step = 'PP_AUFK'    iv_block = 'PP'   iv_keys = 'Q24 Q25 D13 D14' ).
    add_step( iv_step = 'PP_QALS'    iv_block = 'PP'   iv_keys = 'D15' ).
    add_step( iv_step = 'PP_CRHD'    iv_block = 'PP'   iv_keys = 'D18' ).
    add_step( iv_step = 'ORG_PLANTS' iv_block = 'ORG'  iv_keys = 'Q27 D17' ).
    add_step( iv_step = 'ORG_EDI'    iv_block = 'ORG'  iv_keys = 'Q23 D22 D23 D24' ).
    add_step( iv_step = 'ORG_USERS'  iv_block = 'ORG'  iv_keys = 'Q28 D25 D26' ).
* No figure keys: a failure shows up in the INFO part of view 4 (ms_res-errors)
    add_step( iv_step = 'ORG_UNITS'  iv_block = 'ORG'  iv_keys = '' ).
    add_step( iv_step = 'INTF_RFC'     iv_block = 'INTF' iv_keys = '' ).
    add_step( iv_step = 'INTF_LOGSYS'  iv_block = 'INTF' iv_keys = '' ).
    add_step( iv_step = 'INTF_PARTNER' iv_block = 'INTF' iv_keys = '' ).
    add_step( iv_step = 'INTF_CVERS'   iv_block = 'INTF' iv_keys = '' ).
    add_step( iv_step = 'DERV_ACTIVE' iv_block = 'DERV' iv_keys = 'Q07 Q09' ).
    add_step( iv_step = 'DERV_G567'  iv_block = 'DERV' iv_keys = '' ).
    add_step( iv_step = 'DERV_USAGE' iv_block = 'DERV' iv_keys = '' ).
  ENDMETHOD.

  METHOD add_step.
    DATA ls_step TYPE ty_step.

    ls_step-step  = iv_step.
    ls_step-block = iv_block.
    ls_step-keys  = iv_keys.
    APPEND ls_step TO mt_steps.
  ENDMETHOD.

  METHOD add_detail.
    DATA ls_detreg TYPE ty_detreg.

    ls_detreg-fkey = iv_fkey.
    ls_detreg-grp  = iv_grp.
    APPEND ls_detreg TO mt_detreg.
  ENDMETHOD.

  METHOD init_figures.
    DATA: lt_b_na   TYPE string_table,
          lt_c_na   TYPE string_table,
          ls_fig    TYPE ty_fig,
          ls_detreg TYPE ty_detreg,
          lv_nr     TYPE n LENGTH 2,
          lv_row    TYPE string.

* N/A cells by design (design 7)
    SPLIT '14 16 19 20 21 22 25 29' AT space INTO TABLE lt_b_na.
    SPLIT '03 04 07 09 16 18 21 22 26 27 29' AT space INTO TABLE lt_c_na.

    CLEAR ms_res-figs.
    lv_nr = 2.
    DO 27 TIMES.
      lv_nr = lv_nr + 1.
      IF lv_nr = 17.                          " "Banking" is an empty header row
        CONTINUE.
      ENDIF.
      CLEAR ls_fig.
      CONCATENATE 'Q' lv_nr INTO ls_fig-fkey.
      lv_row = lv_nr.
      READ TABLE lt_b_na TRANSPORTING NO FIELDS WITH KEY table_line = lv_row.
      IF sy-subrc = 0.
        ls_fig-b_na = gc_x.
      ENDIF.
      READ TABLE lt_c_na TRANSPORTING NO FIELDS WITH KEY table_line = lv_row.
      IF sy-subrc = 0.
        ls_fig-c_na = gc_x.
      ENDIF.
      IF ls_fig-b_na = gc_x AND ls_fig-c_na = gc_x.
        ls_fig-status = gc_st_ok.             " nothing to collect
      ENDIF.
      INSERT ls_fig INTO TABLE ms_res-figs.
    ENDDO.

* Detail headers exist from the start, so skipped blocks show "not collected"
    LOOP AT mt_detreg INTO ls_detreg.
      CLEAR ls_fig.
      ls_fig-fkey = ls_detreg-fkey.
      ls_fig-grp  = ls_detreg-grp.
      ls_fig-b_na = gc_x.
      ls_fig-c_na = gc_x.
      INSERT ls_fig INTO TABLE ms_res-figs.
    ENDLOOP.
  ENDMETHOD.

  METHOD run_block.
    DATA ls_step TYPE ty_step.

    LOOP AT mt_steps INTO ls_step WHERE block = iv_block.
      run_step( ls_step ).
    ENDLOOP.
  ENDMETHOD.

  METHOD run_step.
    DATA: lx_root  TYPE REF TO cx_root,
          lv_text  TYPE string,
          lv_msg   TYPE string,
          ls_error TYPE ty_error.

    TRY.
        CASE is_step-step.
          WHEN 'BASE_BUKRS'.
            step_base_bukrs( ).
          WHEN 'MD_GL'.
            step_md_gl( ).
          WHEN 'MD_COA'.
            step_md_coa( ).
          WHEN 'MD_SKB1'.
            step_md_skb1( ).
          WHEN 'MD_KNA1'.
            step_md_kna1( ).
          WHEN 'MD_LFA1'.
            step_md_lfa1( ).
          WHEN 'MD_MARA'.
            step_md_mara( ).
          WHEN 'MD_CSKS'.
            step_md_csks( ).
          WHEN 'MD_CEPC'.
            step_md_cepc( ).
          WHEN 'MD_ANLA'.
            step_md_anla( ).
          WHEN 'FI_CUST'.
            step_fi_cust( ).
          WHEN 'FI_VEND'.
            step_fi_vend( ).
          WHEN 'FI_BANKS'.
            step_fi_banks( ).
          WHEN 'FI_PAYR'.
            step_fi_payr( ).
          WHEN 'FI_REGUH'.
            step_fi_reguh( ).
          WHEN 'FI_BKPF'.
            step_fi_bkpf( ).
          WHEN 'SD_VBAK'.
            step_sd_vbak( ).
          WHEN 'SD_VBUK'.
            step_sd_vbuk( ).
          WHEN 'SD_LIKP'.
            step_sd_likp( ).
          WHEN 'SD_VBRK'.
            step_sd_vbrk( ).
          WHEN 'MM_EKKO'.
            step_mm_ekko( ).
          WHEN 'MM_EKPO'.
            step_mm_ekpo( ).
          WHEN 'MM_RBKP'.
            step_mm_rbkp( ).
          WHEN 'MM_MKPF'.
            step_mm_mkpf( ).
          WHEN 'MM_LTAK'.
            step_mm_ltak( ).
          WHEN 'MM_T320'.
            step_mm_t320( ).
          WHEN 'PP_AUFK'.
            step_pp_aufk( ).
          WHEN 'PP_QALS'.
            step_pp_qals( ).
          WHEN 'PP_CRHD'.
            step_pp_crhd( ).
          WHEN 'ORG_PLANTS'.
            step_org_plants( ).
          WHEN 'ORG_EDI'.
            step_org_edi( ).
          WHEN 'ORG_USERS'.
            step_org_users( ).
          WHEN 'ORG_UNITS'.
            step_org_units( ).
          WHEN 'INTF_RFC'.
            step_intf_rfc( ).
          WHEN 'INTF_LOGSYS'.
            step_intf_logsys( ).
          WHEN 'INTF_PARTNER'.
            step_intf_partner( ).
          WHEN 'INTF_CVERS'.
            step_intf_cvers( ).
          WHEN 'DERV_ACTIVE'.
            step_derv_active( ).
          WHEN 'DERV_G567'.
            step_derv_g567( ).
          WHEN 'DERV_USAGE'.
            step_derv_usage( ).
        ENDCASE.
      CATCH cx_root INTO lx_root.
        lv_text = lx_root->get_text( ).
        set_error( iv_keys = is_step-keys iv_text = lv_text ).
        ls_error-step = is_step-step.
        ls_error-text = lv_text.
        APPEND ls_error TO ms_res-errors.
        IF sy-batch = gc_x.
          lv_msg = lcl_text=>get( 'M08' ).
          CONCATENATE lv_msg is_step-keys lv_text INTO lv_msg SEPARATED BY space.
          MESSAGE lv_msg TYPE 'S'.
        ENDIF.
    ENDTRY.
  ENDMETHOD.

  METHOD prepare_fig.
    DATA ls_head TYPE ty_fig.

    rs_fig-fkey = iv_fkey.
    rs_fig-sub  = iv_sub.
    READ TABLE ms_res-figs INTO rs_fig WITH TABLE KEY fkey = rs_fig-fkey sub = rs_fig-sub.
    IF sy-subrc <> 0.
* New sub row of a detail: inherits the group, values N/A until set
      READ TABLE ms_res-figs INTO ls_head WITH TABLE KEY fkey = rs_fig-fkey sub = space.
      rs_fig-grp  = ls_head-grp.
      rs_fig-b_na = gc_x.
      rs_fig-c_na = gc_x.
    ENDIF.
  ENDMETHOD.

  METHOD store_fig.
    MODIFY TABLE ms_res-figs FROM is_fig.
    IF sy-subrc <> 0.
      INSERT is_fig INTO TABLE ms_res-figs.
    ENDIF.
  ENDMETHOD.

  METHOD set_b.
    DATA ls_fig TYPE ty_fig.

    ls_fig = prepare_fig( iv_fkey = iv_fkey iv_sub = iv_sub ).
    ls_fig-b_val  = iv_val.
    CLEAR ls_fig-b_na.
    IF ls_fig-status <> gc_st_err.              " a figure fed by several steps keeps a failure
      ls_fig-status = gc_st_ok.
    ENDIF.
    store_fig( ls_fig ).
  ENDMETHOD.

  METHOD set_c.
    DATA ls_fig TYPE ty_fig.

    ls_fig = prepare_fig( iv_fkey = iv_fkey iv_sub = iv_sub ).
    ls_fig-c_total = iv_total.
    CLEAR ls_fig-c_na.
    IF ls_fig-status <> gc_st_err.
      ls_fig-status = gc_st_ok.
    ENDIF.
    store_fig( ls_fig ).
  ENDMETHOD.

  METHOD mark_ok.
    DATA ls_fig TYPE ty_fig.

    ls_fig = prepare_fig( iv_fkey = iv_fkey iv_sub = space ).
    IF ls_fig-status <> gc_st_err.
      ls_fig-status = gc_st_ok.
    ENDIF.
    store_fig( ls_fig ).
  ENDMETHOD.

  METHOD set_error.
    DATA: lt_keys TYPE string_table,
          lv_key  TYPE string,
          lv_fkey TYPE ty_textid,
          ls_fig  TYPE ty_fig.

    SPLIT iv_keys AT space INTO TABLE lt_keys.
    ls_fig-status  = gc_st_err.
    ls_fig-errtext = iv_text.
    LOOP AT lt_keys INTO lv_key.
      lv_fkey = lv_key.
      MODIFY ms_res-figs FROM ls_fig TRANSPORTING status errtext WHERE fkey = lv_fkey.
    ENDLOOP.
  ENDMETHOD.

* Row 3 and detail D01: company codes with at least one FI document
* entered in the period (BKPF-CPUDT)
  METHOD step_base_bukrs.
    DATA: ls_t001  TYPE ty_t001,
          lv_found TYPE bukrs,
          lv_all   TYPE ty_num,
          lv_act   TYPE ty_num,
          lv_flag  TYPE ty_num.

    CLEAR: mt_t001, mt_bukrs_act, mv_base_ok.
    SELECT bukrs land1 waers ktopl ktop2 FROM t001 INTO TABLE mt_t001.
    LOOP AT mt_t001 INTO ls_t001.
      lv_all = lv_all + 1.
      SELECT bukrs FROM bkpf UP TO 1 ROWS INTO lv_found
        WHERE bukrs = ls_t001-bukrs
          AND cpudt BETWEEN mv_datfr AND mv_datto.
      ENDSELECT.
      IF sy-subrc = 0.
        INSERT ls_t001-bukrs INTO TABLE mt_bukrs_act.
        lv_act  = lv_act + 1.
        lv_flag = 1.
      ELSE.
        lv_flag = 0.
      ENDIF.
* Detail D01: one sub row per company code, value 1 = active, 0 = not active
      set_b( iv_fkey = 'D01' iv_sub = ls_t001-bukrs iv_val = lv_flag ).
    ENDLOOP.
    set_b( iv_fkey = 'Q03' iv_val = lv_act ).
    set_b( iv_fkey = 'D01' iv_val = lv_all ).
    mv_base_ok = gc_x.
  ENDMETHOD.

* Rows 4 and 5: charts of accounts of the active company codes and their
* G/L accounts at chart-of-accounts level (SKA1)
  METHOD step_md_gl.
    DATA: lt_ktopl  TYPE SORTED TABLE OF ktopl WITH UNIQUE KEY table_line,
          ls_t001   TYPE ty_t001,
          lv_ktopl  TYPE ktopl,
          lv_cnt    TYPE i,
          lv_charts TYPE ty_num,
          lv_stock  TYPE ty_num,
          lv_new    TYPE ty_num.

    IF mv_base_ok IS INITIAL.
      RETURN.
    ENDIF.
    LOOP AT mt_t001 INTO ls_t001.
      IF ls_t001-ktopl IS INITIAL.
        CONTINUE.
      ENDIF.
      READ TABLE mt_bukrs_act TRANSPORTING NO FIELDS WITH TABLE KEY table_line = ls_t001-bukrs.
      IF sy-subrc = 0.
        INSERT ls_t001-ktopl INTO TABLE lt_ktopl.
      ENDIF.
    ENDLOOP.
* Few charts: one count per chart uses the primary key prefix KTOPL
    LOOP AT lt_ktopl INTO lv_ktopl.
      lv_charts = lv_charts + 1.
      SELECT COUNT( * ) FROM ska1 INTO lv_cnt
        WHERE ktopl = lv_ktopl
          AND xloev = space.
      lv_stock = lv_stock + lv_cnt.
      SELECT COUNT( * ) FROM ska1 INTO lv_cnt
        WHERE ktopl = lv_ktopl
          AND erdat BETWEEN mv_datfr AND mv_datto.
      lv_new = lv_new + lv_cnt.
    ENDLOOP.
    set_b( iv_fkey = 'Q04' iv_val = lv_charts ).
    set_b( iv_fkey = 'Q05' iv_val = lv_stock ).
    set_c( iv_fkey = 'Q05' iv_total = lv_new ).
  ENDMETHOD.

* Details D28 and D29: country charts of accounts (T001-KTOP2) of the active
* company codes and group charts of accounts (T004-KKTPL) of the operational
* charts of row 4. Header = number of charts, one sub row per chart with its
* G/L accounts (SKA1)
  METHOD step_md_coa.
    DATA: lt_ktopl TYPE SORTED TABLE OF ktopl WITH UNIQUE KEY table_line,
          lt_ktop2 TYPE SORTED TABLE OF ktopl WITH UNIQUE KEY table_line,
          lt_kktpl TYPE SORTED TABLE OF ktopl WITH UNIQUE KEY table_line,
          ls_t001  TYPE ty_t001,
          lv_ktopl TYPE ktopl,
          lv_kktpl TYPE ktopl,
          lv_cnt   TYPE ty_num.

    IF mv_base_ok IS INITIAL.
      RETURN.
    ENDIF.
    LOOP AT mt_t001 INTO ls_t001.
      READ TABLE mt_bukrs_act TRANSPORTING NO FIELDS WITH TABLE KEY table_line = ls_t001-bukrs.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      IF ls_t001-ktopl IS NOT INITIAL.
        INSERT ls_t001-ktopl INTO TABLE lt_ktopl.
      ENDIF.
      IF ls_t001-ktop2 IS NOT INITIAL.
        INSERT ls_t001-ktop2 INTO TABLE lt_ktop2.
      ENDIF.
    ENDLOOP.
* Group chart is an attribute of the operational chart (few charts, one read each)
    LOOP AT lt_ktopl INTO lv_ktopl.
      CLEAR lv_kktpl.
      SELECT SINGLE kktpl FROM t004 INTO lv_kktpl
        WHERE ktopl = lv_ktopl.
      IF sy-subrc = 0 AND lv_kktpl IS NOT INITIAL.
        INSERT lv_kktpl INTO TABLE lt_kktpl.
      ENDIF.
    ENDLOOP.

    LOOP AT lt_ktop2 INTO lv_ktopl.
      set_coa_sub( iv_fkey = 'D28' iv_ktopl = lv_ktopl ).
    ENDLOOP.
    lv_cnt = lines( lt_ktop2 ).
    set_b( iv_fkey = 'D28' iv_val = lv_cnt ).

    LOOP AT lt_kktpl INTO lv_ktopl.
      set_coa_sub( iv_fkey = 'D29' iv_ktopl = lv_ktopl ).
    ENDLOOP.
    lv_cnt = lines( lt_kktpl ).
    set_b( iv_fkey = 'D29' iv_val = lv_cnt ).
  ENDMETHOD.

* Sub row of D28/D29: G/L accounts of one chart (SKA1) without deletion flag
* (value) and created in the period (total)
  METHOD set_coa_sub.
    DATA: lv_cnt TYPE i,
          lv_num TYPE ty_num.

    SELECT COUNT( * ) FROM ska1 INTO lv_cnt
      WHERE ktopl = iv_ktopl
        AND xloev = space.
    lv_num = lv_cnt.
    set_b( iv_fkey = iv_fkey iv_sub = iv_ktopl iv_val = lv_num ).
    SELECT COUNT( * ) FROM ska1 INTO lv_cnt
      WHERE ktopl = iv_ktopl
        AND erdat BETWEEN mv_datfr AND mv_datto.
    lv_num = lv_cnt.
    set_c( iv_fkey = iv_fkey iv_sub = iv_ktopl iv_total = lv_num ).
  ENDMETHOD.

* Detail D02: G/L accounts at company-code level (SKB1) of the active
* company codes, without deletion flag and posting block
  METHOD step_md_skb1.
    DATA: lv_bukrs TYPE bukrs,
          lv_cnt   TYPE i,
          lv_total TYPE ty_num.

    IF mv_base_ok IS INITIAL.
      RETURN.
    ENDIF.
    LOOP AT mt_bukrs_act INTO lv_bukrs.
      SELECT COUNT( * ) FROM skb1 INTO lv_cnt
        WHERE bukrs = lv_bukrs
          AND xloeb = space
          AND xspeb = space.
      lv_total = lv_total + lv_cnt.
    ENDLOOP.
    set_b( iv_fkey = 'D02' iv_val = lv_total ).
  ENDMETHOD.

* Row 6: customers. One pass, grouped by creation date and deletion flag:
* B = without central deletion flag, C = created in the period
  METHOD step_md_kna1.
    TYPES: BEGIN OF lty_grp,
             erdat TYPE kna1-erdat,
             loevm TYPE kna1-loevm,
             cnt   TYPE i,
           END OF lty_grp.
    DATA: lt_grp   TYPE STANDARD TABLE OF lty_grp,
          ls_grp   TYPE lty_grp,
          lv_stock TYPE ty_num,
          lv_new   TYPE ty_num.

    SELECT erdat loevm COUNT( * ) FROM kna1 INTO TABLE lt_grp
      GROUP BY erdat loevm.
    LOOP AT lt_grp INTO ls_grp.
      IF ls_grp-loevm IS INITIAL.
        lv_stock = lv_stock + ls_grp-cnt.
      ENDIF.
      IF ls_grp-erdat BETWEEN mv_datfr AND mv_datto.
        lv_new = lv_new + ls_grp-cnt.
      ENDIF.
    ENDLOOP.
    set_b( iv_fkey = 'Q06' iv_val = lv_stock ).
    set_c( iv_fkey = 'Q06' iv_total = lv_new ).
  ENDMETHOD.

* Row 8: vendors, same logic as row 6
  METHOD step_md_lfa1.
    TYPES: BEGIN OF lty_grp,
             erdat TYPE lfa1-erdat,
             loevm TYPE lfa1-loevm,
             cnt   TYPE i,
           END OF lty_grp.
    DATA: lt_grp   TYPE STANDARD TABLE OF lty_grp,
          ls_grp   TYPE lty_grp,
          lv_stock TYPE ty_num,
          lv_new   TYPE ty_num.

    SELECT erdat loevm COUNT( * ) FROM lfa1 INTO TABLE lt_grp
      GROUP BY erdat loevm.
    LOOP AT lt_grp INTO ls_grp.
      IF ls_grp-loevm IS INITIAL.
        lv_stock = lv_stock + ls_grp-cnt.
      ENDIF.
      IF ls_grp-erdat BETWEEN mv_datfr AND mv_datto.
        lv_new = lv_new + ls_grp-cnt.
      ENDIF.
    ENDLOOP.
    set_b( iv_fkey = 'Q08' iv_val = lv_stock ).
    set_c( iv_fkey = 'Q08' iv_total = lv_new ).
  ENDMETHOD.

* Row 10 and detail D03: materials. One pass, grouped by material type,
* deletion flag and creation date
  METHOD step_md_mara.
    TYPES: BEGIN OF lty_grp,
             mtart TYPE mara-mtart,
             lvorm TYPE mara-lvorm,
             ersda TYPE mara-ersda,
             cnt   TYPE i,
           END OF lty_grp,
           BEGIN OF lty_type,
             mtart TYPE mara-mtart,
             cnt   TYPE ty_num,
           END OF lty_type.
    DATA: lt_grp   TYPE STANDARD TABLE OF lty_grp,
          ls_grp   TYPE lty_grp,
          lt_type  TYPE SORTED TABLE OF lty_type WITH UNIQUE KEY mtart,
          ls_type  TYPE lty_type,
          lv_stock TYPE ty_num,
          lv_new   TYPE ty_num.

    SELECT mtart lvorm ersda COUNT( * ) FROM mara INTO TABLE lt_grp
      GROUP BY mtart lvorm ersda.
    LOOP AT lt_grp INTO ls_grp.
      IF ls_grp-lvorm IS INITIAL.
        lv_stock = lv_stock + ls_grp-cnt.
        ls_type-mtart = ls_grp-mtart.
        IF ls_type-mtart IS INITIAL.
          ls_type-mtart = '-'.                  " sub key space is the header row
        ENDIF.
        ls_type-cnt = ls_grp-cnt.
        COLLECT ls_type INTO lt_type.
      ENDIF.
      IF ls_grp-ersda BETWEEN mv_datfr AND mv_datto.
        lv_new = lv_new + ls_grp-cnt.
      ENDIF.
    ENDLOOP.
    set_b( iv_fkey = 'Q10' iv_val = lv_stock ).
    set_c( iv_fkey = 'Q10' iv_total = lv_new ).
    set_b( iv_fkey = 'D03' iv_val = lv_stock ).
    LOOP AT lt_type INTO ls_type.
      set_b( iv_fkey = 'D03' iv_sub = ls_type-mtart iv_val = ls_type-cnt ).
    ENDLOOP.
  ENDMETHOD.

* Row 11: cost centers. B = records valid today (validity periods of one
* cost center do not overlap, so one record per cost center);
* C = cost centers whose earliest validity record was created in the period
  METHOD step_md_csks.
    TYPES: BEGIN OF lty_first,
             kokrs TYPE csks-kokrs,
             kostl TYPE csks-kostl,
             ersda TYPE csks-ersda,
           END OF lty_first.
    DATA: lt_first TYPE STANDARD TABLE OF lty_first,
          ls_first TYPE lty_first,
          lv_cnt   TYPE i,
          lv_stock TYPE ty_num,
          lv_new   TYPE ty_num.

    SELECT COUNT( * ) FROM csks INTO lv_cnt
      WHERE datab <= sy-datum
        AND datbi >= sy-datum.
    lv_stock = lv_cnt.
    SELECT kokrs kostl MIN( ersda ) FROM csks INTO TABLE lt_first
      GROUP BY kokrs kostl.
    LOOP AT lt_first INTO ls_first.
      IF ls_first-ersda BETWEEN mv_datfr AND mv_datto.
        lv_new = lv_new + 1.
      ENDIF.
    ENDLOOP.
    set_b( iv_fkey = 'Q11' iv_val = lv_stock ).
    set_c( iv_fkey = 'Q11' iv_total = lv_new ).
  ENDMETHOD.

* Detail D05: profit centers valid today (CEPC)
  METHOD step_md_cepc.
    DATA: lv_cnt TYPE i,
          lv_val TYPE ty_num.

    SELECT COUNT( * ) FROM cepc INTO lv_cnt
      WHERE datab <= sy-datum
        AND datbi >= sy-datum.
    lv_val = lv_cnt.
    set_b( iv_fkey = 'D05' iv_val = lv_val ).
  ENDMETHOD.

* Row 12 and detail D06: assets that are not deactivated. Main numbers have
* sub-number 0000; one pass grouped by sub-number
  METHOD step_md_anla.
    TYPES: BEGIN OF lty_sub,
             anln2 TYPE anla-anln2,
             cnt   TYPE i,
           END OF lty_sub.
    DATA: lt_sub   TYPE STANDARD TABLE OF lty_sub,
          ls_sub   TYPE lty_sub,
          lv_deakt TYPE anla-deakt,             " initial = not deactivated
          lv_cnt   TYPE i,
          lv_main  TYPE ty_num,
          lv_subs  TYPE ty_num,
          lv_new   TYPE ty_num.

    SELECT anln2 COUNT( * ) FROM anla INTO TABLE lt_sub
      WHERE deakt = lv_deakt
      GROUP BY anln2.
    LOOP AT lt_sub INTO ls_sub.
      IF ls_sub-anln2 = '0000'.
        lv_main = lv_main + ls_sub-cnt.
      ELSE.
        lv_subs = lv_subs + ls_sub-cnt.
      ENDIF.
    ENDLOOP.
    SELECT COUNT( * ) FROM anla INTO lv_cnt
      WHERE anln2 = '0000'
        AND erdat BETWEEN mv_datfr AND mv_datto.
    lv_new = lv_cnt.
    set_b( iv_fkey = 'Q12' iv_val = lv_main ).
    set_c( iv_fkey = 'Q12' iv_total = lv_new ).
    set_b( iv_fkey = 'D06' iv_val = lv_subs ).
  ENDMETHOD.

* Row 14 and the FI part of row 7: one pass over BSID and one over BSAD
* (open and cleared customer items), only items entered in the period.
* Row 14 counts documents, not line items (design 2 #7)
  METHOD step_fi_cust.
    TYPES: BEGIN OF lty_tbsl,
             bschl TYPE tbsl-bschl,
             koart TYPE tbsl-koart,
             shkzg TYPE tbsl-shkzg,
             xzahl TYPE tbsl-xzahl,
           END OF lty_tbsl.
    DATA: lt_tbsl TYPE STANDARD TABLE OF lty_tbsl,
          ls_tbsl TYPE lty_tbsl,
          lt_pay  TYPE ty_bschl_t,
          lt_item TYPE ty_cust_item_t,
          lt_doc  TYPE ty_doc_t,
          lv_cnt  TYPE i,
          lv_docs TYPE ty_num.

    CLEAR: mt_kunnr_fi, mv_fi_cust_ok.
* Incoming payment posting keys by their SAP attributes, no key value hard-coded:
* customer account, credit, payment transaction
    SELECT bschl koart shkzg xzahl FROM tbsl INTO TABLE lt_tbsl.
    LOOP AT lt_tbsl INTO ls_tbsl.
      IF ls_tbsl-koart = 'D' AND ls_tbsl-shkzg = 'H' AND ls_tbsl-xzahl = gc_x.
        INSERT ls_tbsl-bschl INTO TABLE lt_pay.
      ENDIF.
    ENDLOOP.

    SELECT kunnr bukrs belnr gjahr bschl FROM bsid INTO TABLE lt_item
      PACKAGE SIZE 50000
      WHERE cpudt BETWEEN mv_datfr AND mv_datto.
      add_cust_items( EXPORTING it_item = lt_item
                                it_pay  = lt_pay
                      CHANGING  ct_doc  = lt_doc ).
    ENDSELECT.
    SELECT kunnr bukrs belnr gjahr bschl FROM bsad INTO TABLE lt_item
      PACKAGE SIZE 50000
      WHERE cpudt BETWEEN mv_datfr AND mv_datto.
      add_cust_items( EXPORTING it_item = lt_item
                                it_pay  = lt_pay
                      CHANGING  ct_doc  = lt_doc ).
    ENDSELECT.

    DESCRIBE TABLE lt_doc LINES lv_cnt.
    lv_docs = lv_cnt.
    set_c( iv_fkey = 'Q14' iv_total = lv_docs ).
    mv_fi_cust_ok = gc_x.
  ENDMETHOD.

  METHOD add_cust_items.
    DATA: ls_item TYPE ty_cust_item,
          ls_doc  TYPE ty_doc.

    LOOP AT it_item INTO ls_item.
      INSERT ls_item-kunnr INTO TABLE mt_kunnr_fi.          " duplicates are rejected
      READ TABLE it_pay TRANSPORTING NO FIELDS WITH TABLE KEY table_line = ls_item-bschl.
      IF sy-subrc = 0.
        ls_doc-bukrs = ls_item-bukrs.
        ls_doc-belnr = ls_item-belnr.
        ls_doc-gjahr = ls_item-gjahr.
        INSERT ls_doc INTO TABLE ct_doc.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

* FI part of row 9: distinct vendors with a line item entered in the period
* (BSIK open, BSAK cleared); one aggregated pass per table
  METHOD step_fi_vend.
    DATA: lt_lifnr TYPE STANDARD TABLE OF lifnr,
          lv_lifnr TYPE lifnr.

    CLEAR: mt_lifnr_fi, mv_fi_vend_ok.
    SELECT DISTINCT lifnr FROM bsik INTO TABLE lt_lifnr
      WHERE cpudt BETWEEN mv_datfr AND mv_datto.
    LOOP AT lt_lifnr INTO lv_lifnr.
      INSERT lv_lifnr INTO TABLE mt_lifnr_fi.
    ENDLOOP.
    SELECT DISTINCT lifnr FROM bsak INTO TABLE lt_lifnr
      WHERE cpudt BETWEEN mv_datfr AND mv_datto.
    LOOP AT lt_lifnr INTO lv_lifnr.
      INSERT lv_lifnr INTO TABLE mt_lifnr_fi.
    ENDLOOP.
    mv_fi_vend_ok = gc_x.
  ENDMETHOD.

* Row 18 and details D19/D20: house banks (T012) and house bank accounts
* (T012K) of the active company codes; row 18 = distinct bank country + bank key
  METHOD step_fi_banks.
    TYPES: BEGIN OF lty_t012,
             bukrs TYPE t012-bukrs,
             hbkid TYPE t012-hbkid,
             banks TYPE t012-banks,
             bankl TYPE t012-bankl,
           END OF lty_t012,
           BEGIN OF lty_t012k,
             bukrs TYPE t012k-bukrs,
             hbkid TYPE t012k-hbkid,
             hktid TYPE t012k-hktid,
           END OF lty_t012k,
           BEGIN OF lty_bank,
             banks TYPE t012-banks,
             bankl TYPE t012-bankl,
           END OF lty_bank.
    DATA: lt_t012  TYPE STANDARD TABLE OF lty_t012,
          ls_t012  TYPE lty_t012,
          lt_t012k TYPE STANDARD TABLE OF lty_t012k,
          ls_t012k TYPE lty_t012k,
          lt_bank  TYPE HASHED TABLE OF lty_bank WITH UNIQUE KEY banks bankl,
          ls_bank  TYPE lty_bank,
          lv_cnt   TYPE i,
          lv_banks TYPE ty_num,
          lv_hbank TYPE ty_num,
          lv_accts TYPE ty_num.

    IF mv_base_ok IS INITIAL.
      RETURN.
    ENDIF.
    SELECT bukrs hbkid banks bankl FROM t012 INTO TABLE lt_t012.
    LOOP AT lt_t012 INTO ls_t012.
      READ TABLE mt_bukrs_act TRANSPORTING NO FIELDS WITH TABLE KEY table_line = ls_t012-bukrs.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      lv_hbank = lv_hbank + 1.
      IF ls_t012-banks IS NOT INITIAL OR ls_t012-bankl IS NOT INITIAL.
        ls_bank-banks = ls_t012-banks.
        ls_bank-bankl = ls_t012-bankl.
        INSERT ls_bank INTO TABLE lt_bank.
      ENDIF.
    ENDLOOP.
    DESCRIBE TABLE lt_bank LINES lv_cnt.
    lv_banks = lv_cnt.

    SELECT bukrs hbkid hktid FROM t012k INTO TABLE lt_t012k.
    LOOP AT lt_t012k INTO ls_t012k.
      READ TABLE mt_bukrs_act TRANSPORTING NO FIELDS WITH TABLE KEY table_line = ls_t012k-bukrs.
      IF sy-subrc = 0.
        lv_accts = lv_accts + 1.
      ENDIF.
    ENDLOOP.

    set_b( iv_fkey = 'Q18' iv_val = lv_banks ).
    set_b( iv_fkey = 'D19' iv_val = lv_hbank ).
    set_b( iv_fkey = 'D20' iv_val = lv_accts ).
  ENDMETHOD.

* Row 19: checks in the check register (PAYR) with payment date in the period,
* not voided. VOIDR is NUMC, so "initial" is compared with a typed variable
  METHOD step_fi_payr.
    DATA: lv_voidr TYPE payr-voidr,
          lv_cnt   TYPE i,
          lv_total TYPE ty_num.

    SELECT COUNT( * ) FROM payr INTO lv_cnt
      WHERE zaldt BETWEEN mv_datfr AND mv_datto
        AND voidr = lv_voidr.
    lv_total = lv_cnt.
    set_c( iv_fkey = 'Q19' iv_total = lv_total ).
  ENDMETHOD.

* Row 20 and detail D21: payments of productive payment runs (REGUH: run date
* in the period, no proposal run, payment document created). One aggregated
* pass per run, paying company code and payment method used (RZAWE; REGUH has
* no ZLSCH). Runs whose 6th run-ID character is 'P' (SAP convention: HR payroll
* DME pre-program) are skipped, as HR is out of scope. Row 20 counts outgoing
* payment methods (XEINZ initial) classified as bank transfer in T042Z, i.e.
* none of the check / bill of exchange indicators set; D21 shows all methods.
  METHOD step_fi_reguh.
    TYPES: BEGIN OF lty_grp,
             laufi TYPE reguh-laufi,
             zbukr TYPE reguh-zbukr,
             rzawe TYPE reguh-rzawe,
             cnt   TYPE i,
           END OF lty_grp,
           BEGIN OF lty_t042z,
             land1 TYPE t042z-land1,
             zlsch TYPE t042z-zlsch,
             xeinz TYPE t042z-xeinz,
             xschk TYPE t042z-xschk,
             xwech TYPE t042z-xwech,
             xwanf TYPE t042z-xwanf,
             xwecs TYPE t042z-xwecs,
             xswec TYPE t042z-xswec,
           END OF lty_t042z,
           BEGIN OF lty_meth,
             land1 TYPE t001-land1,
             zlsch TYPE t042z-zlsch,
             cnt   TYPE ty_num,
           END OF lty_meth.
    DATA: lt_grp   TYPE STANDARD TABLE OF lty_grp,
          ls_grp   TYPE lty_grp,
          lt_t042z TYPE SORTED TABLE OF lty_t042z WITH UNIQUE KEY land1 zlsch,
          ls_t042z TYPE lty_t042z,
          lt_meth  TYPE SORTED TABLE OF lty_meth WITH UNIQUE KEY land1 zlsch,
          ls_meth  TYPE lty_meth,
          ls_t001  TYPE ty_t001,
          lv_sub   TYPE c LENGTH 30,
          lv_eft   TYPE ty_num,
          lv_total TYPE ty_num.

    IF mv_base_ok IS INITIAL.                 " country of the paying company code comes from T001
      RETURN.
    ENDIF.
    SELECT laufi zbukr rzawe COUNT( * ) FROM reguh INTO TABLE lt_grp
      WHERE laufd BETWEEN mv_datfr AND mv_datto
        AND xvorl = space
        AND vblnr <> space
      GROUP BY laufi zbukr rzawe.
    SELECT land1 zlsch xeinz xschk xwech xwanf xwecs xswec FROM t042z INTO TABLE lt_t042z.

    LOOP AT lt_grp INTO ls_grp.
      IF ls_grp-laufi+5(1) = 'P'.
        CONTINUE.
      ENDIF.
      CLEAR: ls_meth, ls_t001.
      READ TABLE mt_t001 INTO ls_t001 WITH TABLE KEY bukrs = ls_grp-zbukr.
      ls_meth-land1 = ls_t001-land1.
      ls_meth-zlsch = ls_grp-rzawe.
      ls_meth-cnt   = ls_grp-cnt.
      COLLECT ls_meth INTO lt_meth.
    ENDLOOP.

    LOOP AT lt_meth INTO ls_meth.
      lv_total = lv_total + ls_meth-cnt.
      READ TABLE lt_t042z INTO ls_t042z WITH TABLE KEY land1 = ls_meth-land1 zlsch = ls_meth-zlsch.
      IF sy-subrc = 0
        AND ls_t042z-xeinz IS INITIAL
        AND ls_t042z-xschk IS INITIAL
        AND ls_t042z-xwech IS INITIAL
        AND ls_t042z-xwanf IS INITIAL
        AND ls_t042z-xwecs IS INITIAL
        AND ls_t042z-xswec IS INITIAL.
        lv_eft = lv_eft + ls_meth-cnt.
      ENDIF.
      CONCATENATE ls_meth-land1 '/' ls_meth-zlsch INTO lv_sub.
      set_c( iv_fkey = 'D21' iv_sub = lv_sub iv_total = ls_meth-cnt ).
    ENDLOOP.

    set_c( iv_fkey = 'Q20' iv_total = lv_eft ).
    set_c( iv_fkey = 'D21' iv_total = lv_total ).
  ENDMETHOD.

* Detail D27: FI documents entered in the period (BKPF-CPUDT), one aggregated
* pass, split by document status (BSTAT) so that parked, noted or sample
* documents are visible
  METHOD step_fi_bkpf.
    TYPES: BEGIN OF lty_grp,
             bstat TYPE bkpf-bstat,
             cnt   TYPE i,
           END OF lty_grp.
    DATA: lt_grp   TYPE STANDARD TABLE OF lty_grp,
          ls_grp   TYPE lty_grp,
          lv_sub   TYPE c LENGTH 30,
          lv_cnt   TYPE ty_num,
          lv_total TYPE ty_num.

    SELECT bstat COUNT( * ) FROM bkpf INTO TABLE lt_grp
      WHERE cpudt BETWEEN mv_datfr AND mv_datto
      GROUP BY bstat.
    LOOP AT lt_grp INTO ls_grp.
      lv_cnt   = ls_grp-cnt.
      lv_total = lv_total + lv_cnt.
      lv_sub   = ls_grp-bstat.
      IF lv_sub IS INITIAL.
        lv_sub = '-'.                           " sub key space is the header row
      ENDIF.
      set_c( iv_fkey = 'D27' iv_sub = lv_sub iv_total = lv_cnt ).
    ENDLOOP.
    set_c( iv_fkey = 'D27' iv_total = lv_total ).
  ENDMETHOD.

* Row 13 C, detail D07 and the SD part of row 7: one aggregated pass over the
* sales documents created in the period (VBAK-ERDAT). Sales orders are SD
* document category C (SAP-defined). The same pass collects the sales
* organizations, distribution channels, divisions and document currencies of
* the sales orders for the organization view (design 5: one pass per table)
  METHOD step_sd_vbak.
    TYPES: BEGIN OF lty_grp,
             vbtyp TYPE vbak-vbtyp,
             kunnr TYPE vbak-kunnr,
             vkorg TYPE vbak-vkorg,
             vtweg TYPE vbak-vtweg,
             spart TYPE vbak-spart,
             waerk TYPE vbak-waerk,
             cnt   TYPE i,
           END OF lty_grp,
           BEGIN OF lty_cat,
             vbtyp TYPE vbak-vbtyp,
             cnt   TYPE ty_num,
           END OF lty_cat.
    DATA: lt_grp    TYPE STANDARD TABLE OF lty_grp,
          ls_grp    TYPE lty_grp,
          lt_cat    TYPE SORTED TABLE OF lty_cat WITH UNIQUE KEY vbtyp,
          ls_cat    TYPE lty_cat,
          lv_sub    TYPE c LENGTH 30,
          lv_orders TYPE ty_num,
          lv_total  TYPE ty_num.

    CLEAR: mt_kunnr_sd, mt_vkorg_used, mt_vtweg_used, mt_spart_used, mt_waers_sd, mv_sd_cust_ok.
    SELECT vbtyp kunnr vkorg vtweg spart waerk COUNT( * ) FROM vbak INTO TABLE lt_grp
      PACKAGE SIZE 50000
      WHERE erdat BETWEEN mv_datfr AND mv_datto
      GROUP BY vbtyp kunnr vkorg vtweg spart waerk.
      LOOP AT lt_grp INTO ls_grp.
        ls_cat-vbtyp = ls_grp-vbtyp.
        ls_cat-cnt   = ls_grp-cnt.
        COLLECT ls_cat INTO lt_cat.
        IF ls_grp-vbtyp = 'C'.
          IF ls_grp-kunnr IS NOT INITIAL.
            INSERT ls_grp-kunnr INTO TABLE mt_kunnr_sd.
          ENDIF.
          INSERT ls_grp-vkorg INTO TABLE mt_vkorg_used.
          INSERT ls_grp-vtweg INTO TABLE mt_vtweg_used.
          INSERT ls_grp-spart INTO TABLE mt_spart_used.
          INSERT ls_grp-waerk INTO TABLE mt_waers_sd.
        ENDIF.
      ENDLOOP.
    ENDSELECT.

    LOOP AT lt_cat INTO ls_cat.
      lv_total = lv_total + ls_cat-cnt.
      IF ls_cat-vbtyp = 'C'.
        lv_orders = ls_cat-cnt.
      ENDIF.
      lv_sub = ls_cat-vbtyp.
      IF lv_sub IS INITIAL.
        lv_sub = '-'.                           " sub key space is the header row
      ENDIF.
      set_c( iv_fkey = 'D07' iv_sub = lv_sub iv_total = ls_cat-cnt ).
    ENDLOOP.
    set_c( iv_fkey = 'Q13' iv_total = lv_orders ).
    set_c( iv_fkey = 'D07' iv_total = lv_total ).
    mv_sd_cust_ok = gc_x.
  ENDMETHOD.

* Row 13 B: open sales orders today, from the header status table: SD document
* category C and overall processing status not C (completely processed)
  METHOD step_sd_vbuk.
    DATA: lv_cnt  TYPE i,
          lv_open TYPE ty_num.

    SELECT COUNT( * ) FROM vbuk INTO lv_cnt
      WHERE vbtyp = 'C'
        AND gbstk <> 'C'.
    lv_open = lv_cnt.
    set_b( iv_fkey = 'Q13' iv_val = lv_open ).
  ENDMETHOD.

* Detail D08: deliveries created in the period (LIKP-ERDAT) per SD document
* category, one aggregated pass
  METHOD step_sd_likp.
    TYPES: BEGIN OF lty_grp,
             vbtyp TYPE likp-vbtyp,
             cnt   TYPE i,
           END OF lty_grp.
    DATA: lt_grp   TYPE STANDARD TABLE OF lty_grp,
          ls_grp   TYPE lty_grp,
          lv_sub   TYPE c LENGTH 30,
          lv_cnt   TYPE ty_num,
          lv_total TYPE ty_num.

    SELECT vbtyp COUNT( * ) FROM likp INTO TABLE lt_grp
      WHERE erdat BETWEEN mv_datfr AND mv_datto
      GROUP BY vbtyp.
    LOOP AT lt_grp INTO ls_grp.
      lv_cnt   = ls_grp-cnt.
      lv_total = lv_total + lv_cnt.
      lv_sub   = ls_grp-vbtyp.
      IF lv_sub IS INITIAL.
        lv_sub = '-'.
      ENDIF.
      set_c( iv_fkey = 'D08' iv_sub = lv_sub iv_total = lv_cnt ).
    ENDLOOP.
    set_c( iv_fkey = 'D08' iv_total = lv_total ).
  ENDMETHOD.

* Detail D09: billing documents created in the period (VBRK-ERDAT) per SD
* document category; cancelled documents (FKSTO) get their own sub row,
* sub key "<category> X"
  METHOD step_sd_vbrk.
    TYPES: BEGIN OF lty_grp,
             vbtyp TYPE vbrk-vbtyp,
             fksto TYPE vbrk-fksto,
             cnt   TYPE i,
           END OF lty_grp.
    DATA: lt_grp   TYPE STANDARD TABLE OF lty_grp,
          ls_grp   TYPE lty_grp,
          lv_sub   TYPE c LENGTH 30,
          lv_cnt   TYPE ty_num,
          lv_total TYPE ty_num.

    SELECT vbtyp fksto COUNT( * ) FROM vbrk INTO TABLE lt_grp
      WHERE erdat BETWEEN mv_datfr AND mv_datto
      GROUP BY vbtyp fksto.
    LOOP AT lt_grp INTO ls_grp.
      lv_cnt   = ls_grp-cnt.
      lv_total = lv_total + lv_cnt.
      lv_sub   = ls_grp-vbtyp.
      IF lv_sub IS INITIAL.
        lv_sub = '-'.
      ENDIF.
      IF ls_grp-fksto IS NOT INITIAL.
        CONCATENATE lv_sub ls_grp-fksto INTO lv_sub SEPARATED BY space.
      ENDIF.
      set_c( iv_fkey = 'D09' iv_sub = lv_sub iv_total = lv_cnt ).
    ENDLOOP.
    set_c( iv_fkey = 'D09' iv_total = lv_total ).
  ENDMETHOD.

* Row 15 C, detail D10 and the MM part of row 9: one aggregated pass over the
* purchasing documents created in the period (EKKO-AEDAT = created on).
* Purchase orders are purchasing document category F (SAP-defined). The same
* pass collects the purchasing organizations and document currencies of the
* purchase orders for the organization view (design 5: one pass per table)
  METHOD step_mm_ekko.
    TYPES: BEGIN OF lty_grp,
             bstyp TYPE ekko-bstyp,
             lifnr TYPE ekko-lifnr,
             ekorg TYPE ekko-ekorg,
             waers TYPE ekko-waers,
             cnt   TYPE i,
           END OF lty_grp,
           BEGIN OF lty_cat,
             bstyp TYPE ekko-bstyp,
             cnt   TYPE ty_num,
           END OF lty_cat.
    DATA: lt_grp    TYPE STANDARD TABLE OF lty_grp,
          ls_grp    TYPE lty_grp,
          lt_cat    TYPE SORTED TABLE OF lty_cat WITH UNIQUE KEY bstyp,
          ls_cat    TYPE lty_cat,
          lv_sub    TYPE c LENGTH 30,
          lv_orders TYPE ty_num,
          lv_total  TYPE ty_num.

    CLEAR: mt_lifnr_mm, mt_ekorg_used, mt_waers_mm, mv_mm_vend_ok.
    SELECT bstyp lifnr ekorg waers COUNT( * ) FROM ekko INTO TABLE lt_grp
      PACKAGE SIZE 50000
      WHERE aedat BETWEEN mv_datfr AND mv_datto
      GROUP BY bstyp lifnr ekorg waers.
      LOOP AT lt_grp INTO ls_grp.
        ls_cat-bstyp = ls_grp-bstyp.
        ls_cat-cnt   = ls_grp-cnt.
        COLLECT ls_cat INTO lt_cat.
        IF ls_grp-bstyp = 'F'.
          IF ls_grp-lifnr IS NOT INITIAL.
            INSERT ls_grp-lifnr INTO TABLE mt_lifnr_mm.
          ENDIF.
          INSERT ls_grp-ekorg INTO TABLE mt_ekorg_used.
          INSERT ls_grp-waers INTO TABLE mt_waers_mm.
        ENDIF.
      ENDLOOP.
    ENDSELECT.

    LOOP AT lt_cat INTO ls_cat.
      lv_total = lv_total + ls_cat-cnt.
      IF ls_cat-bstyp = 'F'.
        lv_orders = ls_cat-cnt.
      ENDIF.
      lv_sub = ls_cat-bstyp.
      IF lv_sub IS INITIAL.
        lv_sub = '-'.                           " sub key space is the header row
      ENDIF.
      set_c( iv_fkey = 'D10' iv_sub = lv_sub iv_total = ls_cat-cnt ).
    ENDLOOP.
    set_c( iv_fkey = 'Q15' iv_total = lv_orders ).
    set_c( iv_fkey = 'D10' iv_total = lv_total ).
    mv_mm_vend_ok = gc_x.
  ENDMETHOD.

* Row 15 B: open purchase orders today = distinct purchase orders with at least
* one item of category F without delivery-completed and deletion indicator
  METHOD step_mm_ekpo.
    DATA: lv_cnt  TYPE i,
          lv_open TYPE ty_num.

    SELECT COUNT( DISTINCT ebeln ) FROM ekpo INTO lv_cnt
      WHERE bstyp = 'F'
        AND elikz = space
        AND loekz = space.
    lv_open = lv_cnt.
    set_b( iv_fkey = 'Q15' iv_val = lv_open ).
  ENDMETHOD.

* Detail D11: vendor invoices of logistics invoice verification entered in the
* period (RBKP-CPUDT), status posted (RBSTAT 5, SAP-defined)
  METHOD step_mm_rbkp.
    DATA: lv_cnt   TYPE i,
          lv_total TYPE ty_num.

    SELECT COUNT( * ) FROM rbkp INTO lv_cnt
      WHERE cpudt BETWEEN mv_datfr AND mv_datto
        AND rbstat = '5'.
    lv_total = lv_cnt.
    set_c( iv_fkey = 'D11' iv_total = lv_total ).
  ENDMETHOD.

* Details D12 and D04: material documents entered in the period (MKPF-CPUDT)
* and the distinct materials of their items (MSEG by document key). One pass
* over MKPF in packages; FOR ALL ENTRIES only with a non-empty driver and
* removes duplicate materials per package itself
  METHOD step_mm_mkpf.
    TYPES: BEGIN OF lty_doc,
             mblnr TYPE mkpf-mblnr,
             mjahr TYPE mkpf-mjahr,
           END OF lty_doc.
    DATA: lt_doc   TYPE STANDARD TABLE OF lty_doc,
          lt_matnr TYPE STANDARD TABLE OF matnr,
          lv_matnr TYPE matnr,
          lt_mat   TYPE HASHED TABLE OF matnr WITH UNIQUE KEY table_line,
          lv_lines TYPE i,
          lv_docs  TYPE ty_num,
          lv_mats  TYPE ty_num.

    SELECT mblnr mjahr FROM mkpf INTO TABLE lt_doc
      PACKAGE SIZE 5000
      WHERE cpudt BETWEEN mv_datfr AND mv_datto.
      DESCRIBE TABLE lt_doc LINES lv_lines.
      lv_docs = lv_docs + lv_lines.
      IF lv_lines > 0.
        SELECT matnr FROM mseg INTO TABLE lt_matnr
          FOR ALL ENTRIES IN lt_doc
          WHERE mblnr = lt_doc-mblnr
            AND mjahr = lt_doc-mjahr.
        LOOP AT lt_matnr INTO lv_matnr.
          IF lv_matnr IS NOT INITIAL.
            INSERT lv_matnr INTO TABLE lt_mat.
          ENDIF.
        ENDLOOP.
      ENDIF.
    ENDSELECT.
    DESCRIBE TABLE lt_mat LINES lv_lines.
    lv_mats = lv_lines.
    set_c( iv_fkey = 'D12' iv_total = lv_docs ).
    set_b( iv_fkey = 'D04' iv_val = lv_mats ).    " distinct count over the period, no average
  ENDMETHOD.

* Detail D16: WM transfer orders created in the period (LTAK-BDATU)
  METHOD step_mm_ltak.
    DATA: lv_cnt   TYPE i,
          lv_total TYPE ty_num.

    SELECT COUNT( * ) FROM ltak INTO lv_cnt
      WHERE bdatu BETWEEN mv_datfr AND mv_datto.
    lv_total = lv_cnt.
    set_c( iv_fkey = 'D16' iv_total = lv_total ).
  ENDMETHOD.

* Row 26: distinct WM warehouse numbers assigned to a plant / storage location
* (T320, customizing: read completely, aggregated in ABAP). Without WM: 0
  METHOD step_mm_t320.
    DATA: lt_lgnum TYPE STANDARD TABLE OF lgnum,
          lv_lines TYPE i,
          lv_whs   TYPE ty_num.

    SELECT lgnum FROM t320 INTO TABLE lt_lgnum.
    DELETE lt_lgnum WHERE table_line IS INITIAL.
    SORT lt_lgnum.
    DELETE ADJACENT DUPLICATES FROM lt_lgnum.
    DESCRIBE TABLE lt_lgnum LINES lv_lines.
    lv_whs = lv_lines.
    set_b( iv_fkey = 'Q26' iv_val = lv_whs ).
  ENDMETHOD.

* Rows 24 and 25, details D13 and D14: one pass over the production, process
* and maintenance orders (AUFK order categories 10, 40, 30; SAP-defined) in
* packages. Created = AUFK-ERDAT in the period. Open = none of the system
* statuses DLV (I0012), TECO (I0045), CLSD (I0046), DLFL (I0076) active in JEST
* (SAP-delivered status IDs, design 2 #2); JEST is read by FOR ALL ENTRIES
* per package of order object numbers. Also collects the plants with
* production or process orders created in the period (plant view, design 10)
  METHOD step_pp_aufk.
    TYPES: BEGIN OF lty_order,
             objnr TYPE aufk-objnr,
             autyp TYPE aufk-autyp,
             werks TYPE aufk-werks,
             erdat TYPE aufk-erdat,
           END OF lty_order,
           BEGIN OF lty_jest,
             objnr TYPE jest-objnr,
           END OF lty_jest,
           BEGIN OF lty_cat,
             autyp   TYPE aufk-autyp,
             cnt_open TYPE ty_num,
             cnt_new  TYPE ty_num,
           END OF lty_cat.
    DATA: lt_order  TYPE STANDARD TABLE OF lty_order,
          ls_order  TYPE lty_order,
          lt_jest   TYPE STANDARD TABLE OF lty_jest,
          ls_jest   TYPE lty_jest,
          lt_closed TYPE HASHED TABLE OF j_objnr WITH UNIQUE KEY table_line,
          lt_cat    TYPE SORTED TABLE OF lty_cat WITH UNIQUE KEY autyp,
          ls_cat    TYPE lty_cat,
          lv_lines  TYPE i,
          lv_sub    TYPE c LENGTH 30,
          lv_open   TYPE ty_num,
          lv_new    TYPE ty_num,
          lv_open_m TYPE ty_num,
          lv_new_m  TYPE ty_num.

    CLEAR: mt_werks_manuf, mv_pp_manuf_ok.
    SELECT objnr autyp werks erdat FROM aufk INTO TABLE lt_order
      PACKAGE SIZE 5000
      WHERE autyp IN ('10', '30', '40').
      DESCRIBE TABLE lt_order LINES lv_lines.
      CLEAR lt_closed.
      IF lv_lines > 0.
        SELECT objnr FROM jest INTO TABLE lt_jest
          FOR ALL ENTRIES IN lt_order
          WHERE objnr = lt_order-objnr
            AND stat  IN ('I0012', 'I0045', 'I0046', 'I0076')
            AND inact = space.
        LOOP AT lt_jest INTO ls_jest.
          INSERT ls_jest-objnr INTO TABLE lt_closed.
        ENDLOOP.
      ENDIF.
      LOOP AT lt_order INTO ls_order.
        CLEAR ls_cat.
        ls_cat-autyp = ls_order-autyp.
        READ TABLE lt_closed TRANSPORTING NO FIELDS WITH TABLE KEY table_line = ls_order-objnr.
        IF sy-subrc <> 0.
          ls_cat-cnt_open = 1.
        ENDIF.
        IF ls_order-erdat BETWEEN mv_datfr AND mv_datto.
          ls_cat-cnt_new = 1.
          IF ls_order-autyp <> '30' AND ls_order-werks IS NOT INITIAL.
            INSERT ls_order-werks INTO TABLE mt_werks_manuf.
          ENDIF.
        ENDIF.
        COLLECT ls_cat INTO lt_cat.
      ENDLOOP.
    ENDSELECT.

    LOOP AT lt_cat INTO ls_cat.
      IF ls_cat-autyp = '30'.
        lv_open_m = ls_cat-cnt_open.
        lv_new_m  = ls_cat-cnt_new.
      ELSE.
        lv_open = lv_open + ls_cat-cnt_open.
        lv_new  = lv_new + ls_cat-cnt_new.
        lv_sub  = ls_cat-autyp.
        set_b( iv_fkey = 'D13' iv_sub = lv_sub iv_val = ls_cat-cnt_open ).
        set_c( iv_fkey = 'D13' iv_sub = lv_sub iv_total = ls_cat-cnt_new ).
      ENDIF.
    ENDLOOP.
    set_b( iv_fkey = 'Q24' iv_val = lv_open ).
    set_c( iv_fkey = 'Q24' iv_total = lv_new ).
    set_b( iv_fkey = 'D13' iv_val = lv_open ).
    set_c( iv_fkey = 'D13' iv_total = lv_new ).
    set_c( iv_fkey = 'Q25' iv_total = lv_new_m ).
    set_b( iv_fkey = 'D14' iv_val = lv_open_m ).
    mv_pp_manuf_ok = gc_x.
  ENDMETHOD.

* Detail D15: inspection lots created in the period (QALS-ENSTEHDAT)
  METHOD step_pp_qals.
    DATA: lv_cnt   TYPE i,
          lv_total TYPE ty_num.

    SELECT COUNT( * ) FROM qals INTO lv_cnt
      WHERE enstehdat BETWEEN mv_datfr AND mv_datto.
    lv_total = lv_cnt.
    set_c( iv_fkey = 'D15' iv_total = lv_total ).
  ENDMETHOD.

* Detail D18: work centers (CRHD object type A, SAP-defined) of the plants
* counted in row 27
  METHOD step_pp_crhd.
    TYPES: BEGIN OF lty_crhd,
             werks TYPE crhd-werks,
           END OF lty_crhd.
    DATA: lt_crhd TYPE STANDARD TABLE OF lty_crhd,
          ls_crhd TYPE lty_crhd,
          lv_cnt  TYPE ty_num.

    IF mv_base_ok IS INITIAL.
      RETURN.
    ENDIF.
    counted_plants( ).
    SELECT werks FROM crhd INTO TABLE lt_crhd
      WHERE objty = 'A'.
    LOOP AT lt_crhd INTO ls_crhd.
      READ TABLE mt_werks_cnt TRANSPORTING NO FIELDS WITH TABLE KEY table_line = ls_crhd-werks.
      IF sy-subrc = 0.
        lv_cnt = lv_cnt + 1.
      ENDIF.
    ENDLOOP.
    set_b( iv_fkey = 'D18' iv_val = lv_cnt ).
  ENDMETHOD.

* Plants counted in row 27: plants (T001W) whose valuation area belongs to an
* active company code (T001K). Customizing, read completely; computed once
  METHOD counted_plants.
    TYPES: BEGIN OF lty_t001w,
             werks TYPE t001w-werks,
             bwkey TYPE t001w-bwkey,
           END OF lty_t001w,
           BEGIN OF lty_t001k,
             bwkey TYPE t001k-bwkey,
             bukrs TYPE t001k-bukrs,
           END OF lty_t001k.
    DATA: lt_t001w TYPE STANDARD TABLE OF lty_t001w,
          ls_t001w TYPE lty_t001w,
          lt_t001k TYPE SORTED TABLE OF lty_t001k WITH UNIQUE KEY bwkey,
          ls_t001k TYPE lty_t001k.

    IF mv_werks_cnt_ok = gc_x.
      RETURN.
    ENDIF.
    CLEAR mt_werks_cnt.
    SELECT werks bwkey FROM t001w INTO TABLE lt_t001w.
    SELECT bwkey bukrs FROM t001k INTO TABLE lt_t001k.
    LOOP AT lt_t001w INTO ls_t001w.
      READ TABLE lt_t001k INTO ls_t001k WITH TABLE KEY bwkey = ls_t001w-bwkey.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      READ TABLE mt_bukrs_act TRANSPORTING NO FIELDS WITH TABLE KEY table_line = ls_t001k-bukrs.
      IF sy-subrc = 0.
        INSERT ls_t001w-werks INTO TABLE mt_werks_cnt.
      ENDIF.
    ENDLOOP.
    mv_werks_cnt_ok = gc_x.
  ENDMETHOD.

* Row 27, detail D17 and the plant view (design 10): all plants with name,
* country, city and the company code of their valuation area. Counted = plant
* of an active company code (row 27). Manufacturing = production or process
* orders created for the plant in the period (blank if block PP was skipped)
  METHOD step_org_plants.
    TYPES: BEGIN OF lty_t001w,
             werks TYPE t001w-werks,
             name1 TYPE t001w-name1,
             land1 TYPE t001w-land1,
             ort01 TYPE t001w-ort01,
             bwkey TYPE t001w-bwkey,
           END OF lty_t001w,
           BEGIN OF lty_t001k,
             bwkey TYPE t001k-bwkey,
             bukrs TYPE t001k-bukrs,
           END OF lty_t001k,
           BEGIN OF lty_t001l,
             werks TYPE t001l-werks,
             lgort TYPE t001l-lgort,
           END OF lty_t001l.
    DATA: lt_t001w  TYPE STANDARD TABLE OF lty_t001w,
          ls_t001w  TYPE lty_t001w,
          lt_t001k  TYPE SORTED TABLE OF lty_t001k WITH UNIQUE KEY bwkey,
          ls_t001k  TYPE lty_t001k,
          lt_t001l  TYPE STANDARD TABLE OF lty_t001l,
          ls_t001l  TYPE lty_t001l,
          ls_plant  TYPE ty_plant,
          lv_plants TYPE ty_num,
          lv_slocs  TYPE ty_num.

    IF mv_base_ok IS INITIAL.
      RETURN.
    ENDIF.
    counted_plants( ).
    CLEAR ms_res-plants.
    SELECT werks name1 land1 ort01 bwkey FROM t001w INTO TABLE lt_t001w.
    SELECT bwkey bukrs FROM t001k INTO TABLE lt_t001k.
    SORT lt_t001w BY werks.
    LOOP AT lt_t001w INTO ls_t001w.
      CLEAR: ls_plant, ls_t001k.
      ls_plant-werks = ls_t001w-werks.
      ls_plant-name1 = ls_t001w-name1.
      ls_plant-land1 = ls_t001w-land1.
      ls_plant-ort01 = ls_t001w-ort01.
      READ TABLE lt_t001k INTO ls_t001k WITH TABLE KEY bwkey = ls_t001w-bwkey.
      ls_plant-bukrs = ls_t001k-bukrs.
      READ TABLE mt_werks_cnt TRANSPORTING NO FIELDS WITH TABLE KEY table_line = ls_t001w-werks.
      IF sy-subrc = 0.
        ls_plant-counted = gc_x.
        lv_plants = lv_plants + 1.
      ENDIF.
      IF mv_pp_manuf_ok = gc_x.
        READ TABLE mt_werks_manuf TRANSPORTING NO FIELDS WITH TABLE KEY table_line = ls_t001w-werks.
        IF sy-subrc = 0.
          ls_plant-manuf = gc_x.
        ENDIF.
      ENDIF.
      APPEND ls_plant TO ms_res-plants.
    ENDLOOP.

    SELECT werks lgort FROM t001l INTO TABLE lt_t001l.
    LOOP AT lt_t001l INTO ls_t001l.
      READ TABLE mt_werks_cnt TRANSPORTING NO FIELDS WITH TABLE KEY table_line = ls_t001l-werks.
      IF sy-subrc = 0.
        lv_slocs = lv_slocs + 1.
      ENDIF.
    ENDLOOP.

    set_b( iv_fkey = 'Q27' iv_val = lv_plants ).
    set_b( iv_fkey = 'D17' iv_val = lv_slocs ).
  ENDMETHOD.

* Row 23 and details D22-D24. B = configured EDI message flows with business
* partners: partner profile message lines outbound (EDP13) and inbound (EDP21)
* without logical systems (partner type LS, SAP-defined). C and details: IDocs
* created in the period (EDIDC-CREDAT), one aggregated pass; the partner is the
* receiver for outbound (direction 1) and the sender for inbound (direction 2)
  METHOD step_org_edi.
    TYPES: BEGIN OF lty_grp,
             direct TYPE edidc-direct,
             rcvprt TYPE edidc-rcvprt,
             sndprt TYPE edidc-sndprt,
             mestyp TYPE edidc-mestyp,
             cnt    TYPE i,
           END OF lty_grp,
           BEGIN OF lty_part,
             direct TYPE edidc-direct,
             prt    TYPE edidc-rcvprt,
             cnt    TYPE ty_num,
           END OF lty_part,
           BEGIN OF lty_mes,
             mestyp TYPE edidc-mestyp,
             cnt    TYPE ty_num,
           END OF lty_mes.
    DATA: lt_grp   TYPE STANDARD TABLE OF lty_grp,
          ls_grp   TYPE lty_grp,
          lt_part  TYPE SORTED TABLE OF lty_part WITH UNIQUE KEY direct prt,
          ls_part  TYPE lty_part,
          lt_mes   TYPE SORTED TABLE OF lty_mes WITH UNIQUE KEY mestyp,
          lt_top   TYPE STANDARD TABLE OF lty_mes,
          ls_mes   TYPE lty_mes,
          lv_cnt   TYPE i,
          lv_sub   TYPE c LENGTH 30,
          lv_prof  TYPE ty_num,
          lv_edi   TYPE ty_num,
          lv_ale   TYPE ty_num,
          lv_total TYPE ty_num.

    SELECT COUNT( * ) FROM edp13 INTO lv_cnt
      WHERE rcvprt <> 'LS'.
    lv_prof = lv_cnt.
    SELECT COUNT( * ) FROM edp21 INTO lv_cnt
      WHERE sndprt <> 'LS'.
    lv_prof = lv_prof + lv_cnt.

    SELECT direct rcvprt sndprt mestyp COUNT( * ) FROM edidc INTO TABLE lt_grp
      WHERE credat BETWEEN mv_datfr AND mv_datto
      GROUP BY direct rcvprt sndprt mestyp.
    LOOP AT lt_grp INTO ls_grp.
      CLEAR ls_part.
      ls_part-direct = ls_grp-direct.
      IF ls_grp-direct = '1'.
        ls_part-prt = ls_grp-rcvprt.
      ELSE.
        ls_part-prt = ls_grp-sndprt.
      ENDIF.
      ls_part-cnt = ls_grp-cnt.
      COLLECT ls_part INTO lt_part.
      lv_total = lv_total + ls_part-cnt.
      IF ls_part-prt = 'LS'.
        lv_ale = lv_ale + ls_part-cnt.
      ELSE.
        lv_edi = lv_edi + ls_part-cnt.
      ENDIF.
      ls_mes-mestyp = ls_grp-mestyp.
      ls_mes-cnt    = ls_grp-cnt.
      COLLECT ls_mes INTO lt_mes.
    ENDLOOP.

    LOOP AT lt_part INTO ls_part.
      CONCATENATE ls_part-direct '/' ls_part-prt INTO lv_sub.
      set_c( iv_fkey = 'D22' iv_sub = lv_sub iv_total = ls_part-cnt ).
    ENDLOOP.
    set_c( iv_fkey = 'D22' iv_total = lv_total ).
    set_c( iv_fkey = 'D23' iv_total = lv_ale ).

* Top 10 message types by number of IDocs; the header holds all IDocs
    lt_top = lt_mes.
    SORT lt_top BY cnt DESCENDING mestyp ASCENDING.
    LOOP AT lt_top INTO ls_mes.
      IF sy-tabix > 10.
        EXIT.
      ENDIF.
      lv_sub = ls_mes-mestyp.
      IF lv_sub IS INITIAL.
        lv_sub = '-'.
      ENDIF.
      set_c( iv_fkey = 'D24' iv_sub = lv_sub iv_total = ls_mes-cnt ).
    ENDLOOP.
    set_c( iv_fkey = 'D24' iv_total = lv_total ).

    set_b( iv_fkey = 'Q23' iv_val = lv_prof ).
    set_c( iv_fkey = 'Q23' iv_total = lv_edi ).
  ENDMETHOD.

* Row 28 and details D25/D26 from the logon data (USR02), without user names
* (design 2 #13). Valid today: GLTGV/GLTGB initial or around today. Not locked
* by an administrator: UFLAG 0, or only the failed-logon lock 128. User types
* and lock values are SAP-defined
  METHOD step_org_users.
    TYPES: BEGIN OF lty_usr,
             ustyp TYPE usr02-ustyp,
             uflag TYPE usr02-uflag,
             gltgv TYPE usr02-gltgv,
             gltgb TYPE usr02-gltgb,
             trdat TYPE usr02-trdat,
             erdat TYPE usr02-erdat,
           END OF lty_usr,
           BEGIN OF lty_typ,
             ustyp TYPE usr02-ustyp,
             cnt   TYPE ty_num,
           END OF lty_typ.
    DATA: lt_usr    TYPE STANDARD TABLE OF lty_usr,
          ls_usr    TYPE lty_usr,
          lt_typ    TYPE SORTED TABLE OF lty_typ WITH UNIQUE KEY ustyp,
          ls_typ    TYPE lty_typ,
          lv_valid  TYPE ty_flag,
          lv_sub    TYPE c LENGTH 30,
          lv_active TYPE ty_num,
          lv_new    TYPE ty_num,
          lv_dialog TYPE ty_num,
          lv_total  TYPE ty_num.

    SELECT ustyp uflag gltgv gltgb trdat erdat FROM usr02 INTO TABLE lt_usr.
    LOOP AT lt_usr INTO ls_usr.
      lv_valid = gc_x.
      IF ls_usr-gltgv IS NOT INITIAL AND ls_usr-gltgv > sy-datum.
        CLEAR lv_valid.
      ENDIF.
      IF ls_usr-gltgb IS NOT INITIAL AND ls_usr-gltgb < sy-datum.
        CLEAR lv_valid.
      ENDIF.
      IF lv_valid = gc_x.
        lv_total     = lv_total + 1.
        ls_typ-ustyp = ls_usr-ustyp.
        ls_typ-cnt   = 1.
        COLLECT ls_typ INTO lt_typ.
        IF ls_usr-ustyp = 'A' AND ( ls_usr-uflag = 0 OR ls_usr-uflag = 128 ).
          lv_dialog = lv_dialog + 1.
          IF ls_usr-trdat >= mv_datfr.
            lv_active = lv_active + 1.
          ENDIF.
        ENDIF.
      ENDIF.
      IF ls_usr-ustyp = 'A' AND ls_usr-erdat BETWEEN mv_datfr AND mv_datto.
        lv_new = lv_new + 1.
      ENDIF.
    ENDLOOP.

    LOOP AT lt_typ INTO ls_typ.
      lv_sub = ls_typ-ustyp.
      IF lv_sub IS INITIAL.
        lv_sub = '-'.
      ENDIF.
      set_b( iv_fkey = 'D25' iv_sub = lv_sub iv_val = ls_typ-cnt ).
    ENDLOOP.
    set_b( iv_fkey = 'D25' iv_val = lv_total ).
    set_b( iv_fkey = 'D26' iv_val = lv_dialog ).
    set_b( iv_fkey = 'Q28' iv_val = lv_active ).
    set_c( iv_fkey = 'Q28' iv_total = lv_new ).
  ENDMETHOD.

* Organization view (design 9): purchasing organizations (T024E), sales
* organizations (TVKO), distribution channels (TVTW) and divisions (TSPA) with
* their texts in the logon language of the collection run. "Used" comes from the
* purchase orders (block MM) and sales orders (block SD) created in the period.
* If that source is missing, the rows show "error" when its step failed and
* "not collected" when its block was skipped
  METHOD step_org_units.
    TYPES: BEGIN OF lty_t024e,
             ekorg TYPE t024e-ekorg,
             ekotx TYPE t024e-ekotx,
             bukrs TYPE t024e-bukrs,
           END OF lty_t024e,
           BEGIN OF lty_tvko,
             vkorg TYPE tvko-vkorg,
             bukrs TYPE tvko-bukrs,
           END OF lty_tvko,
           BEGIN OF lty_tvkot,
             vkorg TYPE tvkot-vkorg,
             vtext TYPE tvkot-vtext,
           END OF lty_tvkot,
           BEGIN OF lty_tvtwt,
             vtweg TYPE tvtwt-vtweg,
             vtext TYPE tvtwt-vtext,
           END OF lty_tvtwt,
           BEGIN OF lty_tspat,
             spart TYPE tspat-spart,
             vtext TYPE tspat-vtext,
           END OF lty_tspat.
    DATA: lt_t024e TYPE STANDARD TABLE OF lty_t024e,
          ls_t024e TYPE lty_t024e,
          lt_tvko  TYPE STANDARD TABLE OF lty_tvko,
          ls_tvko  TYPE lty_tvko,
          lt_tvkot TYPE SORTED TABLE OF lty_tvkot WITH UNIQUE KEY vkorg,
          ls_tvkot TYPE lty_tvkot,
          lt_vtweg TYPE STANDARD TABLE OF vtweg,
          lv_vtweg TYPE vtweg,
          lt_tvtwt TYPE SORTED TABLE OF lty_tvtwt WITH UNIQUE KEY vtweg,
          ls_tvtwt TYPE lty_tvtwt,
          lt_spart TYPE STANDARD TABLE OF spart,
          lv_spart TYPE spart,
          lt_tspat TYPE SORTED TABLE OF lty_tspat WITH UNIQUE KEY spart,
          ls_tspat TYPE lty_tspat,
          ls_org   TYPE ty_org,
          lv_st_mm TYPE ty_flag,
          lv_st_sd TYPE ty_flag.

    DELETE ms_res-orgs WHERE grp <> 'A'.
    lv_st_mm = src_status( 'MM_EKKO' ).
    lv_st_sd = src_status( 'SD_VBAK' ).

    SELECT ekorg ekotx bukrs FROM t024e INTO TABLE lt_t024e.
    SORT lt_t024e BY ekorg.
    LOOP AT lt_t024e INTO ls_t024e.
      CLEAR ls_org.
      ls_org-grp   = 'P'.
      ls_org-okey  = ls_t024e-ekorg.
      ls_org-otext = ls_t024e-ekotx.
      ls_org-bukrs = ls_t024e-bukrs.
      IF mv_mm_vend_ok = gc_x.
        ls_org-status = gc_st_ok.
        READ TABLE mt_ekorg_used TRANSPORTING NO FIELDS WITH TABLE KEY table_line = ls_t024e-ekorg.
        IF sy-subrc = 0.
          ls_org-used = gc_x.
        ENDIF.
      ELSE.
        ls_org-status = lv_st_mm.
      ENDIF.
      APPEND ls_org TO ms_res-orgs.
    ENDLOOP.

    SELECT vkorg bukrs FROM tvko INTO TABLE lt_tvko.
    SELECT vkorg vtext FROM tvkot INTO TABLE lt_tvkot
      WHERE spras = sy-langu.
    SORT lt_tvko BY vkorg.
    LOOP AT lt_tvko INTO ls_tvko.
      CLEAR: ls_org, ls_tvkot.
      ls_org-grp   = 'S'.
      ls_org-okey  = ls_tvko-vkorg.
      READ TABLE lt_tvkot INTO ls_tvkot WITH TABLE KEY vkorg = ls_tvko-vkorg.
      ls_org-otext = ls_tvkot-vtext.
      ls_org-bukrs = ls_tvko-bukrs.
      IF mv_sd_cust_ok = gc_x.
        ls_org-status = gc_st_ok.
        READ TABLE mt_vkorg_used TRANSPORTING NO FIELDS WITH TABLE KEY table_line = ls_tvko-vkorg.
        IF sy-subrc = 0.
          ls_org-used = gc_x.
        ENDIF.
      ELSE.
        ls_org-status = lv_st_sd.
      ENDIF.
      APPEND ls_org TO ms_res-orgs.
    ENDLOOP.

    SELECT vtweg FROM tvtw INTO TABLE lt_vtweg.
    SELECT vtweg vtext FROM tvtwt INTO TABLE lt_tvtwt
      WHERE spras = sy-langu.
    SORT lt_vtweg.
    LOOP AT lt_vtweg INTO lv_vtweg.
      CLEAR: ls_org, ls_tvtwt.
      ls_org-grp  = 'D'.
      ls_org-okey = lv_vtweg.
      READ TABLE lt_tvtwt INTO ls_tvtwt WITH TABLE KEY vtweg = lv_vtweg.
      ls_org-otext = ls_tvtwt-vtext.
      IF mv_sd_cust_ok = gc_x.
        ls_org-status = gc_st_ok.
        READ TABLE mt_vtweg_used TRANSPORTING NO FIELDS WITH TABLE KEY table_line = lv_vtweg.
        IF sy-subrc = 0.
          ls_org-used = gc_x.
        ENDIF.
      ELSE.
        ls_org-status = lv_st_sd.
      ENDIF.
      APPEND ls_org TO ms_res-orgs.
    ENDLOOP.

    SELECT spart FROM tspa INTO TABLE lt_spart.
    SELECT spart vtext FROM tspat INTO TABLE lt_tspat
      WHERE spras = sy-langu.
    SORT lt_spart.
    LOOP AT lt_spart INTO lv_spart.
      CLEAR: ls_org, ls_tspat.
      ls_org-grp  = 'V'.
      ls_org-okey = lv_spart.
      READ TABLE lt_tspat INTO ls_tspat WITH TABLE KEY spart = lv_spart.
      ls_org-otext = ls_tspat-vtext.
      IF mv_sd_cust_ok = gc_x.
        ls_org-status = gc_st_ok.
        READ TABLE mt_spart_used TRANSPORTING NO FIELDS WITH TABLE KEY table_line = lv_spart.
        IF sy-subrc = 0.
          ls_org-used = gc_x.
        ENDIF.
      ELSE.
        ls_org-status = lv_st_sd.
      ENDIF.
      APPEND ls_org TO ms_res-orgs.
    ENDLOOP.
  ENDMETHOD.

* Interfaces view (design 11): RFC destinations with name and connection type
* only; connection options (host, user) are not read. Each INTF step collects
* into a local table and appends it at the end, so a failure leaves no partial
* list (view 5 then shows "error" for the object type)
  METHOD step_intf_rfc.
    TYPES: BEGIN OF lty_rfc,
             rfcdest TYPE rfcdes-rfcdest,
             rfctype TYPE rfcdes-rfctype,
           END OF lty_rfc.
    DATA: lt_rfc  TYPE STANDARD TABLE OF lty_rfc,
          ls_rfc  TYPE lty_rfc,
          lt_intf TYPE ty_intf_t,
          ls_intf TYPE ty_intf.

    SELECT rfcdest rfctype FROM rfcdes INTO TABLE lt_rfc.
    SORT lt_rfc BY rfcdest.
    LOOP AT lt_rfc INTO ls_rfc.
      CLEAR ls_intf.
      ls_intf-otype = 'R'.
      ls_intf-name  = ls_rfc-rfcdest.
      ls_intf-itype = ls_rfc-rfctype.
      APPEND ls_intf TO lt_intf.
    ENDLOOP.
    APPEND LINES OF lt_intf TO ms_res-intfs.
  ENDMETHOD.

* Logical systems (TBDLS) with their text in the logon language of the run
  METHOD step_intf_logsys.
    TYPES: BEGIN OF lty_text,
             logsys TYPE tbdlst-logsys,
             stext  TYPE tbdlst-stext,
           END OF lty_text.
    DATA: lt_logsys TYPE STANDARD TABLE OF logsys,
          lv_logsys TYPE logsys,
          lt_text   TYPE SORTED TABLE OF lty_text WITH UNIQUE KEY logsys,
          ls_text   TYPE lty_text,
          lt_intf   TYPE ty_intf_t,
          ls_intf   TYPE ty_intf.

    SELECT logsys FROM tbdls INTO TABLE lt_logsys.
    SELECT logsys stext FROM tbdlst INTO TABLE lt_text
      WHERE langu = sy-langu.
    SORT lt_logsys.
    LOOP AT lt_logsys INTO lv_logsys.
      CLEAR: ls_intf, ls_text.
      ls_intf-otype = 'L'.
      ls_intf-name  = lv_logsys.
      READ TABLE lt_text INTO ls_text WITH TABLE KEY logsys = lv_logsys.
      ls_intf-descr = ls_text-stext.
      APPEND ls_intf TO lt_intf.
    ENDLOOP.
    APPEND LINES OF lt_intf TO ms_res-intfs.
  ENDMETHOD.

* Partner profiles (EDPP1) with the IDocs created in the period per partner
* (EDIDC-CREDAT, one aggregated pass). The partner is the receiver for outbound
* (direction 1) and the sender for inbound IDocs (direction 2), as in row 23.
* Partners with IDocs but without a partner profile are listed as well
  METHOD step_intf_partner.
    TYPES: BEGIN OF lty_prof,
             parnum TYPE edpp1-parnum,
             partyp TYPE edpp1-partyp,
           END OF lty_prof,
           BEGIN OF lty_grp,
             direct TYPE edidc-direct,
             rcvprn TYPE edidc-rcvprn,
             rcvprt TYPE edidc-rcvprt,
             sndprn TYPE edidc-sndprn,
             sndprt TYPE edidc-sndprt,
             cnt    TYPE i,
           END OF lty_grp,
           BEGIN OF lty_cnt,
             prt TYPE edidc-rcvprt,
             prn TYPE edidc-rcvprn,
             cnt TYPE ty_num,
           END OF lty_cnt,
           BEGIN OF lty_text,
             logsys TYPE tbdlst-logsys,
             stext  TYPE tbdlst-stext,
           END OF lty_text.
    DATA: lt_prof   TYPE STANDARD TABLE OF lty_prof,
          ls_prof   TYPE lty_prof,
          lt_grp    TYPE STANDARD TABLE OF lty_grp,
          ls_grp    TYPE lty_grp,
          lt_cnt    TYPE SORTED TABLE OF lty_cnt WITH UNIQUE KEY prt prn,
          ls_cnt    TYPE lty_cnt,
          lt_text   TYPE SORTED TABLE OF lty_text WITH UNIQUE KEY logsys,
          ls_text   TYPE lty_text,
          lv_logsys TYPE tbdlst-logsys,
          lt_intf   TYPE ty_intf_t,
          ls_intf   TYPE ty_intf.

    SELECT direct rcvprn rcvprt sndprn sndprt COUNT( * ) FROM edidc INTO TABLE lt_grp
      WHERE credat BETWEEN mv_datfr AND mv_datto
      GROUP BY direct rcvprn rcvprt sndprn sndprt.
    LOOP AT lt_grp INTO ls_grp.
      CLEAR ls_cnt.
      IF ls_grp-direct = '1'.
        ls_cnt-prt = ls_grp-rcvprt.
        ls_cnt-prn = ls_grp-rcvprn.
      ELSE.
        ls_cnt-prt = ls_grp-sndprt.
        ls_cnt-prn = ls_grp-sndprn.
      ENDIF.
      ls_cnt-cnt = ls_grp-cnt.
      COLLECT ls_cnt INTO lt_cnt.
    ENDLOOP.

    SELECT parnum partyp FROM edpp1 INTO TABLE lt_prof.
    SELECT logsys stext FROM tbdlst INTO TABLE lt_text
      WHERE langu = sy-langu.
    LOOP AT lt_prof INTO ls_prof.
      CLEAR: ls_intf, ls_cnt.
      ls_intf-otype = 'P'.
      ls_intf-name  = ls_prof-parnum.
      ls_intf-itype = ls_prof-partyp.
      READ TABLE lt_cnt INTO ls_cnt WITH TABLE KEY prt = ls_prof-partyp prn = ls_prof-parnum.
      IF sy-subrc = 0.
        ls_intf-idocs = ls_cnt-cnt.
        DELETE TABLE lt_cnt WITH TABLE KEY prt = ls_prof-partyp prn = ls_prof-parnum.
      ENDIF.
      APPEND ls_intf TO lt_intf.
    ENDLOOP.
* Remaining counts: IDocs of partners without a partner profile
    LOOP AT lt_cnt INTO ls_cnt.
      CLEAR ls_intf.
      ls_intf-otype  = 'P'.
      ls_intf-name   = ls_cnt-prn.
      ls_intf-itype  = ls_cnt-prt.
      ls_intf-idocs  = ls_cnt-cnt.
      ls_intf-noprof = gc_x.
      APPEND ls_intf TO lt_intf.
    ENDLOOP.

* Text of logical systems (partner type LS, SAP-defined)
    LOOP AT lt_intf INTO ls_intf WHERE itype = 'LS'.
      CLEAR ls_text.
      lv_logsys = ls_intf-name.
      READ TABLE lt_text INTO ls_text WITH TABLE KEY logsys = lv_logsys.
      IF sy-subrc = 0.
        ls_intf-descr = ls_text-stext.
        MODIFY lt_intf FROM ls_intf TRANSPORTING descr.
      ENDIF.
    ENDLOOP.
    SORT lt_intf BY itype name.
    APPEND LINES OF lt_intf TO ms_res-intfs.
  ENDMETHOD.

* Installed software components (CVERS, System > Status) with release, support
* package level and text in the logon language of the run, else in English
  METHOD step_intf_cvers.
    TYPES: BEGIN OF lty_cvers,
             comp  TYPE cvers-component,
             rel   TYPE cvers-release,
             splev TYPE cvers-extrelease,
           END OF lty_cvers,
           BEGIN OF lty_ref,
             comp  TYPE cvers_ref-component,
             langu TYPE cvers_ref-langu,
             text  TYPE cvers_ref-desc_text,
           END OF lty_ref.
    DATA: lt_cvers TYPE STANDARD TABLE OF lty_cvers,
          ls_cvers TYPE lty_cvers,
          lt_ref   TYPE STANDARD TABLE OF lty_ref,
          ls_ref   TYPE lty_ref,
          lt_intf  TYPE ty_intf_t,
          ls_intf  TYPE ty_intf.

    SELECT component release extrelease FROM cvers INTO TABLE lt_cvers.
    SELECT component langu desc_text FROM cvers_ref INTO TABLE lt_ref
      WHERE langu = sy-langu
         OR langu = 'E'.
* Standard table: the key of CVERS_REF is not documented, duplicates are removed
    SORT lt_ref BY comp langu.
    DELETE ADJACENT DUPLICATES FROM lt_ref COMPARING comp langu.
    SORT lt_cvers BY comp.
    LOOP AT lt_cvers INTO ls_cvers.
      CLEAR ls_intf.
      ls_intf-otype = 'C'.
      ls_intf-name  = ls_cvers-comp.
      ls_intf-rel   = ls_cvers-rel.
      ls_intf-splev = ls_cvers-splev.
      READ TABLE lt_ref INTO ls_ref WITH KEY comp = ls_cvers-comp langu = sy-langu BINARY SEARCH.
      IF sy-subrc <> 0.
        READ TABLE lt_ref INTO ls_ref WITH KEY comp = ls_cvers-comp langu = 'E' BINARY SEARCH.
      ENDIF.
      IF sy-subrc = 0.
        ls_intf-descr = ls_ref-text.
      ENDIF.
      APPEND ls_intf TO lt_intf.
    ENDLOOP.
    APPEND LINES OF lt_intf TO ms_res-intfs.
  ENDMETHOD.

* G5 to G7 (design 9). Each line is set to "error" first, so that a failure in
* the middle of the step leaves an error and not a partial list. A line whose
* source is missing shows "error" if a source step failed and "not collected"
* if a source block was skipped
  METHOD step_derv_g567.
    TYPES: BEGIN OF lty_t001w,
             werks TYPE t001w-werks,
             land1 TYPE t001w-land1,
           END OF lty_t001w,
           BEGIN OF lty_t002,
             spras TYPE t002-spras,
             laiso TYPE t002-laiso,
           END OF lty_t002.
    DATA: lt_land  TYPE SORTED TABLE OF land1 WITH UNIQUE KEY table_line,
          lt_t001w TYPE STANDARD TABLE OF lty_t001w,
          ls_t001w TYPE lty_t001w,
          ls_t001  TYPE ty_t001,
          lt_kunnr TYPE STANDARD TABLE OF kunnr,
          lv_kunnr TYPE kunnr,
          lt_lifnr TYPE STANDARD TABLE OF lifnr,
          lv_lifnr TYPE lifnr,
          lt_spras TYPE STANDARD TABLE OF spras,
          lv_spras TYPE spras,
          lt_lang  TYPE SORTED TABLE OF spras WITH UNIQUE KEY table_line,
          lt_t002  TYPE SORTED TABLE OF lty_t002 WITH UNIQUE KEY spras,
          ls_t002  TYPE lty_t002,
          lt_iso   TYPE SORTED TABLE OF laiso WITH UNIQUE KEY table_line,
          lt_waers TYPE SORTED TABLE OF waers WITH UNIQUE KEY table_line,
          lv_waers TYPE waers,
          lv_land1 TYPE land1,
          lv_laiso TYPE laiso.

    ms_res-meta-g5_st = gc_st_err.
    ms_res-meta-g6_st = gc_st_err.
    ms_res-meta-g7_st = gc_st_err.
    CLEAR: ms_res-meta-g5, ms_res-meta-g6, ms_res-meta-g7.

* G5: countries of the active company codes and of the plants counted in row 27
    IF mv_base_ok = gc_x.
      counted_plants( ).
      LOOP AT mt_t001 INTO ls_t001.
        READ TABLE mt_bukrs_act TRANSPORTING NO FIELDS WITH TABLE KEY table_line = ls_t001-bukrs.
        IF sy-subrc = 0 AND ls_t001-land1 IS NOT INITIAL.
          INSERT ls_t001-land1 INTO TABLE lt_land.
        ENDIF.
      ENDLOOP.
      SELECT werks land1 FROM t001w INTO TABLE lt_t001w.
      LOOP AT lt_t001w INTO ls_t001w.
        READ TABLE mt_werks_cnt TRANSPORTING NO FIELDS WITH TABLE KEY table_line = ls_t001w-werks.
        IF sy-subrc = 0 AND ls_t001w-land1 IS NOT INITIAL.
          INSERT ls_t001w-land1 INTO TABLE lt_land.
        ENDIF.
      ENDLOOP.
      LOOP AT lt_land INTO lv_land1.
        add_to_list( EXPORTING iv_value = lv_land1 CHANGING cv_list = ms_res-meta-g5 ).
      ENDLOOP.
      ms_res-meta-g5_st = gc_st_ok.
    ELSE.
      ms_res-meta-g5_st = src_status( 'BASE_BUKRS' ).
    ENDIF.

* G6: correspondence languages of the active customers and vendors (rows 7 and
* 9) as ISO codes. FOR ALL ENTRIES returns each language once
    IF mv_fi_cust_ok = gc_x AND mv_sd_cust_ok = gc_x
      AND mv_fi_vend_ok = gc_x AND mv_mm_vend_ok = gc_x.
      LOOP AT mt_kunnr_fi INTO lv_kunnr.
        APPEND lv_kunnr TO lt_kunnr.
      ENDLOOP.
      LOOP AT mt_kunnr_sd INTO lv_kunnr.
        APPEND lv_kunnr TO lt_kunnr.
      ENDLOOP.
      SORT lt_kunnr.
      DELETE ADJACENT DUPLICATES FROM lt_kunnr.
      IF lt_kunnr IS NOT INITIAL.
        SELECT spras FROM kna1 INTO TABLE lt_spras
          FOR ALL ENTRIES IN lt_kunnr
          WHERE kunnr = lt_kunnr-table_line.
        LOOP AT lt_spras INTO lv_spras.
          INSERT lv_spras INTO TABLE lt_lang.
        ENDLOOP.
      ENDIF.
      LOOP AT mt_lifnr_fi INTO lv_lifnr.
        APPEND lv_lifnr TO lt_lifnr.
      ENDLOOP.
      LOOP AT mt_lifnr_mm INTO lv_lifnr.
        APPEND lv_lifnr TO lt_lifnr.
      ENDLOOP.
      SORT lt_lifnr.
      DELETE ADJACENT DUPLICATES FROM lt_lifnr.
      IF lt_lifnr IS NOT INITIAL.
        SELECT spras FROM lfa1 INTO TABLE lt_spras
          FOR ALL ENTRIES IN lt_lifnr
          WHERE lifnr = lt_lifnr-table_line.
        LOOP AT lt_spras INTO lv_spras.
          INSERT lv_spras INTO TABLE lt_lang.
        ENDLOOP.
      ENDIF.
      SELECT spras laiso FROM t002 INTO TABLE lt_t002.
      LOOP AT lt_lang INTO lv_spras.
        READ TABLE lt_t002 INTO ls_t002 WITH TABLE KEY spras = lv_spras.
        IF sy-subrc = 0 AND ls_t002-laiso IS NOT INITIAL.
          INSERT ls_t002-laiso INTO TABLE lt_iso.
        ENDIF.
      ENDLOOP.
      LOOP AT lt_iso INTO lv_laiso.
        add_to_list( EXPORTING iv_value = lv_laiso CHANGING cv_list = ms_res-meta-g6 ).
      ENDLOOP.
      ms_res-meta-g6_st = gc_st_ok.
    ELSE.
      ms_res-meta-g6_st = src_status( 'FI_CUST FI_VEND SD_VBAK MM_EKKO' ).
    ENDIF.

* G7: local currencies of the active company codes plus the document currencies
* of the sales orders and purchase orders created in the period
    IF mv_base_ok = gc_x AND mv_sd_cust_ok = gc_x AND mv_mm_vend_ok = gc_x.
      LOOP AT mt_t001 INTO ls_t001.
        READ TABLE mt_bukrs_act TRANSPORTING NO FIELDS WITH TABLE KEY table_line = ls_t001-bukrs.
        IF sy-subrc = 0 AND ls_t001-waers IS NOT INITIAL.
          INSERT ls_t001-waers INTO TABLE lt_waers.
        ENDIF.
      ENDLOOP.
      LOOP AT mt_waers_sd INTO lv_waers.
        IF lv_waers IS NOT INITIAL.
          INSERT lv_waers INTO TABLE lt_waers.
        ENDIF.
      ENDLOOP.
      LOOP AT mt_waers_mm INTO lv_waers.
        IF lv_waers IS NOT INITIAL.
          INSERT lv_waers INTO TABLE lt_waers.
        ENDIF.
      ENDLOOP.
      LOOP AT lt_waers INTO lv_waers.
        add_to_list( EXPORTING iv_value = lv_waers CHANGING cv_list = ms_res-meta-g7 ).
      ENDLOOP.
      ms_res-meta-g7_st = gc_st_ok.
    ELSE.
      ms_res-meta-g7_st = src_status( 'BASE_BUKRS SD_VBAK MM_EKKO' ).
    ENDIF.
  ENDMETHOD.

* "a, b, c" without depending on how CONCATENATE treats trailing blanks of a
* separator literal
  METHOD add_to_list.
    DATA lv_value TYPE string.

    lv_value = iv_value.
    IF cv_list IS INITIAL.
      cv_list = lv_value.
    ELSE.
      CONCATENATE cv_list ',' INTO cv_list.
      CONCATENATE cv_list lv_value INTO cv_list SEPARATED BY space.
    ENDIF.
  ENDMETHOD.

* Status of a derived value whose source flag is not set: "error" if one of the
* source steps (blank-separated names) ran and failed, otherwise space ("not
* collected", the block was skipped). All source steps run before ORG and DERV
  METHOD src_status.
    DATA: lt_step TYPE STANDARD TABLE OF string,
          lv_step TYPE string,
          lv_name TYPE c LENGTH 20.

    SPLIT iv_steps AT space INTO TABLE lt_step.
    LOOP AT lt_step INTO lv_step.
      lv_name = lv_step.
      READ TABLE ms_res-errors TRANSPORTING NO FIELDS WITH KEY step = lv_name.
      IF sy-subrc = 0.
        rv_status = gc_st_err.
        EXIT.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

* Application usage in the organization view (design 9): documents created in
* the period per area, taken from the figures that the blocks collected. Status
* and count follow the source figure
  METHOD step_derv_usage.
    DELETE ms_res-orgs WHERE grp = 'A'.
    add_usage( iv_area = 'O11' iv_fkey = 'D27' ).
    add_usage( iv_area = 'O12' iv_fkey = 'Q13' ).
    add_usage( iv_area = 'O13' iv_fkey = 'D08' ).
    add_usage( iv_area = 'O14' iv_fkey = 'D09' ).
    add_usage( iv_area = 'O15' iv_fkey = 'Q15' ).
    add_usage( iv_area = 'O16' iv_fkey = 'D12' ).
    add_usage( iv_area = 'O17' iv_fkey = 'D11' ).
    add_usage( iv_area = 'O18' iv_fkey = 'Q24' ).
    add_usage( iv_area = 'O19' iv_fkey = 'Q25' ).
    add_usage( iv_area = 'O20' iv_fkey = 'D15' ).
    add_usage( iv_area = 'O21' iv_fkey = 'D16' ).
    add_usage( iv_area = 'O22' iv_fkey = 'D22' ).
  ENDMETHOD.

  METHOD add_usage.
    DATA: ls_fig  TYPE ty_fig,
          ls_org  TYPE ty_org,
          lv_fkey TYPE ty_textid.

    lv_fkey = iv_fkey.
    READ TABLE ms_res-figs INTO ls_fig WITH TABLE KEY fkey = lv_fkey sub = space.
    ls_org-grp    = 'A'.
    ls_org-okey   = iv_area.
    ls_org-status = ls_fig-status.
    IF ls_fig-status = gc_st_ok.
      ls_org-cnt = ls_fig-c_total.
      IF ls_org-cnt > 0.
        ls_org-used = gc_x.
      ENDIF.
    ENDIF.
    APPEND ls_org TO ms_res-orgs.
  ENDMETHOD.

* Rows 7 and 9: union of the FI set with the SD set (sold-to parties of sales
* orders) and the MM set (vendors of purchase orders). Built only if both
* source steps succeeded; otherwise the row stays "not collected" or "error"
  METHOD step_derv_active.
    DATA: lt_kunnr TYPE ty_kunnr_t,
          lv_kunnr TYPE kunnr,
          lt_lifnr TYPE ty_lifnr_t,
          lv_lifnr TYPE lifnr,
          lv_cnt   TYPE i,
          lv_val   TYPE ty_num.

    IF mv_fi_cust_ok = gc_x AND mv_sd_cust_ok = gc_x.
      lt_kunnr = mt_kunnr_fi.
      LOOP AT mt_kunnr_sd INTO lv_kunnr.
        INSERT lv_kunnr INTO TABLE lt_kunnr.
      ENDLOOP.
      DESCRIBE TABLE lt_kunnr LINES lv_cnt.
      lv_val = lv_cnt.
      set_b( iv_fkey = 'Q07' iv_val = lv_val ).
    ENDIF.
    IF mv_fi_vend_ok = gc_x AND mv_mm_vend_ok = gc_x.
      lt_lifnr = mt_lifnr_fi.
      LOOP AT mt_lifnr_mm INTO lv_lifnr.
        INSERT lv_lifnr INTO TABLE lt_lifnr.
      ENDLOOP.
      DESCRIBE TABLE lt_lifnr LINES lv_cnt.
      lv_val = lv_cnt.
      set_b( iv_fkey = 'Q09' iv_val = lv_val ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Output: SALV in dialog, WRITE list in background (design 6, 13.4, 13.6)
*----------------------------------------------------------------------*
CLASS lcl_output DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS constructor
      IMPORTING is_result TYPE ty_result.
    METHODS display
      IMPORTING iv_view TYPE i.
    METHODS write_all.
  PRIVATE SECTION.
    TYPES: BEGIN OF ty_col,
             fname TYPE lvc_fname,
             head  TYPE ty_textid,
             width TYPE i,                    " column width in the background list
           END OF ty_col,
           ty_col_t TYPE STANDARD TABLE OF ty_col WITH DEFAULT KEY.
* All value columns are character fields: "N/A" and numbers share one column
    TYPES: BEGIN OF ty_v1,
             row    TYPE c LENGTH 3,
             item   TYPE c LENGTH 60,
             val_b  TYPE c LENGTH 40,
             val_c  TYPE c LENGTH 20,
             basis  TYPE c LENGTH 60,
             total  TYPE c LENGTH 20,
             defin  TYPE c LENGTH 132,
             remark TYPE c LENGTH 255,
           END OF ty_v1,
           ty_v1_t TYPE STANDARD TABLE OF ty_v1 WITH DEFAULT KEY,
           BEGIN OF ty_v2,
             plant    TYPE c LENGTH 40,
             location TYPE c LENGTH 3,
             revenue  TYPE c LENGTH 20,
             on_sap   TYPE c LENGTH 1,
             legacy   TYPE c LENGTH 1,
             city     TYPE c LENGTH 25,
             bukrs    TYPE c LENGTH 4,
             counted  TYPE c LENGTH 1,
             manuf    TYPE c LENGTH 1,
           END OF ty_v2,
           ty_v2_t TYPE STANDARD TABLE OF ty_v2 WITH DEFAULT KEY,
           BEGIN OF ty_v3,
             grp    TYPE c LENGTH 40,
             okey   TYPE c LENGTH 10,
             otext  TYPE c LENGTH 40,
             ovalue TYPE c LENGTH 255,
             used   TYPE c LENGTH 20,           " X, or "not collected" / "error"
           END OF ty_v3,
           ty_v3_t TYPE STANDARD TABLE OF ty_v3 WITH DEFAULT KEY,
           BEGIN OF ty_v4,
             grp    TYPE c LENGTH 40,
             item   TYPE c LENGTH 80,
             value  TYPE c LENGTH 40,
             avg    TYPE c LENGTH 20,
             total  TYPE c LENGTH 20,
             defin  TYPE c LENGTH 132,
             remark TYPE c LENGTH 255,
           END OF ty_v4,
           ty_v4_t TYPE STANDARD TABLE OF ty_v4 WITH DEFAULT KEY,
           BEGIN OF ty_v5,
             otype TYPE c LENGTH 30,
             name  TYPE c LENGTH 40,
             itype TYPE c LENGTH 20,
             descr TYPE c LENGTH 120,
             rel   TYPE c LENGTH 10,
             splev TYPE c LENGTH 10,
             idocs TYPE c LENGTH 20,
           END OF ty_v5,
           ty_v5_t TYPE STANDARD TABLE OF ty_v5 WITH DEFAULT KEY.
    DATA: ms_res TYPE ty_result,
          mt_v1  TYPE ty_v1_t,
          mt_v2  TYPE ty_v2_t,
          mt_v3  TYPE ty_v3_t,
          mt_v4  TYPE ty_v4_t,
          mt_v5  TYPE ty_v5_t.
    METHODS get_view
      IMPORTING iv_view  TYPE i
      EXPORTING er_table TYPE REF TO data
                et_cols  TYPE ty_col_t
                ev_title TYPE ty_textid.
    METHODS add_col
      IMPORTING iv_fname TYPE c
                iv_head  TYPE c
                iv_width TYPE i
      CHANGING  ct_cols  TYPE ty_col_t.
    METHODS build_v1.
    METHODS coa_note
      RETURNING value(rv_note) TYPE string.
    METHODS coa_split
      RETURNING value(rv_split) TYPE string.
    METHODS plant_split
      RETURNING value(rv_split) TYPE string.
    METHODS build_v2.
    METHODS build_v3.
    METHODS build_v4.
    METHODS build_v5.
    METHODS add_info
      IMPORTING iv_id    TYPE c
                iv_value TYPE any.
    METHODS sub_text
      IMPORTING iv_fkey        TYPE c
                iv_sub         TYPE c
      RETURNING value(rv_text) TYPE string.
    METHODS domain_text
      IMPORTING iv_domain      TYPE c
                iv_value       TYPE c
      RETURNING value(rv_text) TYPE string.
    METHODS rollname_text
      IMPORTING iv_rollname    TYPE c
                iv_value       TYPE c
      RETURNING value(rv_text) TYPE string.
    METHODS add_g_line
      IMPORTING iv_id     TYPE c
                iv_value  TYPE string
                iv_status TYPE c.
    METHODS status_text
      IMPORTING iv_status      TYPE c
      RETURNING value(rv_text) TYPE string.
    METHODS cell
      IMPORTING iv_na          TYPE c
                iv_status      TYPE c
                iv_num         TYPE ty_num
      RETURNING value(rv_text) TYPE string.
    METHODS num
      IMPORTING iv_num         TYPE ty_num
      RETURNING value(rv_text) TYPE string.
    METHODS show_salv
      IMPORTING it_cols  TYPE ty_col_t
                iv_title TYPE ty_textid
      CHANGING  ct_table TYPE STANDARD TABLE.
    METHODS write_table
      IMPORTING it_cols  TYPE ty_col_t
                iv_title TYPE ty_textid
                it_table TYPE STANDARD TABLE.
ENDCLASS.

CLASS lcl_output IMPLEMENTATION.

  METHOD constructor.
    ms_res = is_result.
  ENDMETHOD.

  METHOD display.
    DATA: lr_table TYPE REF TO data,
          lt_cols  TYPE ty_col_t,
          lv_title TYPE ty_textid.
    FIELD-SYMBOLS <lt_table> TYPE STANDARD TABLE.

    get_view( EXPORTING iv_view  = iv_view
              IMPORTING er_table = lr_table
                        et_cols  = lt_cols
                        ev_title = lv_title ).
    ASSIGN lr_table->* TO <lt_table>.
    show_salv( EXPORTING it_cols  = lt_cols
                         iv_title = lv_title
               CHANGING  ct_table = <lt_table> ).
  ENDMETHOD.

  METHOD write_all.
    DATA: lr_table TYPE REF TO data,
          lt_cols  TYPE ty_col_t,
          lv_title TYPE ty_textid,
          lv_view  TYPE i.
    FIELD-SYMBOLS <lt_table> TYPE STANDARD TABLE.

    DO 5 TIMES.
      lv_view = sy-index.
      get_view( EXPORTING iv_view  = lv_view
                IMPORTING er_table = lr_table
                          et_cols  = lt_cols
                          ev_title = lv_title ).
      ASSIGN lr_table->* TO <lt_table>.
      write_table( it_cols = lt_cols iv_title = lv_title it_table = <lt_table> ).
    ENDDO.
  ENDMETHOD.

  METHOD get_view.
    CLEAR: er_table, et_cols, ev_title.
    CASE iv_view.
      WHEN 1.
        build_v1( ).
        GET REFERENCE OF mt_v1 INTO er_table.
        ev_title = 'V01'.
        add_col( EXPORTING iv_fname = 'ROW'    iv_head = 'H01' iv_width = 3   CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'ITEM'   iv_head = 'H02' iv_width = 40  CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'VAL_B'  iv_head = 'H03' iv_width = 25  CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'VAL_C'  iv_head = 'H04' iv_width = 15  CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'BASIS'  iv_head = 'H05' iv_width = 40  CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'TOTAL'  iv_head = 'H06' iv_width = 15  CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'DEFIN'  iv_head = 'H07' iv_width = 120 CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'REMARK' iv_head = 'H08' iv_width = 120 CHANGING ct_cols = et_cols ).
      WHEN 2.
        build_v2( ).
        GET REFERENCE OF mt_v2 INTO er_table.
        ev_title = 'V02'.
        add_col( EXPORTING iv_fname = 'PLANT'    iv_head = 'H10' iv_width = 40 CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'LOCATION' iv_head = 'H11' iv_width = 8  CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'REVENUE'  iv_head = 'H12' iv_width = 14 CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'ON_SAP'   iv_head = 'H13' iv_width = 6  CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'LEGACY'   iv_head = 'H14' iv_width = 16 CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'CITY'     iv_head = 'H15' iv_width = 25 CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'BUKRS'    iv_head = 'H16' iv_width = 12 CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'COUNTED'  iv_head = 'H17' iv_width = 17 CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'MANUF'    iv_head = 'H18' iv_width = 13 CHANGING ct_cols = et_cols ).
      WHEN 3.
        build_v3( ).
        GET REFERENCE OF mt_v3 INTO er_table.
        ev_title = 'V03'.
        add_col( EXPORTING iv_fname = 'GRP'    iv_head = 'H20' iv_width = 30  CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'OKEY'   iv_head = 'H21' iv_width = 10  CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'OTEXT'  iv_head = 'H22' iv_width = 40  CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'OVALUE' iv_head = 'H23' iv_width = 120 CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'USED'   iv_head = 'H24' iv_width = 20  CHANGING ct_cols = et_cols ).
      WHEN 4.
        build_v4( ).
        GET REFERENCE OF mt_v4 INTO er_table.
        ev_title = 'V04'.
        add_col( EXPORTING iv_fname = 'GRP'    iv_head = 'H20' iv_width = 20  CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'ITEM'   iv_head = 'H02' iv_width = 50  CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'VALUE'  iv_head = 'H23' iv_width = 25  CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'AVG'    iv_head = 'H04' iv_width = 15  CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'TOTAL'  iv_head = 'H06' iv_width = 15  CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'DEFIN'  iv_head = 'H07' iv_width = 120 CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'REMARK' iv_head = 'H08' iv_width = 120 CHANGING ct_cols = et_cols ).
      WHEN OTHERS.
        build_v5( ).
        GET REFERENCE OF mt_v5 INTO er_table.
        ev_title = 'V05'.
        add_col( EXPORTING iv_fname = 'OTYPE' iv_head = 'H30' iv_width = 20 CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'NAME'  iv_head = 'H31' iv_width = 40 CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'ITYPE' iv_head = 'H32' iv_width = 10 CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'DESCR' iv_head = 'H22' iv_width = 120 CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'REL'   iv_head = 'H34' iv_width = 10 CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'SPLEV' iv_head = 'H35' iv_width = 10 CHANGING ct_cols = et_cols ).
        add_col( EXPORTING iv_fname = 'IDOCS' iv_head = 'H33' iv_width = 15 CHANGING ct_cols = et_cols ).
    ENDCASE.
  ENDMETHOD.

  METHOD add_col.
    DATA ls_col TYPE ty_col.

    ls_col-fname = iv_fname.
    ls_col-head  = iv_head.
    ls_col-width = iv_width.
    APPEND ls_col TO ct_cols.
  ENDMETHOD.

* View 1: exactly 27 rows in questionnaire order, so that B3:C29 (or B3:D29)
* can be pasted as one block
  METHOD build_v1.
    DATA: ls_row  TYPE ty_v1,
          ls_fig  TYPE ty_fig,
          lv_nr   TYPE n LENGTH 2,
          lv_id   TYPE ty_textid,
          lv_text TYPE string,
          lv_split TYPE string,
          lv_avg  TYPE ty_num.

    CLEAR mt_v1.
    lv_nr = 2.
    DO 27 TIMES.
      lv_nr = lv_nr + 1.
      CLEAR: ls_row, ls_fig, lv_avg.
      ls_row-row = lv_nr.
      SHIFT ls_row-row LEFT DELETING LEADING '0'.
      CONCATENATE 'Q' lv_nr INTO lv_id.
      ls_row-item = lcl_text=>get( lv_id ).
      IF lv_nr <> 17.
        READ TABLE ms_res-figs INTO ls_fig WITH TABLE KEY fkey = lv_id sub = space.
        lv_text = cell( iv_na = ls_fig-b_na iv_status = ls_fig-status iv_num = ls_fig-b_val ).
* Row 4: "1 (4 local, 1 group)" with the country and group charts of D28/D29
        IF lv_nr = 4 AND ls_fig-status = gc_st_ok.
          lv_split = coa_split( ).
          IF lv_split IS NOT INITIAL.
            CONCATENATE lv_text lv_split INTO lv_text SEPARATED BY space.
          ENDIF.
        ENDIF.
* Row 27: "227 (12 prod)" with the manufacturing plants of view 2
        IF lv_nr = 27 AND ls_fig-status = gc_st_ok.
          lv_split = plant_split( ).
          IF lv_split IS NOT INITIAL.
            CONCATENATE lv_text lv_split INTO lv_text SEPARATED BY space.
          ENDIF.
        ENDIF.
        ls_row-val_b = lv_text.
        IF ms_res-meta-months > 0.
          lv_avg = ls_fig-c_total / ms_res-meta-months.     " packed result: commercial rounding
        ENDIF.
        lv_text = cell( iv_na = ls_fig-c_na iv_status = ls_fig-status iv_num = lv_avg ).
* The average is always per month: "(M)" after the number
        IF ls_fig-c_na IS INITIAL AND ls_fig-status = gc_st_ok.
          lv_split = lcl_text=>get( 'M16' ).
          CONCATENATE lv_text lv_split INTO lv_text SEPARATED BY space.
        ENDIF.
        ls_row-val_c = lv_text.
        IF ls_fig-c_na IS INITIAL.
          lv_text = cell( iv_na = space iv_status = ls_fig-status iv_num = ls_fig-c_total ).
          ls_row-total = lv_text.
        ENDIF.
        CONCATENATE 'N' lv_nr INTO lv_id.
        ls_row-basis = lcl_text=>get( lv_id ).
        CONCATENATE 'L' lv_nr INTO lv_id.
        ls_row-defin = lcl_text=>get( lv_id ).
        CONCATENATE 'R' lv_nr INTO lv_id.
        ls_row-remark = lcl_text=>get( lv_id ).
* Row 4: country and group charts of accounts from details D28/D29
        IF lv_nr = 4.
          lv_text = coa_note( ).
          IF lv_text IS NOT INITIAL.
            CONCATENATE ls_row-remark ';' INTO ls_row-remark.
            CONCATENATE ls_row-remark lv_text INTO ls_row-remark SEPARATED BY space.
          ENDIF.
        ENDIF.
        IF ls_fig-status = gc_st_err.
          CONCATENATE ls_row-remark ls_fig-errtext INTO ls_row-remark SEPARATED BY space.
          SHIFT ls_row-remark LEFT DELETING LEADING space.
        ENDIF.
      ENDIF.
      APPEND ls_row TO mt_v1.
    ENDDO.
  ENDMETHOD.

* "(4 local, 1 group)": number of country (D28) and group charts (D29); empty
* unless both were collected
  METHOD coa_split.
    DATA: ls_fig   TYPE ty_fig,
          lv_local TYPE string,
          lv_group TYPE string,
          lv_word  TYPE string.

    READ TABLE ms_res-figs INTO ls_fig WITH TABLE KEY fkey = 'D28' sub = space.
    IF sy-subrc <> 0 OR ls_fig-status <> gc_st_ok.
      RETURN.
    ENDIF.
    lv_local = num( ls_fig-b_val ).
    READ TABLE ms_res-figs INTO ls_fig WITH TABLE KEY fkey = 'D29' sub = space.
    IF sy-subrc <> 0 OR ls_fig-status <> gc_st_ok.
      RETURN.
    ENDIF.
    lv_group = num( ls_fig-b_val ).
    lv_word = lcl_text=>get( 'M14' ).
    CONCATENATE '(' lv_local INTO rv_split.
    CONCATENATE rv_split lv_word INTO rv_split SEPARATED BY space.
    CONCATENATE rv_split ',' INTO rv_split.
    lv_word = lcl_text=>get( 'M15' ).
    CONCATENATE rv_split lv_group lv_word INTO rv_split SEPARATED BY space.
    CONCATENATE rv_split ')' INTO rv_split.
  ENDMETHOD.

* "(12 prod)": counted plants with production or process orders created
* in the period (plant view, design 10). Empty unless the order pass of block
* PP ran without error, because "manufacturing" is only known then
  METHOD plant_split.
    DATA: ls_block TYPE ty_block,
          ls_plant TYPE ty_plant,
          lv_num   TYPE ty_num,
          lv_cnt   TYPE string,
          lv_word  TYPE string.

    READ TABLE ms_res-blocks INTO ls_block WITH KEY block = 'PP'.
    IF sy-subrc <> 0 OR ls_block-active IS INITIAL.
      RETURN.
    ENDIF.
    READ TABLE ms_res-errors TRANSPORTING NO FIELDS WITH KEY step = 'PP_AUFK'.
    IF sy-subrc = 0.
      RETURN.
    ENDIF.
    LOOP AT ms_res-plants INTO ls_plant WHERE counted = gc_x AND manuf = gc_x.
      lv_num = lv_num + 1.
    ENDLOOP.
    lv_cnt  = num( lv_num ).
    lv_word = lcl_text=>get( 'M17' ).
    CONCATENATE '(' lv_cnt INTO rv_split.
    CONCATENATE rv_split lv_word INTO rv_split SEPARATED BY space.
    CONCATENATE rv_split ')' INTO rv_split.
  ENDMETHOD.

* "Country charts of accounts: 4 (CAFR, CAIN); Group charts of accounts: 1
* (GRP1)" from the stored details D28/D29; empty if they were not collected
  METHOD coa_note.
    DATA: ls_fig  TYPE ty_fig,
          lv_fkey TYPE ty_textid,
          lv_cnt  TYPE ty_num,
          lv_list TYPE string,
          lv_part TYPE string,
          lv_text TYPE string.

    DO 2 TIMES.
      IF sy-index = 1.
        lv_fkey = 'D28'.
      ELSE.
        lv_fkey = 'D29'.
      ENDIF.
      CLEAR ls_fig.
      READ TABLE ms_res-figs INTO ls_fig WITH TABLE KEY fkey = lv_fkey sub = space.
      IF sy-subrc <> 0 OR ls_fig-status <> gc_st_ok.
        CONTINUE.
      ENDIF.
      lv_cnt = ls_fig-b_val.
      CLEAR lv_list.
      LOOP AT ms_res-figs INTO ls_fig WHERE fkey = lv_fkey AND sub IS NOT INITIAL.
        IF lv_list IS INITIAL.
          lv_list = ls_fig-sub.
        ELSE.
          CONCATENATE lv_list ',' INTO lv_list.
          CONCATENATE lv_list ls_fig-sub INTO lv_list SEPARATED BY space.
        ENDIF.
      ENDLOOP.
      lv_text = lcl_text=>get( lv_fkey ).
      CONCATENATE lv_text ':' INTO lv_part.
      lv_text = num( lv_cnt ).
      CONCATENATE lv_part lv_text INTO lv_part SEPARATED BY space.
      IF lv_list IS NOT INITIAL.
        CONCATENATE '(' lv_list ')' INTO lv_list.
        CONCATENATE lv_part lv_list INTO lv_part SEPARATED BY space.
      ENDIF.
      IF rv_note IS INITIAL.
        rv_note = lv_part.
      ELSE.
        CONCATENATE rv_note ';' INTO rv_note.
        CONCATENATE rv_note lv_part INTO rv_note SEPARATED BY space.
      ENDIF.
    ENDDO.
  ENDMETHOD.

* View 2: columns F to J of the plant table first, then supporting columns
  METHOD build_v2.
    DATA: ls_plant TYPE ty_plant,
          ls_row   TYPE ty_v2.

    CLEAR mt_v2.
    LOOP AT ms_res-plants INTO ls_plant.
      CLEAR ls_row.
      CONCATENATE ls_plant-werks '-' ls_plant-name1 INTO ls_row-plant SEPARATED BY space.
      ls_row-location = ls_plant-land1.
      ls_row-on_sap   = gc_x.
      ls_row-city     = ls_plant-ort01.
      ls_row-bukrs    = ls_plant-bukrs.
      ls_row-counted  = ls_plant-counted.
      ls_row-manuf    = ls_plant-manuf.
      APPEND ls_row TO mt_v2.
    ENDLOOP.
  ENDMETHOD.

  METHOD build_v3.
    DATA: ls_org TYPE ty_org,
          ls_row TYPE ty_v3,
          lv_id  TYPE ty_textid.

    CLEAR mt_v3.
* G5 to G7: one list each for one merged target cell (long lists wrap)
    add_g_line( iv_id = 'O01' iv_value = ms_res-meta-g5 iv_status = ms_res-meta-g5_st ).
    add_g_line( iv_id = 'O02' iv_value = ms_res-meta-g6 iv_status = ms_res-meta-g6_st ).
    add_g_line( iv_id = 'O03' iv_value = ms_res-meta-g7 iv_status = ms_res-meta-g7_st ).

    LOOP AT ms_res-orgs INTO ls_org.
      CLEAR ls_row.
      CASE ls_org-grp.
        WHEN 'P'.
          lv_id = 'O04'.
        WHEN 'S'.
          lv_id = 'O05'.
        WHEN 'D'.
          lv_id = 'O06'.
        WHEN 'V'.
          lv_id = 'O07'.
        WHEN OTHERS.
          lv_id = 'O08'.
      ENDCASE.
      ls_row-grp = lcl_text=>get( lv_id ).
      IF ls_org-grp = 'A'.
        ls_row-otext = lcl_text=>get( ls_org-okey ).
        IF ls_org-status = gc_st_ok.
          ls_row-ovalue = num( ls_org-cnt ).
        ELSE.
          ls_row-ovalue = status_text( ls_org-status ).
        ENDIF.
      ELSE.
        ls_row-okey   = ls_org-okey.
        ls_row-otext  = ls_org-otext.
        ls_row-ovalue = ls_org-bukrs.
      ENDIF.
* "Used" is only known if the block that reads the documents was collected
      IF ls_org-status = gc_st_ok.
        ls_row-used = ls_org-used.
      ELSE.
        ls_row-used = status_text( ls_org-status ).
      ENDIF.
      APPEND ls_row TO mt_v3.
    ENDLOOP.
  ENDMETHOD.

* A list longer than one row continues in further rows of the same group. Each
* row has at most 120 characters including its closing comma, so that it fits
* the spool column (120) and an ALV grid cell (128). The key column of the first
* row holds the number of entries, so a pasted list can be checked
  METHOD add_g_line.
    CONSTANTS lc_max TYPE i VALUE 120.
    DATA: ls_row  TYPE ty_v3,
          lt_item TYPE STANDARD TABLE OF string,
          lv_item TYPE string,
          lv_line TYPE string,
          lv_len  TYPE i,
          lv_cnt  TYPE i,
          lv_num  TYPE ty_num.

    ls_row-grp = lcl_text=>get( iv_id ).
    IF iv_status <> gc_st_ok.
      ls_row-ovalue = status_text( iv_status ).
      APPEND ls_row TO mt_v3.
      RETURN.
    ENDIF.

    IF iv_value IS NOT INITIAL.
      SPLIT iv_value AT ',' INTO TABLE lt_item.
    ENDIF.
    DESCRIBE TABLE lt_item LINES lv_cnt.
    lv_num = lv_cnt.
    ls_row-okey = num( lv_num ).
    LOOP AT lt_item INTO lv_item.
      CONDENSE lv_item.
      lv_len = strlen( lv_line ) + strlen( lv_item ) + 3.
      IF lv_line IS NOT INITIAL AND lv_len > lc_max.
        CONCATENATE lv_line ',' INTO ls_row-ovalue.
        APPEND ls_row TO mt_v3.
        CLEAR: ls_row-okey, ls_row-ovalue, lv_line.
      ENDIF.
      IF lv_line IS INITIAL.
        lv_line = lv_item.
      ELSE.
        CONCATENATE lv_line ',' INTO lv_line.
        CONCATENATE lv_line lv_item INTO lv_line SEPARATED BY space.
      ENDIF.
    ENDLOOP.
    ls_row-ovalue = lv_line.
    APPEND ls_row TO mt_v3.
  ENDMETHOD.

* Text for a value that is not available: "error" or "not collected"
  METHOD status_text.
    IF iv_status = gc_st_err.
      rv_text = lcl_text=>get( 'S03' ).
    ELSE.
      rv_text = lcl_text=>get( 'S02' ).
    ENDIF.
  ENDMETHOD.

* View 4: INFO (run metadata, design 8.1), then the supporting figures (8.2)
  METHOD build_v4.
    DATA: ls_row   TYPE ty_v4,
          ls_fig   TYPE ty_fig,
          lt_det   TYPE STANDARD TABLE OF ty_fig,
          ls_block TYPE ty_block,
          ls_error TYPE ty_error,
          lv_id    TYPE ty_textid,
          lv_info  TYPE string,
          lv_date1 TYPE c LENGTH 10,
          lv_date2 TYPE c LENGTH 10,
          lv_time  TYPE c LENGTH 8,
          lv_iso   TYPE c LENGTH 2,
          lv_num   TYPE ty_num,
          lv_avg   TYPE ty_num.

    CLEAR mt_v4.
    add_info( iv_id = 'D80' iv_value = ms_res-meta-sysid ).
    add_info( iv_id = 'D81' iv_value = ms_res-meta-mandt ).
    add_info( iv_id = 'D82' iv_value = ms_res-meta-saprl ).
    add_info( iv_id = 'D83' iv_value = ms_res-meta-dbsys ).
    CALL FUNCTION 'CONVERSION_EXIT_ISOLA_OUTPUT'
      EXPORTING
        input  = ms_res-meta-langu
      IMPORTING
        output = lv_iso.
    add_info( iv_id = 'D84' iv_value = lv_iso ).
    WRITE ms_res-meta-datfr TO lv_date1.
    WRITE ms_res-meta-datto TO lv_date2.
    CONCATENATE lv_date1 '-' lv_date2 INTO lv_info SEPARATED BY space.
    add_info( iv_id = 'D85' iv_value = lv_info ).
    lv_num = ms_res-meta-months.
    lv_info = num( lv_num ).
    add_info( iv_id = 'D86' iv_value = lv_info ).
    WRITE ms_res-meta-startd TO lv_date1.
    WRITE ms_res-meta-startt TO lv_time.
    CONCATENATE lv_date1 lv_time INTO lv_info SEPARATED BY space.
    add_info( iv_id = 'D87' iv_value = lv_info ).
    WRITE ms_res-meta-endd TO lv_date1.
    WRITE ms_res-meta-endt TO lv_time.
    CONCATENATE lv_date1 lv_time INTO lv_info SEPARATED BY space.
    add_info( iv_id = 'D88' iv_value = lv_info ).
    add_info( iv_id = 'D89' iv_value = ms_res-meta-uname ).
    IF ms_res-meta-stored_d IS NOT INITIAL.
      WRITE ms_res-meta-stored_d TO lv_date1.
      WRITE ms_res-meta-stored_t TO lv_time.
      CONCATENATE lv_date1 lv_time INTO lv_info SEPARATED BY space.
      add_info( iv_id = 'D90' iv_value = lv_info ).
    ENDIF.
* Runtime per block; skipped blocks show "not collected"
    LOOP AT ms_res-blocks INTO ls_block.
      CLEAR ls_row.
      ls_row-grp = lcl_text=>get( 'G00' ).
      lv_info = lcl_text=>get( 'M12' ).
      CONCATENATE lv_info ls_block-block INTO ls_row-item SEPARATED BY space.
      IF ls_block-active = gc_x.
        lv_num = ls_block-seconds.
        ls_row-value = num( lv_num ).
      ELSE.
        ls_row-value = lcl_text=>get( 'S02' ).
      ENDIF.
      APPEND ls_row TO mt_v4.
    ENDLOOP.
* Failed steps with the exception text
    LOOP AT ms_res-errors INTO ls_error.
      CLEAR ls_row.
      ls_row-grp = lcl_text=>get( 'G00' ).
      lv_info = lcl_text=>get( 'M08' ).
      CONCATENATE lv_info ls_error-step INTO ls_row-item SEPARATED BY space.
      ls_row-value  = lcl_text=>get( 'S03' ).
      ls_row-remark = ls_error-text.
      APPEND ls_row TO mt_v4.
    ENDLOOP.

* Details grouped by their group, within a group in detail order (header
* before its sub rows)
    LOOP AT ms_res-figs INTO ls_fig.
      IF ls_fig-fkey(1) = 'D'.
        APPEND ls_fig TO lt_det.
      ENDIF.
    ENDLOOP.
    SORT lt_det BY grp fkey sub.
    LOOP AT lt_det INTO ls_fig.
      CLEAR: ls_row, lv_avg.
      ls_row-grp  = lcl_text=>get( ls_fig-grp ).
      ls_row-item = lcl_text=>get( ls_fig-fkey ).
      IF ls_fig-sub IS NOT INITIAL.
        lv_info = sub_text( iv_fkey = ls_fig-fkey iv_sub = ls_fig-sub ).
        CONCATENATE ls_row-item '-' ls_fig-sub lv_info INTO ls_row-item SEPARATED BY space.
      ELSE.
        CONCATENATE 'E' ls_fig-fkey+1(2) INTO lv_id.
        ls_row-defin = lcl_text=>get( lv_id ).
      ENDIF.
      IF ls_fig-status = gc_st_ok.
        IF ls_fig-b_na IS INITIAL.
          ls_row-value = num( ls_fig-b_val ).
        ENDIF.
        IF ls_fig-c_na IS INITIAL.
          IF ms_res-meta-months > 0.
            lv_avg = ls_fig-c_total / ms_res-meta-months.
          ENDIF.
          ls_row-avg   = num( lv_avg ).
          ls_row-total = num( ls_fig-c_total ).
        ENDIF.
      ELSEIF ls_fig-status = gc_st_err.
        ls_row-value  = lcl_text=>get( 'S03' ).
        ls_row-remark = ls_fig-errtext.
      ELSE.
        ls_row-value = lcl_text=>get( 'S02' ).
      ENDIF.
      APPEND ls_row TO mt_v4.
    ENDLOOP.
  ENDMETHOD.

* View 5 (design 11) in the order RFC destinations, logical systems, partner
* profiles, software components. An object type whose step failed shows one
* "error" row; if block INTF was skipped, each type shows "not collected"
  METHOD build_v5.
    TYPES: BEGIN OF lty_rtext,
             itype TYPE c LENGTH 20,
             text  TYPE string,
           END OF lty_rtext.
    DATA: ls_intf   TYPE ty_intf,
          ls_row    TYPE ty_v5,
          ls_block  TYPE ty_block,
          lt_rtext  TYPE SORTED TABLE OF lty_rtext WITH UNIQUE KEY itype,
          ls_rtext  TYPE lty_rtext,
          lv_otype  TYPE ty_flag,
          lv_id     TYPE ty_textid,
          lv_step   TYPE c LENGTH 20,
          lv_type   TYPE string,
          lv_noprof TYPE string.

    CLEAR mt_v5.
    READ TABLE ms_res-blocks INTO ls_block WITH KEY block = 'INTF'.
    lv_noprof = lcl_text=>get( 'I05' ).

    DO 4 TIMES.
      CASE sy-index.
        WHEN 1.
          lv_otype = 'R'.
          lv_id    = 'I01'.
          lv_step  = 'INTF_RFC'.
        WHEN 2.
          lv_otype = 'L'.
          lv_id    = 'I02'.
          lv_step  = 'INTF_LOGSYS'.
        WHEN 3.
          lv_otype = 'P'.
          lv_id    = 'I03'.
          lv_step  = 'INTF_PARTNER'.
        WHEN OTHERS.
          lv_otype = 'C'.
          lv_id    = 'I04'.
          lv_step  = 'INTF_CVERS'.
      ENDCASE.
      lv_type = lcl_text=>get( lv_id ).

      IF ls_block-active IS INITIAL.
        CLEAR ls_row.
        ls_row-otype = lv_type.
        ls_row-name  = status_text( space ).
        APPEND ls_row TO mt_v5.
        CONTINUE.
      ENDIF.
      READ TABLE ms_res-errors TRANSPORTING NO FIELDS WITH KEY step = lv_step.
      IF sy-subrc = 0.
        CLEAR ls_row.
        ls_row-otype = lv_type.
        ls_row-name  = status_text( gc_st_err ).
        APPEND ls_row TO mt_v5.
        CONTINUE.
      ENDIF.

      LOOP AT ms_res-intfs INTO ls_intf WHERE otype = lv_otype.
        CLEAR ls_row.
        ls_row-otype = lv_type.
        ls_row-name  = ls_intf-name.
        ls_row-itype = ls_intf-itype.
        ls_row-descr = ls_intf-descr.
        ls_row-rel   = ls_intf-rel.
        ls_row-splev = ls_intf-splev.
* Connection type text from the domain fixed values, in the display language
        IF lv_otype = 'R'.
          READ TABLE lt_rtext INTO ls_rtext WITH TABLE KEY itype = ls_intf-itype.
          IF sy-subrc <> 0.
            CLEAR ls_rtext.
            ls_rtext-itype = ls_intf-itype.
            ls_rtext-text  = rollname_text( iv_rollname = 'RFCTYPE_D' iv_value = ls_intf-itype ).
            INSERT ls_rtext INTO TABLE lt_rtext.
          ENDIF.
          ls_row-descr = ls_rtext-text.
        ENDIF.
        IF lv_otype = 'P'.
          ls_row-idocs = num( ls_intf-idocs ).
          IF ls_intf-noprof = gc_x.
            IF ls_row-descr IS INITIAL.
              ls_row-descr = lv_noprof.
            ELSE.
              CONCATENATE ls_row-descr lv_noprof INTO ls_row-descr SEPARATED BY space.
            ENDIF.
          ENDIF.
        ENDIF.
        APPEND ls_row TO mt_v5.
      ENDLOOP.
    ENDDO.
  ENDMETHOD.

* Texts of detail sub keys, read at display time in the display language
  METHOD sub_text.
    DATA: lv_mtart TYPE t134t-mtart,
          lv_mtbez TYPE t134t-mtbez,
          lv_bukrs TYPE t001-bukrs,
          lv_butxt TYPE t001-butxt,
          lv_land1 TYPE t042z-land1,
          lv_zlsch TYPE t042z-zlsch,
          lv_text1 TYPE t042z-text1,
          lv_ktopl TYPE t004t-ktopl,
          lv_ktplt TYPE t004t-ktplt,
          lv_value TYPE c LENGTH 1.

    CASE iv_fkey.
      WHEN 'D10'.                                 " sub key: purchasing document category
        rv_text = rollname_text( iv_rollname = 'EBSTYP' iv_value = iv_sub ).
      WHEN 'D13'.                                 " sub key: order category
        rv_text = rollname_text( iv_rollname = 'AUFTYP' iv_value = iv_sub ).
      WHEN 'D25'.                                 " sub key: user type
        rv_text = rollname_text( iv_rollname = 'XUUSTYP' iv_value = iv_sub ).
      WHEN 'D07' OR 'D08' OR 'D09'.               " sub key: SD document category ("M X" = cancelled)
        lv_value = iv_sub.
        rv_text = domain_text( iv_domain = 'VBTYP' iv_value = lv_value ).
      WHEN 'D21'.                                 " sub key: country/payment method
        SPLIT iv_sub AT '/' INTO lv_land1 lv_zlsch.
        SELECT SINGLE text1 FROM t042z INTO lv_text1
          WHERE land1 = lv_land1
            AND zlsch = lv_zlsch.
        rv_text = lv_text1.
      WHEN 'D27'.                                 " sub key: document status
        lv_value = iv_sub.
        rv_text = domain_text( iv_domain = 'BSTAT' iv_value = lv_value ).
      WHEN 'D01'.
        lv_bukrs = iv_sub.
        SELECT SINGLE butxt FROM t001 INTO lv_butxt
          WHERE bukrs = lv_bukrs.
        rv_text = lv_butxt.
      WHEN 'D28' OR 'D29'.                        " sub key: chart of accounts
        lv_ktopl = iv_sub.
        SELECT SINGLE ktplt FROM t004t INTO lv_ktplt
          WHERE spras = sy-langu
            AND ktopl = lv_ktopl.
        rv_text = lv_ktplt.
      WHEN 'D03'.
        lv_mtart = iv_sub.
        SELECT SINGLE mtbez FROM t134t INTO lv_mtbez
          WHERE spras = sy-langu
            AND mtart = lv_mtart.
        rv_text = lv_mtbez.
    ENDCASE.
  ENDMETHOD.

* Fixed value text of a domain in the display language; sub key '-' stands
* for the value space
  METHOD domain_text.
    DATA: lv_domname TYPE dd07t-domname,
          lv_value   TYPE dd07t-domvalue_l,
          lv_ddtext  TYPE dd07t-ddtext.

    lv_domname = iv_domain.
    lv_value   = iv_value.
    IF lv_value = '-'.
      CLEAR lv_value.
    ENDIF.
    SELECT ddtext FROM dd07t UP TO 1 ROWS INTO lv_ddtext
      WHERE domname    = lv_domname
        AND ddlanguage = sy-langu
        AND as4local   = 'A'
        AND domvalue_l = lv_value.
    ENDSELECT.
    rv_text = lv_ddtext.
  ENDMETHOD.

* Fixed value text via a data element: its domain is read from the dictionary
* (DD04L), not assumed
  METHOD rollname_text.
    DATA: lv_rollname TYPE dd04l-rollname,
          lv_domname  TYPE dd04l-domname.

    lv_rollname = iv_rollname.
    SELECT SINGLE domname FROM dd04l INTO lv_domname
      WHERE rollname = lv_rollname
        AND as4local = 'A'
        AND as4vers  = '0000'.
    IF sy-subrc = 0.
      rv_text = domain_text( iv_domain = lv_domname iv_value = iv_value ).
    ENDIF.
  ENDMETHOD.

  METHOD add_info.
    DATA ls_row TYPE ty_v4.

    ls_row-grp   = lcl_text=>get( 'G00' ).
    ls_row-item  = lcl_text=>get( iv_id ).
    ls_row-value = iv_value.
    APPEND ls_row TO mt_v4.
  ENDMETHOD.

* Cell content of the questionnaire view: N/A by design wins over the status
  METHOD cell.
    IF iv_na = gc_x.
      rv_text = lcl_text=>get( 'S01' ).
    ELSEIF iv_status = gc_st_err.
      rv_text = lcl_text=>get( 'S03' ).
    ELSEIF iv_status = gc_st_ok.
      rv_text = num( iv_num ).
    ELSE.
      rv_text = lcl_text=>get( 'S02' ).
    ENDIF.
  ENDMETHOD.

* Digits only: no thousands separator, no decimals (paste into Excel in any locale)
  METHOD num.
    DATA lv_char TYPE c LENGTH 20.

    lv_char = iv_num.
    CONDENSE lv_char NO-GAPS.
    rv_text = lv_char.
  ENDMETHOD.

  METHOD show_salv.
    DATA: lo_salv    TYPE REF TO cl_salv_table,
          lo_funcs   TYPE REF TO cl_salv_functions_list,
          lo_columns TYPE REF TO cl_salv_columns_table,
          lo_column  TYPE REF TO cl_salv_column,
          lo_display TYPE REF TO cl_salv_display_settings,
          lo_select  TYPE REF TO cl_salv_selections,
          lx_msg     TYPE REF TO cx_salv_msg,
          ls_col     TYPE ty_col,
          lv_found   TYPE ty_flag,
          lv_text    TYPE string,
          lv_long    TYPE scrtext_l,
          lv_medium  TYPE scrtext_m,
          lv_short   TYPE scrtext_s,
          lv_header  TYPE lvc_title.

    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = lo_salv
                                CHANGING  t_table      = ct_table ).
      CATCH cx_salv_msg INTO lx_msg.
        lv_text = lx_msg->get_text( ).
        MESSAGE lv_text TYPE 'I'.
        RETURN.
    ENDTRY.

    lo_funcs = lo_salv->get_functions( ).
    lo_funcs->set_all( gc_x ).

    lo_columns = lo_salv->get_columns( ).
    lo_columns->set_optimize( gc_x ).
    LOOP AT it_cols INTO ls_col.
      lv_found = gc_x.
      TRY.
          lo_column = lo_columns->get_column( ls_col-fname ).
        CATCH cx_salv_not_found.
          CLEAR lv_found.
      ENDTRY.
      IF lv_found IS INITIAL.
        CONTINUE.
      ENDIF.
* Typed variables: SALV methods need an exact type match (design 13.1)
      lv_text   = lcl_text=>get( ls_col-head ).
      lv_long   = lv_text.
      lv_medium = lv_text.
      lv_short  = lv_text.
      lo_column->set_long_text( lv_long ).
      lo_column->set_medium_text( lv_medium ).
      lo_column->set_short_text( lv_short ).
    ENDLOOP.

    lo_display = lo_salv->get_display_settings( ).
    lv_text    = lcl_text=>get( iv_title ).
    lv_header  = lv_text.
    lo_display->set_list_header( lv_header ).
    lo_display->set_striped_pattern( gc_x ).

* Cell selection, so that a block of cells can be copied for pasting
    lo_select = lo_salv->get_selections( ).
    lo_select->set_selection_mode( if_salv_c_selection_mode=>cell ).

    lo_salv->display( ).
  ENDMETHOD.

* Columns that do not fit into the 255-character line wrap to a new line
  METHOD write_table.
    DATA: ls_col  TYPE ty_col,
          lv_pos  TYPE i,
          lv_len  TYPE i,
          lv_end  TYPE i,
          lv_text TYPE c LENGTH 255.
    FIELD-SYMBOLS: <ls_row>   TYPE any,
                   <lv_field> TYPE any.

    SKIP.
    lv_text = lcl_text=>get( iv_title ).
    FORMAT INTENSIFIED ON.
    WRITE / lv_text.
    FORMAT INTENSIFIED OFF.
    ULINE.

    NEW-LINE.
    lv_pos = 1.
    LOOP AT it_cols INTO ls_col.
      lv_len = ls_col-width.
      lv_end = lv_pos + lv_len - 1.
      IF lv_pos > 1 AND lv_end > 255.
        NEW-LINE.
        lv_pos = 5.
      ENDIF.
      lv_text = lcl_text=>get( ls_col-head ).
      WRITE AT lv_pos(lv_len) lv_text.
      lv_pos = lv_pos + lv_len + 1.
    ENDLOOP.
    ULINE.

    LOOP AT it_table ASSIGNING <ls_row>.
      NEW-LINE.
      lv_pos = 1.
      LOOP AT it_cols INTO ls_col.
        ASSIGN COMPONENT ls_col-fname OF STRUCTURE <ls_row> TO <lv_field>.
        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.
        lv_len = ls_col-width.
        lv_end = lv_pos + lv_len - 1.
        IF lv_pos > 1 AND lv_end > 255.
          NEW-LINE.
          lv_pos = 5.
        ENDIF.
        WRITE AT lv_pos(lv_len) <lv_field>.
        lv_pos = lv_pos + lv_len + 1.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Program flow (design 5)
*----------------------------------------------------------------------*
CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS on_init.
    CLASS-METHODS on_check.
    CLASS-METHODS on_start.
    CLASS-METHODS on_end.
  PRIVATE SECTION.
    CLASS-DATA: gs_result TYPE ty_result,
                gv_loaded TYPE ty_flag.
    CLASS-METHODS show_msg
      IMPORTING iv_id   TYPE c
                iv_type TYPE c
                iv_add  TYPE string OPTIONAL.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.

  METHOD on_init.
    DATA: lv_from TYPE d,
          lv_to   TYPE d.

    lcl_text=>load( ).
    gv_tb01 = lcl_text=>get( 'T01' ).
    gv_tb02 = lcl_text=>get( 'T02' ).
    gv_tb03 = lcl_text=>get( 'T03' ).
    gv_tb04 = lcl_text=>get( 'T04' ).
    lcl_period=>effective( EXPORTING iv_datfr = p_datfr
                                     iv_datto = p_datto
                           IMPORTING ev_datfr = lv_from
                                     ev_datto = lv_to ).
    p_datfr = lv_from.
    p_datto = lv_to.
  ENDMETHOD.

  METHOD on_check.
    DATA: lv_from   TYPE d,
          lv_to     TYPE d,
          lv_msgid  TYPE ty_textid,
          lv_exists TYPE ty_flag,
          lv_text   TYPE string.

    IF p_coll = gc_x.
* Empty dates are valid: they are replaced by the default period at runtime
      lcl_period=>effective( EXPORTING iv_datfr = p_datfr
                                       iv_datto = p_datto
                             IMPORTING ev_datfr = lv_from
                                       ev_datto = lv_to ).
      lv_msgid = lcl_period=>check( iv_datfr = lv_from iv_datto = lv_to ).
      IF lv_msgid IS NOT INITIAL.
        lv_text = lcl_text=>get( lv_msgid ).
        IF lv_text IS INITIAL.
          lv_text = lv_msgid.
        ENDIF.
        MESSAGE lv_text TYPE 'E'.
      ENDIF.
    ELSEIF p_show = gc_x.
      lv_exists = lcl_store=>exists( ).
      IF lv_exists IS INITIAL.
        lv_text = lcl_text=>get( 'M05' ).
        IF lv_text IS INITIAL.
          lv_text = 'M05'.
        ENDIF.
        MESSAGE lv_text TYPE 'E'.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD on_start.
    DATA: lo_coll    TYPE REF TO lcl_collector,
          ls_scope   TYPE ty_scope,
          lv_from    TYPE d,
          lv_to      TYPE d,
          lv_rc      TYPE i,
          lv_missing TYPE string,
          lv_len     TYPE i,
          lv_short   TYPE c LENGTH 180,
          lv_date    TYPE c LENGTH 10,
          lv_time    TYPE c LENGTH 8,
          lv_add     TYPE string.

* Completeness of the text pool (replaces the extended check, design 12.3)
    lv_missing = lcl_text=>get_missing( ).
    IF lv_missing IS NOT INITIAL.
      lv_len = strlen( lv_missing ).
      IF lv_len > 180.
        lv_short = lv_missing.
        CONCATENATE lv_short '...' INTO lv_missing SEPARATED BY space.
      ENDIF.
      show_msg( iv_id = 'M11' iv_type = 'S' iv_add = lv_missing ).
    ENDIF.

    IF p_coll = gc_x.
      lcl_period=>effective( EXPORTING iv_datfr = p_datfr
                                       iv_datto = p_datto
                             IMPORTING ev_datfr = lv_from
                                       ev_datto = lv_to ).
      ls_scope-md   = p_md.
      ls_scope-fi   = p_fi.
      ls_scope-sd   = p_sd.
      ls_scope-mm   = p_mm.
      ls_scope-pp   = p_pp.
      ls_scope-org  = p_org.
      ls_scope-intf = p_intf.
      CREATE OBJECT lo_coll
        EXPORTING
          iv_datfr = lv_from
          iv_datto = lv_to.
      lo_coll->run( ls_scope ).
      gs_result = lo_coll->get_result( ).
      gv_loaded = gc_x.
      IF p_store = gc_x.
        GET TIME.
        gs_result-meta-stored_d = sy-datum.
        gs_result-meta-stored_t = sy-uzeit.
        lcl_store=>save( gs_result ).
        show_msg( iv_id = 'M06' iv_type = 'S' ).
      ENDIF.
      show_msg( iv_id = 'M10' iv_type = 'S' ).

    ELSEIF p_show = gc_x.
      lcl_store=>load( IMPORTING es_result = gs_result
                                 ev_rc     = lv_rc ).
      CASE lv_rc.
        WHEN 0.
          gv_loaded = gc_x.
          WRITE gs_result-meta-stored_d TO lv_date.
          WRITE gs_result-meta-stored_t TO lv_time.
          CONCATENATE lv_date lv_time INTO lv_add SEPARATED BY space.
          show_msg( iv_id = 'M09' iv_type = 'S' iv_add = lv_add ).
        WHEN 4.
          show_msg( iv_id = 'M05' iv_type = 'S' ).
        WHEN OTHERS.
          show_msg( iv_id = 'M13' iv_type = 'S' ).
      ENDCASE.

    ELSE.
      lcl_store=>delete( ).
      show_msg( iv_id = 'M07' iv_type = 'S' ).
    ENDIF.
  ENDMETHOD.

  METHOD on_end.
    DATA: lo_output TYPE REF TO lcl_output,
          lv_view   TYPE i.

    IF gv_loaded IS INITIAL.
      RETURN.
    ENDIF.
    CREATE OBJECT lo_output
      EXPORTING
        is_result = gs_result.
    IF sy-batch = gc_x.
      lo_output->write_all( ).
    ELSE.
      IF p_v2 = gc_x.
        lv_view = 2.
      ELSEIF p_v3 = gc_x.
        lv_view = 3.
      ELSEIF p_v4 = gc_x.
        lv_view = 4.
      ELSEIF p_v5 = gc_x.
        lv_view = 5.
      ELSE.
        lv_view = 1.
      ENDIF.
      lo_output->display( lv_view ).
    ENDIF.
  ENDMETHOD.

  METHOD show_msg.
    DATA lv_text TYPE string.

    lv_text = lcl_text=>get( iv_id ).
    IF lv_text IS INITIAL.
      lv_text = iv_id.
    ENDIF.
    IF iv_add IS NOT INITIAL.
      CONCATENATE lv_text iv_add INTO lv_text SEPARATED BY space.
    ENDIF.
    MESSAGE lv_text TYPE iv_type.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Events
*----------------------------------------------------------------------*
INITIALIZATION.
  lcl_app=>on_init( ).

AT SELECTION-SCREEN.
  lcl_app=>on_check( ).

START-OF-SELECTION.
  lcl_app=>on_start( ).

END-OF-SELECTION.
  lcl_app=>on_end( ).
