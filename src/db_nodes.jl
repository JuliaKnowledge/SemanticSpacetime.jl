#=
Database node operations for Semantic Spacetime.

Idempotent node creation, upload, and management against PostgreSQL.

Ported from SSTorytime/pkg/SSTorytime/SSTorytime.go.
=#

# ──────────────────────────────────────────────────────────────────
# SQL formatting helpers
# ──────────────────────────────────────────────────────────────────

"""Format a NodePtr as a PostgreSQL composite literal."""
format_nodeptr(np::NodePtr) = "($(np.class),$(np.cptr))"

"""Format a Link as a PostgreSQL composite literal."""
function format_link(lnk::Link)
    "($(lnk.arr),$(lnk.wgt),$(lnk.ctx),$(format_nodeptr(lnk.dst)))"
end

"""Format a Node for SQL INSERT."""
function form_db_node(n::Node)
    es = sql_escape(n.s)
    ec = sql_escape(n.chap)
    np = format_nodeptr(n.nptr)
    seq = n.seq ? "true" : "false"

    # Format link arrays
    links = String[]
    for i in 1:ST_TOP
        arr = n.incidence[i]
        if isempty(arr)
            push!(links, "NULL")
        else
            items = [format_link(l) for l in arr]
            push!(links, "'{" * join(items, ",") * "}'")
        end
    end

    return """INSERT INTO Node (NPtr, L, S, Chap, Seq, Im3, Im2, Im1, In0, Il1, Ic2, Ie3)
              VALUES ('$(np)'::NodePtr, $(n.l), '$(es)', '$(ec)', $(seq),
              $(join(links, ", ")))"""
end

# ──────────────────────────────────────────────────────────────────
# Node operations
# ──────────────────────────────────────────────────────────────────

"""
    create_db_node!(sst::SSTConnection, n::Node) -> Node

Create a new node in the database. Sets the node's NPtr based on
the next available ClassedNodePtr for its size class.
"""
function create_db_node!(sst::SSTConnection, n::Node)
    class = n_channel(n.s)

    # Get next available pointer for this class
    result = execute_sql_strict(sst.conn,
        "SELECT COALESCE(MAX((NPtr).CPtr), 0) + 1 FROM Node WHERE (NPtr).Chan = $class")
    row = first(LibPQ.Columns(result))
    next_cptr = row[1]::Int32 |> Int

    n.nptr = NodePtr(class, next_cptr)

    sql = form_db_node(n)
    execute_sql_strict(sst.conn, sql)

    return n
end

"""
    idemp_db_add_node!(sst::SSTConnection, n::Node) -> Node

Idempotently add a node to the database. If a node with the same text
already exists, returns the existing node (with its NPtr). Otherwise
creates a new one.
"""
function idemp_db_add_node!(sst::SSTConnection, n::Node)
    es = sql_escape(n.s)

    # Check if node already exists
    result = execute_sql_strict(sst.conn,
        "SELECT NPtr, L, Chap, Seq FROM Node WHERE S = '$(es)' LIMIT 1")
    cols = LibPQ.Columns(result)

    if !isempty(cols) && length(first(cols)) > 0
        row = first(cols)
        # Parse the NPtr from the result
        nptr_str = row[1]
        n.nptr = parse_nodeptr(string(nptr_str))
        return n
    end

    return create_db_node!(sst, n)
end

"""
    upload_node_to_db!(sst::SSTConnection, n::Node)

Upload a fully formed node (with all links) to the database.
Used during bulk graph_to_db operations.
"""
function upload_node_to_db!(sst::SSTConnection, n::Node)
    sql = form_db_node(n)
    execute_sql(sst, sql)
    nothing
end

"""
    upload_arrow_to_db!(sst::SSTConnection, arrow::ArrowEntry)

Upload an arrow directory entry to the database.
"""
function upload_arrow_to_db!(sst::SSTConnection, arrow::ArrowEntry)
    es = sql_escape(arrow.short)
    el = sql_escape(arrow.long)
    execute_sql(sst,
        """INSERT INTO ArrowDirectory (STAindex, Long, Short, ArrPtr)
           VALUES ($(arrow.stindex), '$(el)', '$(es)', $(arrow.ptr))
           ON CONFLICT (ArrPtr) DO NOTHING""")
    nothing
end

"""
    upload_inverse_arrow_to_db!(sst::SSTConnection, fwd::ArrowPtr, bwd::ArrowPtr)

Upload an inverse arrow relationship to the database.
"""
function upload_inverse_arrow_to_db!(sst::SSTConnection, fwd::ArrowPtr, bwd::ArrowPtr)
    execute_sql(sst,
        """INSERT INTO ArrowInverses (Plus, Minus)
           VALUES ($fwd, $bwd)
           ON CONFLICT DO NOTHING""")
    nothing
end

"""
    upload_contexts_to_db!(sst::SSTConnection)

Upload all registered contexts to the database.
"""
function upload_contexts_to_db!(sst::SSTConnection)
    for entry in _CONTEXT_DIRECTORY
        isempty(entry.context) && continue
        upload_context_to_db!(sst, entry.context, entry.ptr)
    end
    nothing
end

"""
    upload_context_to_db!(sst::SSTConnection, ctx::String, ptr::ContextPtr)

Upload a single context entry to the database.
"""
function upload_context_to_db!(sst::SSTConnection, ctx::String, ptr::ContextPtr)
    isempty(ctx) && return nothing
    ec = sql_escape(ctx)
    execute_sql(sst,
        "SELECT IdempInsertContext('$(ec)', $(ptr))")
    nothing
end

# ──────────────────────────────────────────────────────────────────
# Parsing helpers
# ──────────────────────────────────────────────────────────────────

"""
    parse_nodeptr(s::AbstractString) -> NodePtr

Parse a PostgreSQL NodePtr composite literal like "(1,42)" into a NodePtr.
"""
function parse_nodeptr(s::AbstractString)
    cleaned = strip(s, ['(', ')', ' '])
    parts = split(cleaned, ',')
    length(parts) == 2 || error("Cannot parse NodePtr from: $s")
    return NodePtr(parse(Int, strip(parts[1])), parse(Int, strip(parts[2])))
end
