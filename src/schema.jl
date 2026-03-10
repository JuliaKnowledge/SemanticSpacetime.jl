#=
Database schema creation for Semantic Spacetime.

Creates PostgreSQL custom types, tables, and stored functions
needed by SSTorytime. All operations are idempotent.

Ported from SSTorytime/pkg/SSTorytime/SSTorytime.go.
=#

# ──────────────────────────────────────────────────────────────────
# Type definitions
# ──────────────────────────────────────────────────────────────────

const SQL_NODEPTR_TYPE = """
CREATE TYPE NodePtr AS (
    Chan  int,
    CPtr  int
)
"""

const SQL_LINK_TYPE = """
CREATE TYPE Link AS (
    Arr  int,
    Wgt  real,
    Ctx  int,
    Dst  NodePtr
)
"""

const SQL_APPOINTMENT_TYPE = """
CREATE TYPE Appointment AS (
    Arr    int,
    STType int,
    Chap   text,
    Ctx    int,
    NTo    NodePtr,
    NFrom  NodePtr[]
)
"""

# ──────────────────────────────────────────────────────────────────
# Table definitions
# ──────────────────────────────────────────────────────────────────

const SQL_NODE_TABLE = """
CREATE UNLOGGED TABLE IF NOT EXISTS Node (
    NPtr      NodePtr,
    L         int,
    S         text,
    Search    TSVECTOR GENERATED ALWAYS AS (to_tsvector('english', S)) STORED,
    UnSearch  TSVECTOR GENERATED ALWAYS AS (to_tsvector('english', sst_unaccent(S))) STORED,
    Chap      text,
    Seq       boolean,
    Im3       Link[],
    Im2       Link[],
    Im1       Link[],
    In0       Link[],
    Il1       Link[],
    Ic2       Link[],
    Ie3       Link[]
)
"""

const SQL_PAGEMAP_TABLE = """
CREATE UNLOGGED TABLE IF NOT EXISTS PageMap (
    Chap  text,
    Alias text,
    Ctx   int,
    Line  int,
    Path  Link[]
)
"""

const SQL_ARROW_DIRECTORY_TABLE = """
CREATE UNLOGGED TABLE IF NOT EXISTS ArrowDirectory (
    STAindex  int,
    Long      text,
    Short     text,
    ArrPtr    int PRIMARY KEY
)
"""

const SQL_ARROW_INVERSES_TABLE = """
CREATE UNLOGGED TABLE IF NOT EXISTS ArrowInverses (
    Plus    int,
    Minus   int,
    PRIMARY KEY(Plus, Minus)
)
"""

const SQL_LASTSEEN_TABLE = """
CREATE TABLE IF NOT EXISTS LastSeen (
    Section text,
    NPtr    NodePtr,
    First   timestamp,
    Last    timestamp,
    Delta   real,
    Freq    int
)
"""

const SQL_CONTEXT_DIRECTORY_TABLE = """
CREATE TABLE IF NOT EXISTS ContextDirectory (
    Context  text,
    CtxPtr   int PRIMARY KEY
)
"""

# ──────────────────────────────────────────────────────────────────
# Stored functions
# ──────────────────────────────────────────────────────────────────

const SQL_SST_UNACCENT = """
CREATE OR REPLACE FUNCTION sst_unaccent(text)
RETURNS text AS \$\$
    SELECT unaccent(\$1)
\$\$ LANGUAGE SQL IMMUTABLE STRICT
"""

const SQL_IDEMP_INSERT_CONTEXT = """
CREATE OR REPLACE FUNCTION IdempInsertContext(ctx text, cptr int)
RETURNS int AS \$\$
DECLARE
    existing_ptr int;
    new_ptr int;
BEGIN
    SELECT CtxPtr INTO existing_ptr FROM ContextDirectory WHERE Context = ctx;
    IF FOUND THEN
        RETURN existing_ptr;
    END IF;
    IF cptr < 0 THEN
        SELECT COALESCE(MAX(CtxPtr), 0) + 1 INTO new_ptr FROM ContextDirectory;
    ELSE
        new_ptr := cptr;
    END IF;
    INSERT INTO ContextDirectory (Context, CtxPtr) VALUES (ctx, new_ptr)
        ON CONFLICT (CtxPtr) DO NOTHING;
    RETURN new_ptr;
END;
\$\$ LANGUAGE plpgsql
"""

const SQL_IDEMP_APPEND_NODE = """
CREATE OR REPLACE FUNCTION IdempAppendNode(len int, chan int, txt text, chap text)
RETURNS text AS \$\$
DECLARE
    existing_nptr NodePtr;
    new_cptr int;
    new_nptr NodePtr;
BEGIN
    SELECT NPtr INTO existing_nptr FROM Node WHERE S = txt LIMIT 1;
    IF FOUND THEN
        RETURN '(' || (existing_nptr).Chan || ',' || (existing_nptr).CPtr || ')';
    END IF;
    SELECT COALESCE(MAX((NPtr).CPtr), 0) + 1 INTO new_cptr
        FROM Node WHERE (NPtr).Chan = chan;
    new_nptr := ROW(chan, new_cptr)::NodePtr;
    INSERT INTO Node (NPtr, L, S, Chap, Seq)
        VALUES (new_nptr, len, txt, chap, false);
    RETURN '(' || chan || ',' || new_cptr || ')';
END;
\$\$ LANGUAGE plpgsql
"""

# ──────────────────────────────────────────────────────────────────
# Schema creation
# ──────────────────────────────────────────────────────────────────

"""
    create_schema!(sst::SSTConnection)

Create all PostgreSQL types, tables, and stored functions needed
by Semantic Spacetime. All operations are idempotent.
"""
function create_schema!(sst::SSTConnection)
    # Create the unaccent extension (requires contrib)
    execute_sql(sst, "CREATE EXTENSION IF NOT EXISTS unaccent")

    # Create custom types
    execute_sql(sst, SQL_NODEPTR_TYPE)
    execute_sql(sst, SQL_LINK_TYPE)
    execute_sql(sst, SQL_APPOINTMENT_TYPE)

    # Create tables
    execute_sql(sst, SQL_NODE_TABLE)
    execute_sql(sst, SQL_PAGEMAP_TABLE)
    execute_sql(sst, SQL_ARROW_DIRECTORY_TABLE)
    execute_sql(sst, SQL_ARROW_INVERSES_TABLE)
    execute_sql(sst, SQL_LASTSEEN_TABLE)
    execute_sql(sst, SQL_CONTEXT_DIRECTORY_TABLE)

    # Create stored functions
    execute_sql(sst, SQL_SST_UNACCENT)
    execute_sql(sst, SQL_IDEMP_INSERT_CONTEXT)
    execute_sql(sst, SQL_IDEMP_APPEND_NODE)

    nothing
end
