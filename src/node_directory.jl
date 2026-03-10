#=
In-memory node directory with n-gram bucketing.

Nodes are stored in size-classified lanes (1-gram, 2-gram, 3-gram,
<128 chars, <1024 chars, >1024 chars) for efficient lookup.
Short strings (1-3 grams) use Dict for O(1) lookup; longer strings
use linear search (exponentially fewer).

Ported from SSTorytime/pkg/SSTorytime/SSTorytime.go.
=#

# ──────────────────────────────────────────────────────────────────
# NodeDirectory
# ──────────────────────────────────────────────────────────────────

"""
    NodeDirectory

In-memory directory of all nodes, bucketed by text size class.
Short n-grams use hash maps for fast lookup; longer strings use
vectors with linear search (power-law frequency distribution means
these are rare).
"""
mutable struct NodeDirectory
    # Hash maps for 1-3 gram lookups
    n1grams::Dict{String, ClassedNodePtr}
    n1directory::Vector{Node}
    n1_top::ClassedNodePtr

    n2grams::Dict{String, ClassedNodePtr}
    n2directory::Vector{Node}
    n2_top::ClassedNodePtr

    n3grams::Dict{String, ClassedNodePtr}
    n3directory::Vector{Node}
    n3_top::ClassedNodePtr

    # Linear search for longer strings
    lt128::Vector{Node}
    lt128_top::ClassedNodePtr
    lt1024::Vector{Node}
    lt1024_top::ClassedNodePtr
    gt1024::Vector{Node}
    gt1024_top::ClassedNodePtr
end

"""
    new_node_directory() -> NodeDirectory

Create an empty node directory.
"""
function new_node_directory()
    NodeDirectory(
        Dict{String, ClassedNodePtr}(), Node[], 0,
        Dict{String, ClassedNodePtr}(), Node[], 0,
        Dict{String, ClassedNodePtr}(), Node[], 0,
        Node[], 0,
        Node[], 0,
        Node[], 0,
    )
end

# Module-level directory instance (matching Go's NODE_DIRECTORY global)
const _NODE_DIRECTORY = Ref{NodeDirectory}(new_node_directory())

"""
    reset_node_directory!()

Reset the global node directory. Primarily for testing.
"""
function reset_node_directory!()
    _NODE_DIRECTORY[] = new_node_directory()
    nothing
end

# ──────────────────────────────────────────────────────────────────
# Lookup helpers
# ──────────────────────────────────────────────────────────────────

function _get_directory(nd::NodeDirectory, class::Int)
    class == N1GRAM && return (nd.n1directory, nd.n1grams)
    class == N2GRAM && return (nd.n2directory, nd.n2grams)
    class == N3GRAM && return (nd.n3directory, nd.n3grams)
    class == LT128  && return (nd.lt128, nothing)
    class == LT1024 && return (nd.lt1024, nothing)
    class == GT1024 && return (nd.gt1024, nothing)
    error("Invalid text size class: $class")
end

function _get_top(nd::NodeDirectory, class::Int)
    class == N1GRAM && return nd.n1_top
    class == N2GRAM && return nd.n2_top
    class == N3GRAM && return nd.n3_top
    class == LT128  && return nd.lt128_top
    class == LT1024 && return nd.lt1024_top
    class == GT1024 && return nd.gt1024_top
    error("Invalid text size class: $class")
end

function _set_top!(nd::NodeDirectory, class::Int, val::ClassedNodePtr)
    if class == N1GRAM
        nd.n1_top = val
    elseif class == N2GRAM
        nd.n2_top = val
    elseif class == N3GRAM
        nd.n3_top = val
    elseif class == LT128
        nd.lt128_top = val
    elseif class == LT1024
        nd.lt1024_top = val
    elseif class == GT1024
        nd.gt1024_top = val
    else
        error("Invalid text size class: $class")
    end
end

# ──────────────────────────────────────────────────────────────────
# Linear search for longer strings
# ──────────────────────────────────────────────────────────────────

"""
    linear_find_text(nodes::Vector{Node}, event::Node; ignore_caps::Bool=false) -> (ClassedNodePtr, Bool)

Search a node vector linearly for matching text. Returns (index, found).
"""
function linear_find_text(nodes::Vector{Node}, event::Node; ignore_caps::Bool=false)
    target = ignore_caps ? lowercase(event.s) : event.s
    for (i, n) in enumerate(nodes)
        candidate = ignore_caps ? lowercase(n.s) : n.s
        if candidate == target
            return (ClassedNodePtr(i), true)
        end
    end
    return (ClassedNodePtr(0), false)
end

# ──────────────────────────────────────────────────────────────────
# Check for existing or alternative capitalizations
# ──────────────────────────────────────────────────────────────────

"""
    check_existing_or_alt_caps(nd::NodeDirectory, event::Node) -> (ClassedNodePtr, Bool)

Check if a node with the same text (or different capitalization) already exists.
Returns (pointer, found). Logs a warning if an alternative capitalization exists.
"""
function check_existing_or_alt_caps(nd::NodeDirectory, event::Node)
    class = n_channel(event.s)

    if class <= N3GRAM
        dir, grams = _get_directory(nd, class)
        # Exact match
        if haskey(grams, event.s)
            return (grams[event.s], true)
        end
        # Alt caps check
        lc = lowercase(event.s)
        for (k, v) in grams
            if lowercase(k) == lc && k != event.s
                @warn "Another capitalization exists: '$(k)' vs '$(event.s)'"
                return (v, true)
            end
        end
        return (ClassedNodePtr(0), false)
    else
        dir, _ = _get_directory(nd, class)
        # Exact match
        cptr, found = linear_find_text(dir, event)
        if found
            return (cptr, true)
        end
        # Alt caps
        cptr2, found2 = linear_find_text(dir, event; ignore_caps=true)
        if found2
            @warn "Another capitalization exists for: '$(event.s)'"
            return (cptr2, true)
        end
        return (ClassedNodePtr(0), false)
    end
end

"""
    check_existing_or_alt_caps(event::Node) -> (ClassedNodePtr, Bool)

Check using the global node directory.
"""
check_existing_or_alt_caps(event::Node) = check_existing_or_alt_caps(_NODE_DIRECTORY[], event)

# ──────────────────────────────────────────────────────────────────
# Append node to directory
# ──────────────────────────────────────────────────────────────────

"""
    append_text_to_directory!(nd::NodeDirectory, event::Node) -> NodePtr

Add a node to the directory. Returns the NodePtr for the (possibly existing) node.
Idempotent — returns existing pointer if text already registered.
"""
function append_text_to_directory!(nd::NodeDirectory, event::Node)
    class = n_channel(event.s)

    cptr, found = check_existing_or_alt_caps(nd, event)
    if found
        return NodePtr(class, cptr)
    end

    # Append new node
    _set_top!(nd, class, _get_top(nd, class) + 1)
    new_cptr = _get_top(nd, class)

    event.nptr = NodePtr(class, new_cptr)
    dir, grams = _get_directory(nd, class)
    push!(dir, event)

    if !isnothing(grams)
        grams[event.s] = new_cptr
    end

    return event.nptr
end

"""
    append_text_to_directory!(event::Node) -> NodePtr

Append to the global node directory.
"""
append_text_to_directory!(event::Node) = append_text_to_directory!(_NODE_DIRECTORY[], event)

# ──────────────────────────────────────────────────────────────────
# Node retrieval
# ──────────────────────────────────────────────────────────────────

"""
    get_node_txt_from_ptr(nd::NodeDirectory, ptr::NodePtr) -> String

Get the text of a node by its pointer. Returns "" if not found.
"""
function get_node_txt_from_ptr(nd::NodeDirectory, ptr::NodePtr)
    node = get_memory_node_from_ptr(nd, ptr)
    return node.s
end

get_node_txt_from_ptr(ptr::NodePtr) = get_node_txt_from_ptr(_NODE_DIRECTORY[], ptr)

"""
    get_memory_node_from_ptr(nd::NodeDirectory, ptr::NodePtr) -> Node

Retrieve a node from memory by its pointer. Returns empty node if not found.
"""
function get_memory_node_from_ptr(nd::NodeDirectory, ptr::NodePtr)
    dir, _ = _get_directory(nd, ptr.class)
    if 1 <= ptr.cptr <= length(dir)
        return dir[ptr.cptr]
    end
    return Node()
end

get_memory_node_from_ptr(ptr::NodePtr) = get_memory_node_from_ptr(_NODE_DIRECTORY[], ptr)

"""
    idemp_add_chapter_seq_to_node!(nd::NodeDirectory, class::Int, cptr::ClassedNodePtr, chap::String, seq::Bool)

Idempotently set the chapter and sequence status on an existing node.
"""
function idemp_add_chapter_seq_to_node!(nd::NodeDirectory, class::Int,
                                        cptr::ClassedNodePtr, chap::String, seq::Bool)
    dir, _ = _get_directory(nd, class)
    if 1 <= cptr <= length(dir)
        node = dir[cptr]
        if isempty(node.chap)
            node.chap = chap
        end
        if seq
            node.seq = true
        end
    end
    nothing
end

"""
    update_seq_status!(nd::NodeDirectory, class::Int, cptr::ClassedNodePtr, seq::Bool) -> Union{Node, Nothing}

Update the sequence status of a node (OR with existing value).
Returns the node if found, or nothing if out of range.
"""
function update_seq_status!(nd::NodeDirectory, class::Int, cptr::ClassedNodePtr, seq::Bool)::Union{Node, Nothing}
    dir, _ = _get_directory(nd, class)
    if cptr < 1 || cptr > length(dir)
        return nothing
    end
    node = dir[cptr]
    if seq && !node.seq
        node.seq = true
    end
    return node
end

"""
    update_seq_status!(class::Int, cptr::ClassedNodePtr, seq::Bool) -> Union{Node, Nothing}

Update sequence status using the global node directory.
"""
update_seq_status!(class::Int, cptr::ClassedNodePtr, seq::Bool) = update_seq_status!(_NODE_DIRECTORY[], class, cptr, seq)

"""
    _get_bucket(nd::NodeDirectory, class::Int) -> Vector{Node}

Get the node vector (bucket) for a given text size class.
Convenience accessor that returns only the vector (unlike `_get_directory`
which also returns the hash map).
"""
function _get_bucket(nd::NodeDirectory, class::Int)::Vector{Node}
    dir, _ = _get_directory(nd, class)
    return dir
end
