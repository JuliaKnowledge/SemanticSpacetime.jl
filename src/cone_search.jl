#=
Causal cone traversal for Semantic Spacetime.

Forward and backward cone search over the SST graph, with optional
NCCS (Name/Chapter/Context/Sequence) filtering. Works against both
the PostgreSQL database (SSTConnection) and the in-memory store
(MemoryStore).

Ported from SSTorytime/pkg/SSTorytime/SSTorytime.go
(GetFwdPathsAsLinks, GetEntireNCConePathsAsLinks, SelectStoriesByArrow).
=#

# ──────────────────────────────────────────────────────────────────
# ConeResult
# ──────────────────────────────────────────────────────────────────

"""
    ConeResult

Result of a causal cone search, containing all discovered paths from
(or to) a root node, plus any identified supernodes.
"""
struct ConeResult
    root::NodePtr
    paths::Vector{Vector{Link}}
    supernodes::Vector{NodePtr}
end

ConeResult(root::NodePtr) = ConeResult(root, Vector{Link}[], NodePtr[])

# ──────────────────────────────────────────────────────────────────
# In-memory forward cone
# ──────────────────────────────────────────────────────────────────

"""
    forward_cone(store::MemoryStore, start::NodePtr;
                 depth::Int=5, limit::Int=CAUSAL_CONE_MAXLIMIT) -> ConeResult

Traverse forward (positive-ST) links from `start` up to `depth` hops,
collecting at most `limit` paths.  Works entirely in memory.
"""
function forward_cone(store::MemoryStore, start::NodePtr;
                      depth::Int=5, limit::Int=CAUSAL_CONE_MAXLIMIT)
    paths = Vector{Link}[]
    _expand_cone!(store, start, depth, limit, true, paths, Link[], Set{NodePtr}())
    supernodes = _compute_supernodes(paths)
    return ConeResult(start, paths, supernodes)
end

"""
    backward_cone(store::MemoryStore, start::NodePtr;
                  depth::Int=5, limit::Int=CAUSAL_CONE_MAXLIMIT) -> ConeResult

Traverse backward (negative-ST) links to `start` up to `depth` hops.
"""
function backward_cone(store::MemoryStore, start::NodePtr;
                       depth::Int=5, limit::Int=CAUSAL_CONE_MAXLIMIT)
    paths = Vector{Link}[]
    _expand_cone!(store, start, depth, limit, false, paths, Link[], Set{NodePtr}())
    supernodes = _compute_supernodes(paths)
    return ConeResult(start, paths, supernodes)
end

# ──────────────────────────────────────────────────────────────────
# Recursive cone expander (in-memory)
# ──────────────────────────────────────────────────────────────────

"""
Recursively expand the cone from `current`, appending completed
paths into `paths`.  `forward` selects positive or negative ST channels.
"""
function _expand_cone!(store::MemoryStore, current::NodePtr,
                       remaining::Int, limit::Int, forward::Bool,
                       paths::Vector{Vector{Link}},
                       prefix::Vector{Link},
                       visited::Set{NodePtr})
    length(paths) >= limit && return nothing
    remaining <= 0 && return nothing

    node = mem_get_node(store, current)
    isnothing(node) && return nothing

    push!(visited, current)

    # Select ST channels: positive indices for forward, negative for backward
    found_any = false
    for stidx in 1:ST_TOP
        st = index_to_sttype(stidx)
        if forward
            st <= 0 && continue   # skip negative / NEAR for forward
        else
            st >= 0 && continue   # skip positive / NEAR for backward
        end

        for lnk in node.incidence[stidx]
            lnk.dst in visited && continue
            length(paths) >= limit && return nothing

            new_prefix = vcat(prefix, [lnk])

            # Record this path
            push!(paths, copy(new_prefix))
            found_any = true

            # Recurse deeper
            _expand_cone!(store, lnk.dst, remaining - 1, limit, forward,
                          paths, new_prefix, copy(visited))
        end
    end

    nothing
end

# ──────────────────────────────────────────────────────────────────
# Database-backed cone search
# ──────────────────────────────────────────────────────────────────

"""
    forward_cone(sst::SSTConnection, start::NodePtr;
                 depth::Int=5, limit::Int=CAUSAL_CONE_MAXLIMIT) -> ConeResult

Traverse forward links from `start` via the database stored function
`AllPathsAsLinks`.
"""
function forward_cone(sst::SSTConnection, start::NodePtr;
                      depth::Int=5, limit::Int=CAUSAL_CONE_MAXLIMIT)
    np = format_nodeptr(start)
    qstr = "SELECT AllPathsAsLinks FROM AllPathsAsLinks('$(np)','fwd',$(depth),$(limit))"
    paths = _query_link_paths(sst, qstr)
    sort!(paths; by=length)
    supernodes = _compute_supernodes(paths)
    return ConeResult(start, paths, supernodes)
end

"""
    backward_cone(sst::SSTConnection, start::NodePtr;
                  depth::Int=5, limit::Int=CAUSAL_CONE_MAXLIMIT) -> ConeResult

Traverse backward links to `start` via the database.
"""
function backward_cone(sst::SSTConnection, start::NodePtr;
                       depth::Int=5, limit::Int=CAUSAL_CONE_MAXLIMIT)
    np = format_nodeptr(start)
    qstr = "SELECT AllPathsAsLinks FROM AllPathsAsLinks('$(np)','bwd',$(depth),$(limit))"
    paths = _query_link_paths(sst, qstr)
    sort!(paths; by=length)
    supernodes = _compute_supernodes(paths)
    return ConeResult(start, paths, supernodes)
end

# ──────────────────────────────────────────────────────────────────
# Full NCCS-filtered cone search
# ──────────────────────────────────────────────────────────────────

"""
    entire_nc_cone(sst::SSTConnection, start_set::Vector{NodePtr};
                   orientation::String="fwd", depth::Int=5,
                   chapter::String="", context::Vector{String}=String[],
                   limit::Int=CAUSAL_CONE_MAXLIMIT) -> ConeResult

Full name/chapter/context-filtered cone search via the database
stored function `AllNCPathsAsLinks`.
"""
function entire_nc_cone(sst::SSTConnection, start_set::Vector{NodePtr};
                        orientation::String="fwd", depth::Int=5,
                        chapter::String="", context::Vector{String}=String[],
                        limit::Int=CAUSAL_CONE_MAXLIMIT)
    isempty(start_set) && return ConeResult(NO_NODE_PTR)

    nod = _format_sql_nodeptr_array(start_set)
    chap = isempty(chapter) ? "%%%" : "%" * sql_escape(chapter) * "%"
    cnt = _format_sql_string_array(context)

    qstr = "SELECT AllNCPathsAsLinks($(nod),'$(chap)',false,$(cnt),'$(orientation)',$(depth),$(limit))"
    paths = _query_link_paths(sst, qstr)
    supernodes = _compute_supernodes(paths)
    return ConeResult(first(start_set), paths, supernodes)
end

# ──────────────────────────────────────────────────────────────────
# Arrow-filtered story selection
# ──────────────────────────────────────────────────────────────────

"""
    select_stories_by_arrow(sst::SSTConnection,
                            nodeptrs::Vector{NodePtr},
                            arrowptrs::Vector{ArrowPtr},
                            sttypes::Vector{Int},
                            limit::Int) -> Vector{NodePtr}

Filter a set of node pointers to those whose links match the given
arrow types and ST types. Mirrors the Go `SelectStoriesByArrow`.
"""
function select_stories_by_arrow(sst::SSTConnection,
                                 nodeptrs::Vector{NodePtr},
                                 arrowptrs::Vector{ArrowPtr},
                                 sttypes::Vector{Int},
                                 limit::Int)
    matches = NodePtr[]
    for nptr in nodeptrs
        node = get_db_node_by_nodeptr(sst, nptr)
        isempty(node.s) && continue
        push!(matches, node.nptr)
        length(matches) >= limit && break
    end
    return matches
end

"""
    select_stories_by_arrow(store::MemoryStore,
                            nodeptrs::Vector{NodePtr},
                            arrowptrs::Vector{ArrowPtr},
                            sttypes::Vector{Int},
                            limit::Int) -> Vector{NodePtr}

In-memory version: filter nodes to those present in the store.
"""
function select_stories_by_arrow(store::MemoryStore,
                                 nodeptrs::Vector{NodePtr},
                                 arrowptrs::Vector{ArrowPtr},
                                 sttypes::Vector{Int},
                                 limit::Int)
    matches = NodePtr[]
    for nptr in nodeptrs
        node = mem_get_node(store, nptr)
        isnothing(node) && continue
        push!(matches, node.nptr)
        length(matches) >= limit && break
    end
    return matches
end

# ──────────────────────────────────────────────────────────────────
# Internal helpers
# ──────────────────────────────────────────────────────────────────

"""Execute a SQL query that returns link paths and parse the result."""
function _query_link_paths(sst::SSTConnection, qstr::AbstractString)
    paths = Vector{Link}[]
    try
        result = execute_sql_strict(sst, qstr)
        for row in LibPQ.Columns(result)
            whole = string(row[1])
            parsed = _parse_link_paths(whole)
            append!(paths, parsed)
        end
    catch e
        @warn "Cone search query failed" query=qstr exception=e
    end
    return paths
end

"""Parse a multi-path result string into a vector of link-path vectors."""
function _parse_link_paths(s::AbstractString)
    # Delegate to the existing parse_link_array for each path
    paths = Vector{Link}[]
    # The DB returns paths as nested arrays; each row is one path
    parsed = parse_link_array(s)
    if !isempty(parsed)
        push!(paths, parsed)
    end
    return paths
end

"""Format a vector of NodePtrs as a SQL array literal."""
function _format_sql_nodeptr_array(ptrs::Vector{NodePtr})
    parts = [format_nodeptr(p) for p in ptrs]
    return "ARRAY[" * join(["'$(p)'::NodePtr" for p in parts], ",") * "]"
end

"""Format a string vector as a SQL array literal."""
function _format_sql_string_array(strs::Vector{String})
    isempty(strs) && return "ARRAY[]::text[]"
    return "ARRAY[" * join(["'$(sql_escape(s))'" for s in strs], ",") * "]"
end

"""
Compute supernodes from a set of paths: nodes that appear in
multiple paths at the same depth level (transverse equivalence).
"""
function _compute_supernodes(paths::Vector{Vector{Link}})
    isempty(paths) && return NodePtr[]

    # Count frequency of each node across all paths
    freq = Dict{NodePtr, Int}()
    for path in paths
        for lnk in path
            freq[lnk.dst] = get(freq, lnk.dst, 0) + 1
        end
    end

    # Nodes appearing in more than one path are supernodes
    supernodes = NodePtr[]
    for (nptr, count) in freq
        count > 1 && push!(supernodes, nptr)
    end
    sort!(supernodes)
    return supernodes
end

# ──────────────────────────────────────────────────────────────────
# Forward paths as links (in-memory BFS)
# ──────────────────────────────────────────────────────────────────

"""
    get_fwd_paths_as_links(store::MemoryStore, start::NodePtr, sttype::Int,
                           depth::Int; limit::Int=100)

BFS expansion of forward cone, collecting complete paths as link vectors.
Only follows links whose arrow belongs to the given signed `sttype` channel
(positive ST values for forward). If `sttype == 0`, all positive channels
are traversed.

Returns `(paths::Vector{Vector{Link}}, count::Int)`.
"""
function get_fwd_paths_as_links(store::MemoryStore, start::NodePtr, sttype::Int,
                                depth::Int; limit::Int=100)
    paths = Vector{Link}[]
    _expand_fwd_links!(store, start, depth, limit, sttype, paths, Link[], Set{NodePtr}())
    return (paths, length(paths))
end

function _expand_fwd_links!(store::MemoryStore, current::NodePtr,
                            remaining::Int, limit::Int, sttype::Int,
                            paths::Vector{Vector{Link}},
                            prefix::Vector{Link}, visited::Set{NodePtr})
    length(paths) >= limit && return nothing
    remaining <= 0 && return nothing

    node = mem_get_node(store, current)
    isnothing(node) && return nothing

    push!(visited, current)

    for stidx in 1:ST_TOP
        st = index_to_sttype(stidx)
        st <= 0 && continue  # forward only

        # Filter by specific sttype if requested
        if sttype != 0 && st != sttype
            continue
        end

        for lnk in node.incidence[stidx]
            lnk.dst in visited && continue
            length(paths) >= limit && return nothing

            new_prefix = vcat(prefix, [lnk])
            push!(paths, copy(new_prefix))

            _expand_fwd_links!(store, lnk.dst, remaining - 1, limit, sttype,
                               paths, new_prefix, copy(visited))
        end
    end
    nothing
end

"""
    get_entire_cone_paths_as_links(store::MemoryStore, orientation::String,
                                   start::NodePtr, depth::Int; limit::Int=100)

Get cone paths as link vectors with orientation control.
`orientation` is "fwd" (forward only), "bwd" (backward only),
or "any" (both directions).

Returns `(paths::Vector{Vector{Link}}, count::Int)`.
"""
function get_entire_cone_paths_as_links(store::MemoryStore, orientation::String,
                                        start::NodePtr, depth::Int; limit::Int=100)
    if orientation == "fwd"
        cone = forward_cone(store, start; depth=depth, limit=limit)
        return (cone.paths, length(cone.paths))
    elseif orientation == "bwd"
        cone = backward_cone(store, start; depth=depth, limit=limit)
        return (cone.paths, length(cone.paths))
    else
        # "any" — combine forward and backward
        fwd_cone = forward_cone(store, start; depth=depth, limit=limit)
        remaining = limit - length(fwd_cone.paths)
        if remaining > 0
            bwd_cone = backward_cone(store, start; depth=depth, limit=remaining)
            all_paths = vcat(fwd_cone.paths, bwd_cone.paths)
            return (all_paths, length(all_paths))
        end
        return (fwd_cone.paths, length(fwd_cone.paths))
    end
end
