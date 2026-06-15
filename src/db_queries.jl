#=
Database query operations for Semantic Spacetime.

Functions for looking up nodes, chapters, contexts, and
stories from the PostgreSQL database.

Ported from SSTorytime/pkg/SSTorytime/SSTorytime.go.
=#

# ──────────────────────────────────────────────────────────────────
# Node queries
# ──────────────────────────────────────────────────────────────────

"""
    get_db_node_ptr_matching_name(sst::SSTConnection, name::String, chap::String="") -> Vector{NodePtr}

Find nodes whose text matches `name`, optionally filtered by chapter.
Uses PostgreSQL TSVECTOR search for matching.
"""
function get_db_node_ptr_matching_name(sst::SSTConnection, name::String, chap::String="")
    en = sql_escape(name)
    ptrs = NodePtr[]

    sql = if isempty(chap)
        "SELECT NPtr FROM Node WHERE S = '$(en)'"
    else
        ec = sql_escape(chap)
        "SELECT NPtr FROM Node WHERE S = '$(en)' AND Chap LIKE '%$(ec)%'"
    end

    result = execute_sql_strict(sst.conn, sql)
    # LibPQ.columntable returns a NamedTuple of column vectors; the first
    # column holds every matching NPtr (iterating LibPQ.Columns instead yields
    # columns, and would silently return only the first match).
    ct = LibPQ.columntable(result)
    if !isempty(ct)
        for v in ct[1]
            push!(ptrs, parse_nodeptr(string(v)))
        end
    end

    return ptrs
end

"""
    get_db_node_by_nodeptr(sst::SSTConnection, nptr::NodePtr) -> Node

Retrieve a full node from the database by its NodePtr.
"""
function get_db_node_by_nodeptr(sst::SSTConnection, nptr::NodePtr)
    np = format_nodeptr(nptr)
    sql = "SELECT S, L, Chap, Seq, Im3, Im2, Im1, In0, Il1, Ic2, Ie3 FROM Node WHERE NPtr = '$(np)'::NodePtr"

    result = execute_sql_strict(sst.conn, sql)
    ct = LibPQ.columntable(result)

    # ct[c][r]: column c (1=S,2=L,3=Chap,4=Seq,5..11=Im3..Ie3), row r.
    if isempty(ct) || isempty(ct[1])
        return Node()
    end

    if length(ct[1]) > 1
        @warn "get_db_node_by_nodeptr returned multiple matches; using the first" nptr count=length(ct[1])
    end

    # Expand any dynamic in-built functions (e.g. "Dynamic: {TimeSince ...}")
    # on read, matching Go's GetDBNodeByNodePtr.
    node = Node(expand_dynamic_functions(string(ct[1][1])), string(ct[3][1]))
    node.l = Int(ct[2][1])
    node.seq = something(ct[4][1], false)
    node.nptr = nptr

    # Parse link arrays for each ST channel
    for i in 1:ST_TOP
        col_val = ct[4 + i][1]
        if !isnothing(col_val) && !ismissing(col_val)
            node.incidence[i] = parse_link_array(string(col_val))
        end
    end

    return node
end

# ──────────────────────────────────────────────────────────────────
# Chapter queries
# ──────────────────────────────────────────────────────────────────

"""
    get_db_chapters_matching_name(sst::SSTConnection, src::String) -> Vector{String}

Find chapters whose names match (or contain) `src`.
"""
function get_db_chapters_matching_name(sst::SSTConnection, src::String)
    es = sql_escape(src)
    sql = "SELECT DISTINCT Chap FROM Node WHERE Chap LIKE '%$(es)%' ORDER BY Chap"
    result = execute_sql_strict(sst.conn, sql)
    chapters = String[]
    ct = LibPQ.columntable(result)
    if !isempty(ct)
        for v in ct[1]
            push!(chapters, string(v))
        end
    end
    return chapters
end

# ──────────────────────────────────────────────────────────────────
# Context queries
# ──────────────────────────────────────────────────────────────────

"""
    get_db_context_by_name(sst::SSTConnection, src::String) -> (String, ContextPtr)

Look up a context by name. Returns ("", -1) if not found.
"""
function get_db_context_by_name(sst::SSTConnection, src::String)
    es = sql_escape(src)
    sql = "SELECT DISTINCT Context, CtxPtr FROM ContextDirectory WHERE Context = '$(es)'"
    result = execute_sql_strict(sst.conn, sql)
    ct = LibPQ.columntable(result)

    if isempty(ct) || isempty(ct[1])
        return ("", ContextPtr(-1))
    end

    return (string(ct[1][1]), Int(ct[2][1]))
end

"""
    get_db_context_by_ptr(sst::SSTConnection, ptr::ContextPtr) -> (String, ContextPtr)

Look up a context by pointer. Returns ("", -1) if not found.
"""
function get_db_context_by_ptr(sst::SSTConnection, ptr::ContextPtr)
    sql = "SELECT Context, CtxPtr FROM ContextDirectory WHERE CtxPtr = $(ptr)"
    result = execute_sql_strict(sst.conn, sql)
    ct = LibPQ.columntable(result)

    if isempty(ct) || isempty(ct[1])
        return ("", ContextPtr(-1))
    end

    return (string(ct[1][1]), Int(ct[2][1]))
end

# ──────────────────────────────────────────────────────────────────
# Idempotent DDL helpers
# ──────────────────────────────────────────────────────────────────

"""
    create_type(sst::SSTConnection, defn::AbstractString) -> Bool

Create a PostgreSQL type (idempotent — ignores "already exists" errors).
"""
function create_type(sst::SSTConnection, defn::AbstractString)::Bool
    execute_sql(sst, defn)
    return true
end

"""
    create_table(sst::SSTConnection, defn::AbstractString) -> Bool

Create a PostgreSQL table (idempotent — ignores "already exists" errors).
"""
function create_table(sst::SSTConnection, defn::AbstractString)::Bool
    execute_sql(sst, defn)
    return true
end

# ──────────────────────────────────────────────────────────────────
# Link array parsing
# ──────────────────────────────────────────────────────────────────

"""
    parse_link_array(s::AbstractString) -> Vector{Link}

Parse a PostgreSQL Link[] array literal into a vector of Links.
Format: `{"(arr,wgt,ctx,\\"(chan,cptr)\\")",...}`
"""
function parse_link_array(s::AbstractString)
    links = Link[]
    cleaned = strip(s, ['{', '}', ' '])
    isempty(cleaned) && return links

    # Split on the link boundaries
    # Each link looks like: "(arr,wgt,ctx,"(chan,cptr)")"
    # or with escaped quotes in PostgreSQL output
    i = 1
    while i <= length(cleaned)
        # Find start of a link tuple
        start = findnext('(', cleaned, i)
        isnothing(start) && break

        # Count nested parens to find the end
        depth = 0
        j = start
        while j <= length(cleaned)
            if cleaned[j] == '('
                depth += 1
            elseif cleaned[j] == ')'
                depth -= 1
                if depth == 0
                    break
                end
            end
            j += 1
        end

        # Extract and parse the tuple
        tuple_str = cleaned[start:j]
        link = try_parse_link(tuple_str)
        if !isnothing(link)
            push!(links, link)
        end

        i = j + 1
    end

    return links
end

"""
    try_parse_link(s::AbstractString) -> Union{Link, Nothing}

Try to parse a single Link from a PostgreSQL composite literal.
"""
function try_parse_link(s::AbstractString)
    # Remove outer parens and quotes
    inner = strip(s, ['(', ')', '"', ' '])
    # Split carefully: arr,wgt,ctx,"(chan,cptr)"
    parts = String[]
    depth = 0
    current = IOBuffer()
    for ch in inner
        if ch == '(' || ch == '"'
            depth += 1
            write(current, ch)
        elseif ch == ')' || (ch == '"' && depth > 0)
            depth -= 1
            write(current, ch)
        elseif ch == ',' && depth == 0
            push!(parts, String(take!(current)))
        else
            write(current, ch)
        end
    end
    push!(parts, String(take!(current)))

    length(parts) >= 4 || return nothing

    try
        arr = parse(Int, strip(parts[1]))
        wgt = parse(Float32, strip(parts[2]))
        ctx = parse(Int, strip(parts[3]))
        dst_str = strip(join(parts[4:end], ","), ['"', ' '])
        dst = parse_nodeptr(dst_str)
        return Link(arr, wgt, ctx, dst)
    catch
        return nothing
    end
end
