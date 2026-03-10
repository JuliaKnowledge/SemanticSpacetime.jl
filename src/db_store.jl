#=
DBInterface.jl-based database store for Semantic Spacetime.

Provides a portable SQL backend that works with any DBInterface-compatible
database (SQLite, DuckDB, PostgreSQL via LibPQ, etc.).

Uses normalized relational tables instead of PostgreSQL-specific array columns.
=#

import DBInterface

"""
    DBStore <: AbstractSSTStore

Database-backed graph store using DBInterface.jl for portable SQL access.
Works with SQLite, DuckDB, or any DBInterface-compatible connection.

# Example
```julia
using SQLite
db = SQLite.DB(":memory:")
store = DBStore(db)
db_vertex!(store, "hello", "ch1")
```
"""
mutable struct DBStore <: AbstractSSTStore
    conn::Any  # DBInterface-compatible connection
    configured::Bool
    # In-memory caches for performance
    _node_cache::Dict{NodePtr, Node}
    _name_cache::Dict{String, Vector{NodePtr}}
end

"""
    DBStore(conn; configure::Bool=true)

Create a DBStore wrapping a DBInterface-compatible connection.
If `configure=true`, creates the schema tables immediately.
"""
function DBStore(conn; configure::Bool=true)
    store = DBStore(conn, false, Dict{NodePtr,Node}(), Dict{String,Vector{NodePtr}}())
    configure && create_db_schema!(store)
    return store
end

# ──────────────────────────────────────────────────────────────────
# Schema (portable SQL, no PostgreSQL-specific features)
# ──────────────────────────────────────────────────────────────────

const DBSTORE_SCHEMA = [
    """CREATE TABLE IF NOT EXISTS sst_nodes (
        class     INTEGER NOT NULL,
        cptr      INTEGER NOT NULL,
        len       INTEGER NOT NULL,
        text      TEXT NOT NULL,
        chapter   TEXT NOT NULL DEFAULT '',
        seq       INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (class, cptr)
    )""",
    """CREATE TABLE IF NOT EXISTS sst_links (
        src_class   INTEGER NOT NULL,
        src_cptr    INTEGER NOT NULL,
        dst_class   INTEGER NOT NULL,
        dst_cptr    INTEGER NOT NULL,
        arrow       INTEGER NOT NULL,
        weight      REAL NOT NULL DEFAULT 1.0,
        context     INTEGER NOT NULL DEFAULT 0,
        sttype      INTEGER NOT NULL,
        FOREIGN KEY (src_class, src_cptr) REFERENCES sst_nodes(class, cptr),
        FOREIGN KEY (dst_class, dst_cptr) REFERENCES sst_nodes(class, cptr)
    )""",
    """CREATE TABLE IF NOT EXISTS sst_arrows (
        ptr       INTEGER PRIMARY KEY,
        stindex   INTEGER NOT NULL,
        short     TEXT NOT NULL,
        long      TEXT NOT NULL
    )""",
    """CREATE TABLE IF NOT EXISTS sst_arrow_inverses (
        fwd INTEGER NOT NULL,
        bwd INTEGER NOT NULL,
        PRIMARY KEY (fwd, bwd)
    )""",
    """CREATE TABLE IF NOT EXISTS sst_contexts (
        ptr     INTEGER PRIMARY KEY,
        context TEXT NOT NULL
    )""",
    """CREATE TABLE IF NOT EXISTS sst_pagemap (
        chapter TEXT NOT NULL,
        alias   TEXT NOT NULL DEFAULT '',
        context INTEGER NOT NULL DEFAULT 0,
        line    INTEGER NOT NULL,
        path    TEXT NOT NULL DEFAULT ''
    )""",
    """CREATE TABLE IF NOT EXISTS sst_lastseen (
        section   TEXT NOT NULL,
        class     INTEGER NOT NULL DEFAULT 0,
        cptr      INTEGER NOT NULL DEFAULT 0,
        first_ts  REAL NOT NULL,
        last_ts   REAL NOT NULL,
        delta     REAL NOT NULL DEFAULT 0,
        freq      INTEGER NOT NULL DEFAULT 0
    )""",
    # Indices for performance
    "CREATE INDEX IF NOT EXISTS idx_nodes_text ON sst_nodes(text)",
    "CREATE INDEX IF NOT EXISTS idx_nodes_chapter ON sst_nodes(chapter)",
    "CREATE INDEX IF NOT EXISTS idx_links_src ON sst_links(src_class, src_cptr)",
    "CREATE INDEX IF NOT EXISTS idx_links_dst ON sst_links(dst_class, dst_cptr)",
    "CREATE INDEX IF NOT EXISTS idx_links_arrow ON sst_links(arrow)",
    "CREATE INDEX IF NOT EXISTS idx_links_sttype ON sst_links(sttype)",
]

function create_db_schema!(store::DBStore)
    for sql in DBSTORE_SCHEMA
        DBInterface.execute(store.conn, sql)
    end
    store.configured = true
    nothing
end

# Helper to extract rows from a DBInterface result into a Vector of Tuples.
# SQLite.jl Row objects are cursor-based and invalidated after iteration,
# so we must copy values during the iteration pass.
function _collect_rows(result)
    rows = Vector{Vector{Any}}()
    for row in result
        vals = Any[]
        for i in 1:length(row)
            v = row[i]
            push!(vals, v === missing ? nothing : v)
        end
        push!(rows, vals)
    end
    return rows
end

# Helper to get a single scalar from a query
function _scalar(store::DBStore, sql::AbstractString, params=Any[])
    result = DBInterface.execute(store.conn, sql, params)
    for row in result
        v = row[1]
        return v === missing ? nothing : v
    end
    return nothing
end

# ──────────────────────────────────────────────────────────────────
# Node operations
# ──────────────────────────────────────────────────────────────────

"""
    db_vertex!(store::DBStore, name::AbstractString, chap::AbstractString) -> Node

Create or retrieve a node. Idempotent.
"""
function db_vertex!(store::DBStore, name::AbstractString, chap::AbstractString)
    sname = String(name)
    schap = String(chap)

    # Check cache first
    if haskey(store._name_cache, sname)
        nptr = first(store._name_cache[sname])
        return store._node_cache[nptr]
    end

    # Check database
    rows = _collect_rows(DBInterface.execute(store.conn,
        "SELECT class, cptr, len, chapter, seq FROM sst_nodes WHERE text = ? LIMIT 1",
        [sname]))

    if !isempty(rows)
        row = first(rows)
        nptr = NodePtr(Int(row[1]), Int(row[2]))
        node = Node(sname, String(row[4]))
        node.l = Int(row[3])
        node.nptr = nptr
        node.seq = row[5] != 0
        _cache_node!(store, node)
        return node
    end

    # Create new node
    class = n_channel(sname)
    # Get next cptr for this class
    v = _scalar(store, "SELECT COALESCE(MAX(cptr), 0) + 1 FROM sst_nodes WHERE class = ?", [class])
    next_cptr = isnothing(v) ? 1 : Int(v)

    node = Node(sname, schap)
    node.nptr = NodePtr(class, next_cptr)
    node.l = length(sname)

    DBInterface.execute(store.conn,
        "INSERT INTO sst_nodes (class, cptr, len, text, chapter, seq) VALUES (?, ?, ?, ?, ?, ?)",
        [class, next_cptr, node.l, sname, schap, 0])

    _cache_node!(store, node)
    return node
end

function _cache_node!(store::DBStore, node::Node)
    store._node_cache[node.nptr] = node
    if !haskey(store._name_cache, node.s)
        store._name_cache[node.s] = NodePtr[]
    end
    if node.nptr ∉ store._name_cache[node.s]
        push!(store._name_cache[node.s], node.nptr)
    end
end

# ──────────────────────────────────────────────────────────────────
# Edge operations
# ──────────────────────────────────────────────────────────────────

"""
    db_edge!(store::DBStore, from::Node, arrow::AbstractString, to::Node;
             context::Vector{String}=String[], weight::Float32=1.0f0)

Create a directed link between two nodes. Also creates the inverse link.
"""
function db_edge!(store::DBStore, from::Node, arrow::AbstractString, to::Node;
                  context::Vector{String}=String[], weight::Float32=1.0f0)
    entry = get_arrow_by_name(arrow)
    isnothing(entry) && error("No such arrow '$(arrow)'")

    sttype = index_to_sttype(entry.stindex)
    ctx_ptr = isempty(context) ? ContextPtr(0) : try_context(context)

    # Insert forward link (idempotent)
    _db_insert_link!(store, from.nptr, to.nptr, entry.ptr, weight, ctx_ptr, sttype)

    # Insert inverse link
    inv_arr = get_inverse_arrow(entry.ptr)
    if !isnothing(inv_arr)
        inv_entry = get_arrow_by_ptr(inv_arr)
        inv_sttype = index_to_sttype(inv_entry.stindex)
        _db_insert_link!(store, to.nptr, from.nptr, inv_arr, weight, ctx_ptr, inv_sttype)
    end

    # Update in-memory incidence lists on cached nodes
    fwd_link = Link(entry.ptr, weight, ctx_ptr, to.nptr)
    _add_link_to_cached_node!(store, from.nptr, fwd_link, entry.stindex)
    if !isnothing(inv_arr)
        inv_entry = get_arrow_by_ptr(inv_arr)
        bwd_link = Link(inv_arr, weight, ctx_ptr, from.nptr)
        _add_link_to_cached_node!(store, to.nptr, bwd_link, inv_entry.stindex)
    end

    return (entry.ptr, sttype)
end

function _db_insert_link!(store::DBStore, src::NodePtr, dst::NodePtr,
                           arrow::ArrowPtr, weight::Float32, ctx::ContextPtr, sttype::Int)
    # Check for duplicate
    rows = _collect_rows(DBInterface.execute(store.conn,
        """SELECT 1 FROM sst_links WHERE src_class=? AND src_cptr=? AND dst_class=? AND dst_cptr=? AND arrow=? AND context=? LIMIT 1""",
        [src.class, src.cptr, dst.class, dst.cptr, Int(arrow), Int(ctx)]))
    !isempty(rows) && return

    DBInterface.execute(store.conn,
        "INSERT INTO sst_links (src_class, src_cptr, dst_class, dst_cptr, arrow, weight, context, sttype) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        [src.class, src.cptr, dst.class, dst.cptr, Int(arrow), Float64(weight), Int(ctx), sttype])
end

function _add_link_to_cached_node!(store::DBStore, nptr::NodePtr, link::Link, stindex::Int)
    haskey(store._node_cache, nptr) || return
    node = store._node_cache[nptr]
    (stindex < 1 || stindex > ST_TOP) && return
    merge_link_list!(node.incidence[stindex], link)
end

# ──────────────────────────────────────────────────────────────────
# Query operations
# ──────────────────────────────────────────────────────────────────

"""Get a node by NodePtr."""
function db_get_node(store::DBStore, nptr::NodePtr)::Node
    # Check cache
    haskey(store._node_cache, nptr) && return store._node_cache[nptr]

    rows = _collect_rows(DBInterface.execute(store.conn,
        "SELECT text, len, chapter, seq FROM sst_nodes WHERE class=? AND cptr=?",
        [nptr.class, nptr.cptr]))
    isempty(rows) && return Node()

    row = first(rows)
    node = Node(String(row[1]), String(row[3]))
    node.l = Int(row[2])
    node.nptr = nptr
    node.seq = row[4] != 0

    # Load links
    _load_node_links!(store, node)
    _cache_node!(store, node)
    return node
end

function _load_node_links!(store::DBStore, node::Node)
    rows = _collect_rows(DBInterface.execute(store.conn,
        "SELECT dst_class, dst_cptr, arrow, weight, context, sttype FROM sst_links WHERE src_class=? AND src_cptr=?",
        [node.nptr.class, node.nptr.cptr]))

    for row in rows
        dst = NodePtr(Int(row[1]), Int(row[2]))
        link = Link(ArrowPtr(Int(row[3])), Float32(row[4]), ContextPtr(Int(row[5])), dst)
        stindex = sttype_to_index(Int(row[6]))
        (stindex < 1 || stindex > ST_TOP) && continue
        merge_link_list!(node.incidence[stindex], link)
    end
end

"""Get all links from a node."""
function db_get_links(store::DBStore, nptr::NodePtr)::Vector{Link}
    node = db_get_node(store, nptr)
    links = Link[]
    for i in 1:ST_TOP
        append!(links, node.incidence[i])
    end
    return links
end

"""Find nodes by name."""
function db_get_nodes_by_name(store::DBStore, name::AbstractString)::Vector{Node}
    # Check cache
    if haskey(store._name_cache, name)
        return [store._node_cache[nptr] for nptr in store._name_cache[name] if haskey(store._node_cache, nptr)]
    end

    rows = _collect_rows(DBInterface.execute(store.conn,
        "SELECT class, cptr, len, chapter, seq FROM sst_nodes WHERE text = ?",
        [name]))
    nodes = Node[]
    for row in rows
        nptr = NodePtr(Int(row[1]), Int(row[2]))
        node = Node(String(name), String(row[4]))
        node.l = Int(row[3])
        node.nptr = nptr
        node.seq = row[5] != 0
        _load_node_links!(store, node)
        _cache_node!(store, node)
        push!(nodes, node)
    end
    return nodes
end

"""Search nodes by text pattern (LIKE-based for portability)."""
function db_search_nodes(store::DBStore, pattern::AbstractString;
                          chapter::String="", limit::Int=100)::Vector{NodePtr}
    if !isempty(chapter) && chapter != "any" && chapter != "%%"
        rows = _collect_rows(DBInterface.execute(store.conn,
            "SELECT class, cptr FROM sst_nodes WHERE text LIKE ? AND chapter LIKE ? LIMIT ?",
            ["%$(pattern)%", "%$(chapter)%", limit]))
    else
        rows = _collect_rows(DBInterface.execute(store.conn,
            "SELECT class, cptr FROM sst_nodes WHERE text LIKE ? LIMIT ?",
            ["%$(pattern)%", limit]))
    end
    return [NodePtr(Int(row[1]), Int(row[2])) for row in rows]
end

"""Get all distinct chapters."""
function db_get_chapters(store::DBStore)::Vector{String}
    rows = _collect_rows(DBInterface.execute(store.conn,
        "SELECT DISTINCT chapter FROM sst_nodes ORDER BY chapter"))
    return [String(row[1]) for row in rows]
end

"""Get nodes in a chapter."""
function db_get_chapter_nodes(store::DBStore, chapter::AbstractString; limit::Int=100)::Vector{NodePtr}
    rows = _collect_rows(DBInterface.execute(store.conn,
        "SELECT class, cptr FROM sst_nodes WHERE chapter LIKE ? LIMIT ?",
        ["%$(chapter)%", limit]))
    return [NodePtr(Int(row[1]), Int(row[2])) for row in rows]
end

"""Count nodes and links."""
function db_stats(store::DBStore)::Dict{String,Int}
    n = _scalar(store, "SELECT COUNT(*) FROM sst_nodes")
    l = _scalar(store, "SELECT COUNT(*) FROM sst_links")
    return Dict("nodes" => Int(isnothing(n) ? 0 : n), "links" => Int(isnothing(l) ? 0 : l))
end

# ──────────────────────────────────────────────────────────────────
# Arrow & context sync to DB
# ──────────────────────────────────────────────────────────────────

"""Upload all in-memory arrows to the database."""
function db_upload_arrows!(store::DBStore)
    for entry in _ARROW_DIRECTORY
        entry.ptr == 0 && continue
        DBInterface.execute(store.conn,
            "INSERT OR REPLACE INTO sst_arrows (ptr, stindex, short, long) VALUES (?, ?, ?, ?)",
            [Int(entry.ptr), entry.stindex, entry.short, entry.long])
    end
    for (fwd, bwd) in _INVERSE_ARROWS
        DBInterface.execute(store.conn,
            "INSERT OR REPLACE INTO sst_arrow_inverses (fwd, bwd) VALUES (?, ?)",
            [Int(fwd), Int(bwd)])
    end
end

"""Load arrows from DB into module-level directory."""
function db_load_arrows!(store::DBStore)
    rows = _collect_rows(DBInterface.execute(store.conn,
        "SELECT ptr, stindex, short, long FROM sst_arrows ORDER BY ptr"))
    for row in rows
        ptr = ArrowPtr(Int(row[1]))
        entry = ArrowEntry(Int(row[2]), String(row[4]), String(row[3]), Int(row[1]))
        while length(_ARROW_DIRECTORY) < ptr
            push!(_ARROW_DIRECTORY, ArrowEntry(0, "", "", 0))
        end
        _ARROW_DIRECTORY[ptr] = entry
        _ARROW_SHORT_DIR[String(row[3])] = ptr
        _ARROW_LONG_DIR[String(row[4])] = ptr
        if ptr > _ARROW_DIRECTORY_TOP[]
            _ARROW_DIRECTORY_TOP[] = ptr
        end
    end
    # Load inverses
    inv_rows = _collect_rows(DBInterface.execute(store.conn,
        "SELECT fwd, bwd FROM sst_arrow_inverses"))
    for row in inv_rows
        _INVERSE_ARROWS[ArrowPtr(Int(row[1]))] = ArrowPtr(Int(row[2]))
        _INVERSE_ARROWS[ArrowPtr(Int(row[2]))] = ArrowPtr(Int(row[1]))
    end
end

"""Upload all contexts to DB."""
function db_upload_contexts!(store::DBStore)
    for entry in _CONTEXT_DIRECTORY
        isempty(entry.context) && continue
        DBInterface.execute(store.conn,
            "INSERT OR REPLACE INTO sst_contexts (ptr, context) VALUES (?, ?)",
            [Int(entry.ptr), entry.context])
    end
end

"""Load contexts from DB."""
function db_load_contexts!(store::DBStore)
    rows = _collect_rows(DBInterface.execute(store.conn,
        "SELECT ptr, context FROM sst_contexts ORDER BY ptr"))
    for row in rows
        ptr = ContextPtr(Int(row[1]))
        ctx = String(row[2])
        while length(_CONTEXT_DIRECTORY) < Int(ptr)
            push!(_CONTEXT_DIRECTORY, ContextEntry("", 0))
        end
        _CONTEXT_DIRECTORY[Int(ptr)] = ContextEntry(ctx, Int(ptr))
        _CONTEXT_DIR[ctx] = ptr
        if Int(ptr) > _CONTEXT_TOP[]
            _CONTEXT_TOP[] = Int(ptr)
        end
    end
end

# ──────────────────────────────────────────────────────────────────
# Implement mem_* interface for DBStore (so existing code works)
# ──────────────────────────────────────────────────────────────────

mem_vertex!(store::DBStore, name::AbstractString, chap::AbstractString) = db_vertex!(store, name, chap)
mem_get_node(store::DBStore, nptr::NodePtr) = db_get_node(store, nptr)
mem_get_links(store::DBStore, nptr::NodePtr) = db_get_links(store, nptr)
mem_get_nodes_by_name(store::DBStore, name::AbstractString) = db_get_nodes_by_name(store, name)

function mem_edge!(store::DBStore, from::Node, arrow::AbstractString,
                   to::Node, context::Vector{String}=String[],
                   weight::Float32=1.0f0)
    db_edge!(store, from, arrow, to; context=context, weight=weight)
end

# ──────────────────────────────────────────────────────────────────
# Cone search support for DBStore
# ──────────────────────────────────────────────────────────────────

function forward_cone(store::DBStore, start::NodePtr;
                      depth::Int=5, limit::Int=CAUSAL_CONE_MAXLIMIT)
    paths = Vector{Link}[]
    _expand_db_cone!(store, start, depth, limit, true, paths, Link[], Set{NodePtr}())
    supernodes = _compute_supernodes(paths)
    return ConeResult(start, paths, supernodes)
end

function backward_cone(store::DBStore, start::NodePtr;
                       depth::Int=5, limit::Int=CAUSAL_CONE_MAXLIMIT)
    paths = Vector{Link}[]
    _expand_db_cone!(store, start, depth, limit, false, paths, Link[], Set{NodePtr}())
    supernodes = _compute_supernodes(paths)
    return ConeResult(start, paths, supernodes)
end

function _expand_db_cone!(store::DBStore, current::NodePtr,
                          remaining::Int, limit::Int, forward::Bool,
                          paths::Vector{Vector{Link}},
                          prefix::Vector{Link},
                          visited::Set{NodePtr})
    length(paths) >= limit && return nothing
    remaining <= 0 && return nothing

    node = db_get_node(store, current)
    isempty(node.s) && return nothing

    push!(visited, current)

    found_any = false
    for stidx in 1:ST_TOP
        st = index_to_sttype(stidx)
        if forward
            st <= 0 && continue
        else
            st >= 0 && continue
        end

        for lnk in node.incidence[stidx]
            lnk.dst in visited && continue
            length(paths) >= limit && return nothing

            new_prefix = vcat(prefix, [lnk])
            push!(paths, copy(new_prefix))
            found_any = true

            _expand_db_cone!(store, lnk.dst, remaining - 1, limit, forward,
                             paths, new_prefix, copy(visited))
        end
    end

    nothing
end

# ──────────────────────────────────────────────────────────────────
# Convenience constructors for specific backends
# ──────────────────────────────────────────────────────────────────

"""
    open_sqlite(path::AbstractString=":memory:") -> DBStore

Open a SQLite-backed SST store. Requires `using SQLite`.
"""
function open_sqlite end  # Defined in SQLiteExt

"""
    open_duckdb(path::AbstractString=":memory:") -> DBStore

Open a DuckDB-backed SST store. Requires `using DuckDB`.
"""
function open_duckdb end  # Defined in DuckDBExt

"""
    close_db(store::DBStore)

Close the database connection.
"""
function close_db(store::DBStore)
    try
        DBInterface.close!(store.conn)
    catch
        # Some backends don't support close! on certain connection types
    end
    store._node_cache = Dict{NodePtr,Node}()
    store._name_cache = Dict{String,Vector{NodePtr}}()
    nothing
end
