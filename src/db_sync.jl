#=
Database download/sync utilities for Semantic Spacetime.

Provides functions to synchronize in-memory state (arrows, contexts,
node pointers) with the PostgreSQL database.

Ported from SSTorytime/pkg/SSTorytime/SSTorytime.go.
=#

# Module-level node cache
const _NODE_CACHE = Dict{NodePtr, Node}()

"""
    reset_node_cache!()

Clear the module-level node cache. Primarily for testing.
"""
function reset_node_cache!()
    empty!(_NODE_CACHE)
    nothing
end

# ──────────────────────────────────────────────────────────────────
# Download arrows from DB
# ──────────────────────────────────────────────────────────────────

"""
    download_arrows_from_db!(sst::SSTConnection)

Load the arrow directory from the database into module-level state,
replacing any existing in-memory arrows.
"""
function download_arrows_from_db!(sst::SSTConnection)
    reset_arrows!()

    sql = "SELECT STAindex,Long,Short,ArrPtr FROM ArrowDirectory ORDER BY ArrPtr"
    result = execute_sql_strict(sst, sql)

    ct = LibPQ.columntable(result)
    for r in 1:(isempty(ct) ? 0 : length(ct[1]))
        stindex = Int(ct[1][r])
        long_name = String(ct[2][r])
        short_name = String(ct[3][r])
        ptr = Int(ct[4][r])

        if ptr != _ARROW_DIRECTORY_TOP[]
            @warn "Arrow directory mismatch" ptr _ARROW_DIRECTORY_TOP[]
        end

        entry = ArrowEntry(stindex, long_name, short_name, ptr)
        push!(_ARROW_DIRECTORY, entry)
        _ARROW_SHORT_DIR[short_name] = _ARROW_DIRECTORY_TOP[]
        _ARROW_LONG_DIR[long_name] = _ARROW_DIRECTORY_TOP[]
        _ARROW_DIRECTORY_TOP[] += 1
    end

    # Load inverse arrows
    sql_inv = "SELECT Plus,Minus FROM ArrowInverses ORDER BY Plus"
    result_inv = execute_sql_strict(sst, sql_inv)

    ct_inv = LibPQ.columntable(result_inv)
    for r in 1:(isempty(ct_inv) ? 0 : length(ct_inv[1]))
        plus = Int(ct_inv[1][r])
        minus = Int(ct_inv[2][r])
        _INVERSE_ARROWS[plus] = minus
    end

    nothing
end

# ──────────────────────────────────────────────────────────────────
# Download contexts from DB
# ──────────────────────────────────────────────────────────────────

"""
    download_contexts_from_db!(sst::SSTConnection)

Load the context directory from the database into module-level state,
replacing any existing in-memory contexts.
"""
function download_contexts_from_db!(sst::SSTConnection)
    reset_contexts!()

    sql = "SELECT Context,CtxPtr FROM ContextDirectory ORDER BY CtxPtr"
    result = execute_sql_strict(sst, sql)

    ct = LibPQ.columntable(result)
    for r in 1:(isempty(ct) ? 0 : length(ct[1]))
        context_str = String(ct[1][r])
        ptr = Int(ct[2][r])

        if ptr != _CONTEXT_TOP[]
            @warn "Context directory mismatch" ptr _CONTEXT_TOP[]
        end

        entry = ContextEntry(context_str, ptr)
        push!(_CONTEXT_DIRECTORY, entry)
        _CONTEXT_DIR[context_str] = _CONTEXT_TOP[]
        _CONTEXT_TOP[] += 1
    end

    nothing
end

# ──────────────────────────────────────────────────────────────────
# Synchronize node pointers
# ──────────────────────────────────────────────────────────────────

"""
    synchronize_nptrs!(sst::SSTConnection, store::MemoryStore)

Sync in-memory node pointer counters with the database by reading
the maximum CPtr for each size class channel.
"""
function synchronize_nptrs!(sst::SSTConnection, store::MemoryStore)
    for channel in N1GRAM:GT1024
        sql = "SELECT max((Nptr).CPtr) FROM Node WHERE (Nptr).Chan=$(channel)"
        result = execute_sql_strict(sst, sql)

        ct = LibPQ.columntable(result)
        if !isempty(ct) && !isempty(ct[1])
            val = ct[1][1]
            if !isnothing(val) && !ismissing(val)
                cptr = Int(val)
                if cptr > 0
                    store.class_tops[channel] = max(store.class_tops[channel], cptr)
                end
            end
        end
    end

    nothing
end

# ──────────────────────────────────────────────────────────────────
# Cache node
# ──────────────────────────────────────────────────────────────────

"""
    cache_node!(n::Node)

Cache a node in the module-level node directory. Idempotent —
does not overwrite an existing entry.
"""
function cache_node!(n::Node)
    if !haskey(_NODE_CACHE, n.nptr)
        _NODE_CACHE[n.nptr] = n
    end
    nothing
end

"""
    get_cached_node(nptr::NodePtr) -> Union{Node, Nothing}

Retrieve a node from the module-level cache.
"""
function get_cached_node(nptr::NodePtr)
    return get(_NODE_CACHE, nptr, nothing)
end
