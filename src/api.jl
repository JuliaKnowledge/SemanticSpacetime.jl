#=
High-level Vertex/Edge API for Semantic Spacetime.

Provides the simple `vertex!` / `edge!` interface for graph construction,
matching the Go SST.Vertex() / SST.Edge() API. Users are not allowed to
define new arrow types through this interface.

Ported from SSTorytime/pkg/SSTorytime/SSTorytime.go.
=#

# ──────────────────────────────────────────────────────────────────
# Vertex (node creation)
# ──────────────────────────────────────────────────────────────────

"""
    vertex!(sst::SSTConnection, name::AbstractString, chap::AbstractString) -> Node

Create or retrieve a node in the SST graph. Idempotent — if a node
with the same text already exists, returns the existing node.

# Arguments
- `sst`: Open database connection
- `name`: Text content of the node
- `chap`: Chapter/section this node belongs to

# Example
```julia
sst = open_sst()
n1 = vertex!(sst, "Mary had a little lamb", "nursery rhymes")
n2 = vertex!(sst, "Whose fleece was white as snow", "nursery rhymes")
close_sst(sst)
```
"""
function vertex!(sst::SSTConnection, name::AbstractString, chap::AbstractString)
    node = Node(String(name), String(chap))

    # First register in memory
    nptr = append_text_to_directory!(node)
    node.nptr = nptr

    # Then upsert to database
    idemp_db_add_node!(sst, node)

    return node
end

# ──────────────────────────────────────────────────────────────────
# Edge (link creation)
# ──────────────────────────────────────────────────────────────────

"""
    edge!(sst::SSTConnection, from::Node, arrow::AbstractString, to::Node,
          context::Vector{String}=String[], weight::Float32=1.0f0) -> (ArrowPtr, Int)

Create a directed link between two nodes using a named arrow type.
The arrow must already be registered in the arrow directory.

Returns `(arrow_ptr, sttype)` for the created link.

# Arguments
- `sst`: Open database connection
- `from`: Source node (returned by `vertex!`)
- `arrow`: Short or long name of a registered arrow
- `to`: Destination node (returned by `vertex!`)
- `context`: Optional context labels for the link
- `weight`: Optional link weight (default 1.0)

# Example
```julia
sst = open_sst(load_arrows=true)
n1 = vertex!(sst, "Event A", "chapter1")
n2 = vertex!(sst, "Event B", "chapter1")
edge!(sst, n1, "then", n2, String[], 1.0f0)
close_sst(sst)
```
"""
function edge!(sst::SSTConnection, from::Node, arrow::AbstractString,
               to::Node, context::Vector{String}=String[],
               weight::Float32=1.0f0)

    entry = get_arrow_by_name(arrow)
    isnothing(entry) && error("No such arrow '$(arrow)' in the directory. " *
                              "Vertex/Edge API users cannot define new arrows.")

    sttype = index_to_sttype(entry.stindex)
    ctx_ptr = try_context(context)

    # Create forward link
    lnk = Link(entry.ptr, weight, ctx_ptr, to.nptr)
    append_db_link_to_node!(sst, from.nptr, lnk, sttype)

    # Also add to in-memory
    append_link_to_node!(from.nptr, lnk, to.nptr)

    # Create inverse link
    inv_arr = get_inverse_arrow(entry.ptr)
    if !isnothing(inv_arr)
        inv_link = Link(inv_arr, weight, ctx_ptr, from.nptr)
        append_db_link_to_node!(sst, to.nptr, inv_link, -sttype)
        append_link_to_node!(to.nptr, inv_link, from.nptr)
    end

    return (entry.ptr, sttype)
end

# ──────────────────────────────────────────────────────────────────
# Hub join (multi-link through a central node)
# ──────────────────────────────────────────────────────────────────

"""
    hub_join!(sst::SSTConnection, name::AbstractString, chap::AbstractString,
              from_ptrs::Vector{NodePtr}, arrow::AbstractString,
              context::Vector{String}, weights::Vector{Float32}) -> Node

Create a hub node and link multiple source nodes to it with the
same arrow type. Used for many-to-one relationships.

Returns the hub node.
"""
function hub_join!(sst::SSTConnection, name::AbstractString, chap::AbstractString,
                   from_ptrs::Vector{NodePtr}, arrow::AbstractString,
                   context::Vector{String}, weights::Vector{Float32})

    hub = vertex!(sst, name, chap)

    for (i, fptr) in enumerate(from_ptrs)
        from_node = get_memory_node_from_ptr(fptr)
        w = i <= length(weights) ? weights[i] : 1.0f0
        edge!(sst, from_node, arrow, hub, context, w)
    end

    return hub
end

# ──────────────────────────────────────────────────────────────────
# Bulk upload
# ──────────────────────────────────────────────────────────────────

"""
    graph_to_db!(sst::SSTConnection; show_progress::Bool=false)

Upload the entire in-memory graph (from the global node directory)
to the database. This is typically called after building a graph
with the N4L compiler.
"""
function graph_to_db!(sst::SSTConnection; show_progress::Bool=false)
    nd = _NODE_DIRECTORY[]
    total = 0

    # Upload all arrows
    for arrow in _ARROW_DIRECTORY
        upload_arrow_to_db!(sst, arrow)
    end

    # Upload inverse arrow relationships
    for (fwd, bwd) in _INVERSE_ARROWS
        upload_inverse_arrow_to_db!(sst, fwd, bwd)
    end

    # Upload all contexts
    upload_contexts_to_db!(sst)

    # Upload nodes from each size class
    for class in [N1GRAM, N2GRAM, N3GRAM, LT128, LT1024, GT1024]
        dir, _ = _get_directory(nd, class)
        for node in dir
            upload_node_to_db!(sst, node)
            total += 1
            if show_progress && total % 100 == 0
                @info "Uploaded $total nodes..."
            end
        end
    end

    # Upload page map
    for pm in _page_map_entries()
        upload_pagemap_event!(sst, pm)
    end

    show_progress && @info "Upload complete: $total nodes"
    nothing
end

# Page map state
const _PAGE_MAP = PageMap[]

_page_map_entries() = _PAGE_MAP

"""
    upload_pagemap_event!(sst::SSTConnection, pm::PageMap)

Upload a single page map entry to the database.
"""
function upload_pagemap_event!(sst::SSTConnection, pm::PageMap)
    ec = sql_escape(pm.chapter)
    ea = sql_escape(pm.alias)

    path_str = if isempty(pm.path)
        "NULL"
    else
        items = [format_link(l) for l in pm.path]
        "'{" * join(items, ",") * "}'"
    end

    execute_sql(sst,
        """INSERT INTO PageMap (Chap, Alias, Ctx, Line, Path)
           VALUES ('$(ec)', '$(ea)', $(pm.ctx), $(pm.line), $(path_str))""")
    nothing
end
