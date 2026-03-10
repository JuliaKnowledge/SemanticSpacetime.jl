#=
In-memory graph store for Semantic Spacetime.

Provides the same conceptual API as the PostgreSQL-backed store
(vertex!, edge!, queries) without requiring a database connection.
Useful for testing and lightweight/embedded use cases.
=#

# ──────────────────────────────────────────────────────────────────
# Abstract store type
# ──────────────────────────────────────────────────────────────────

"""
    AbstractSSTStore

Abstract supertype for all SST storage backends.
"""
abstract type AbstractSSTStore end

# ──────────────────────────────────────────────────────────────────
# MemoryStore
# ──────────────────────────────────────────────────────────────────

"""
    MemoryStore <: AbstractSSTStore

A fully in-memory graph store. Holds nodes, links, page map entries,
and per-size-class counters for NodePtr allocation. Arrow and context
directories use the existing module-level state.

# Example
```julia
store = MemoryStore()
n1 = mem_vertex!(store, "hello", "ch1")
n2 = mem_vertex!(store, "world", "ch1")
mem_edge!(store, n1, "then", n2)
```
"""
mutable struct MemoryStore <: AbstractSSTStore
    nodes::Dict{NodePtr, Node}
    # Per-size-class counters for allocating new NodePtrs
    class_tops::Dict{Int, ClassedNodePtr}
    # Page map entries
    page_map::Vector{PageMap}
    # Name → set of NodePtrs for fast name lookup
    name_index::Dict{String, Vector{NodePtr}}
    # Chapter set
    chapters::Set{String}
    # Total link count
    _link_count::Int
end

"""
    MemoryStore()

Create an empty in-memory graph store.
"""
function MemoryStore()
    class_tops = Dict{Int, ClassedNodePtr}(
        N1GRAM => 0, N2GRAM => 0, N3GRAM => 0,
        LT128 => 0, LT1024 => 0, GT1024 => 0,
    )
    MemoryStore(
        Dict{NodePtr, Node}(),
        class_tops,
        PageMap[],
        Dict{String, Vector{NodePtr}}(),
        Set{String}(),
        0,
    )
end

# ──────────────────────────────────────────────────────────────────
# NodePtr allocation
# ──────────────────────────────────────────────────────────────────

function _alloc_nptr!(store::MemoryStore, class::Int)
    store.class_tops[class] += 1
    return NodePtr(class, store.class_tops[class])
end

# ──────────────────────────────────────────────────────────────────
# Vertex creation
# ──────────────────────────────────────────────────────────────────

"""
    mem_vertex!(store::MemoryStore, name::AbstractString, chap::AbstractString) -> Node

Create or retrieve a node in the in-memory store. Idempotent — if a
node with the same text already exists, returns the existing node.
"""
function mem_vertex!(store::MemoryStore, name::AbstractString, chap::AbstractString)
    sname = String(name)
    schap = String(chap)

    # Check for existing node with same text
    if haskey(store.name_index, sname)
        nptr = first(store.name_index[sname])
        existing = store.nodes[nptr]
        # Update chapter if it was empty
        if isempty(existing.chap) && !isempty(schap)
            existing.chap = schap
        end
        if !isempty(schap)
            push!(store.chapters, schap)
        end
        return existing
    end

    # Allocate new NodePtr
    class = n_channel(sname)
    nptr = _alloc_nptr!(store, class)

    node = Node(sname, schap)
    node.nptr = nptr

    store.nodes[nptr] = node
    store.name_index[sname] = [nptr]

    if !isempty(schap)
        push!(store.chapters, schap)
    end

    return node
end

# ──────────────────────────────────────────────────────────────────
# Edge creation
# ──────────────────────────────────────────────────────────────────

"""
    mem_edge!(store::MemoryStore, from::Node, arrow::AbstractString,
              to::Node, context::Vector{String}=String[],
              weight::Float32=1.0f0) -> (ArrowPtr, Int)

Create a directed link between two nodes using a named arrow type.
The arrow must already be registered in the arrow directory.
Also creates the inverse link if one is registered.

Returns `(arrow_ptr, sttype)`.
"""
function mem_edge!(store::MemoryStore, from::Node, arrow::AbstractString,
                   to::Node, context::Vector{String}=String[],
                   weight::Float32=1.0f0)

    entry = get_arrow_by_name(arrow)
    isnothing(entry) && error("No such arrow '$(arrow)' in the directory. " *
                              "Register arrows before creating edges.")

    sttype = index_to_sttype(entry.stindex)
    ctx_ptr = try_context(context)

    # Forward link
    lnk = Link(entry.ptr, weight, ctx_ptr, to.nptr)
    _append_link!(store, from, lnk, entry.stindex)

    # Inverse link
    inv_arr = get_inverse_arrow(entry.ptr)
    if !isnothing(inv_arr)
        inv_entry = get_arrow_by_ptr(inv_arr)
        inv_link = Link(inv_arr, weight, ctx_ptr, from.nptr)
        _append_link!(store, to, inv_link, inv_entry.stindex)
    end

    return (entry.ptr, sttype)
end

"""
Append a link to a node's incidence list (idempotent).
"""
function _append_link!(store::MemoryStore, node::Node, lnk::Link, stindex::Int)
    list = node.incidence[stindex]
    for existing in list
        existing == lnk && return nothing
    end
    push!(list, lnk)
    store._link_count += 1
    nothing
end

# ──────────────────────────────────────────────────────────────────
# Queries
# ──────────────────────────────────────────────────────────────────

"""
    mem_get_node(store::MemoryStore, nptr::NodePtr) -> Union{Node, Nothing}

Retrieve a node by its pointer. Returns `nothing` if not found.
"""
function mem_get_node(store::MemoryStore, nptr::NodePtr)
    return get(store.nodes, nptr, nothing)
end

"""
    mem_get_nodes_by_name(store::MemoryStore, name::AbstractString) -> Vector{Node}

Retrieve all nodes with exactly the given text.
"""
function mem_get_nodes_by_name(store::MemoryStore, name::AbstractString)
    sname = String(name)
    if !haskey(store.name_index, sname)
        return Node[]
    end
    return [store.nodes[nptr] for nptr in store.name_index[sname]
            if haskey(store.nodes, nptr)]
end

"""
    mem_get_chapters(store::MemoryStore) -> Vector{String}

Return a sorted list of all chapter names in the store.
"""
function mem_get_chapters(store::MemoryStore)
    return sort!(collect(store.chapters))
end

"""
    mem_search_text(store::MemoryStore, query::AbstractString) -> Vector{Node}

Simple case-insensitive substring search across all node texts.
Returns nodes whose text contains `query`.
"""
function mem_search_text(store::MemoryStore, query::AbstractString)
    q = lowercase(String(query))
    results = Node[]
    for node in values(store.nodes)
        if occursin(q, lowercase(node.s))
            push!(results, node)
        end
    end
    return results
end

"""
    node_count(store::MemoryStore) -> Int

Return the total number of nodes in the store.
"""
node_count(store::MemoryStore) = length(store.nodes)

"""
    link_count(store::MemoryStore) -> Int

Return the total number of links that have been added to the store.
"""
link_count(store::MemoryStore) = store._link_count
