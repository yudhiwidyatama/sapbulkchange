" Database access used by the engine; replaced by a test double in ABAP Unit.
INTERFACE zif_fi_db_provider PUBLIC.

  TYPES: BEGIN OF ty_line,
           belnr TYPE belnr_d,
           gjahr TYPE gjahr,
           buzei TYPE buzei,
           racct TYPE racct,
           blart TYPE blart,
           budat TYPE budat,
           zuonr TYPE dzuonr,
           augbl TYPE augbl,
         END OF ty_line,
         tt_line TYPE SORTED TABLE OF ty_line WITH NON-UNIQUE KEY belnr gjahr buzei.

  TYPES: BEGIN OF ty_doc_key,
           belnr TYPE belnr_d,
           gjahr TYPE gjahr,
         END OF ty_doc_key,
         tt_doc_key TYPE STANDARD TABLE OF ty_doc_key WITH EMPTY KEY.

  TYPES: BEGIN OF ty_lock,
           belnr TYPE belnr_d,
           gjahr TYPE gjahr,
           owner TYPE sy-uname,
         END OF ty_lock,
         tt_lock TYPE SORTED TABLE OF ty_lock WITH NON-UNIQUE KEY belnr gjahr.

  " ACDOCA lines of the given documents; BUZEI = last 3 characters of DOCLN.
  METHODS read_lines
    IMPORTING iv_bukrs        TYPE bukrs
              iv_rldnr        TYPE fins_ledger
              it_doc_keys     TYPE tt_doc_key
    RETURNING VALUE(rt_lines) TYPE tt_line.

  " All current BKPF enqueue locks of the company code (one ENQUEUE_READ call).
  METHODS read_locks
    IMPORTING iv_bukrs        TYPE bukrs
    RETURNING VALUE(rt_locks) TYPE tt_lock.

ENDINTERFACE.
