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

    # LT128 is hash-mapped too (upstream moved it out of linear search:
    # the original power-law use-case stats no longer applied).
    lt128grams::Dict{String, ClassedNodePtr}
    lt128::Vector{Node}
    lt128_top::ClassedNodePtr

    # Linear search for the rare longer strings
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
        Dict{String, ClassedNodePtr}(), Node[], 0,
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
    class == LT128  && return (nd.lt128, nd.lt128grams)
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
# Existence check (exact match only)
# ──────────────────────────────────────────────────────────────────

"""
    check_existing(nd::NodeDirectory, event::Node) -> (ClassedNodePtr, Bool)

Check whether a node with the *exact* same text already exists.
Returns (pointer, found). Faithful port of Go `CheckExisting`: differently
capitalised variants are NOT treated as the same node here — they are kept
distinct and linked later as NEAR (see [`check_alt_caps!`](@ref)).
"""
function check_existing(nd::NodeDirectory, event::Node)
    class = n_channel(event.s)
    dir, grams = _get_directory(nd, class)

    if !isnothing(grams)
        haskey(grams, event.s) && return (grams[event.s], true)
        return (ClassedNodePtr(0), false)
    end

    # Rare long strings: linear, exact match only
    return linear_find_text(dir, event)
end

check_existing(event::Node) = check_existing(_NODE_DIRECTORY[], event)

# Backwards-compatible alias. NOTE: this no longer merges alternative
# capitalizations — it is exact-match only, matching the upstream split of
# CheckExistingOrAltCaps into CheckExisting + CheckAltCaps.
const check_existing_or_alt_caps = check_existing

# ──────────────────────────────────────────────────────────────────
# Alternative-capitalization NEAR linking
# ──────────────────────────────────────────────────────────────────

"""
    different_caps(n1::Node, n2::Node) -> Bool

True when two nodes have the same length but differ only by capitalization
(identical when lower-cased, but not byte-identical). Port of Go `DifferentCaps`.
"""
function different_caps(n1::Node, n2::Node)
    n1.l != n2.l && return false
    s1 = n1.s
    s2 = n2.s
    return (s1 != s2) && (lowercase(s1) == lowercase(s2))
end

"""
    near_equiv!(nd::NodeDirectory, n1::NodePtr, n2::NodePtr, s1, s2)

Link two capitalization variants bidirectionally with the NEAR `"caps"` arrow
under the `"ambiguous"` context. Port of Go `NearEquiv`.
"""
function near_equiv!(nd::NodeDirectory, n1::NodePtr, n2::NodePtr,
                     s1::AbstractString, s2::AbstractString)
    entry = get_arrow_by_name("caps")
    if isnothing(entry)
        @warn "caps NEAR arrow not registered; skipping capitalization link " *
              "(call add_mandatory_arrows! first)"
        return
    end
    ctx = try_context(["ambiguous"])
    lnk = Link(entry.ptr, 1.0f0, ctx, n2)
    append_link_to_node!(nd, n1, lnk, n2)
    lnk2 = Link(entry.ptr, 1.0f0, ctx, n1)
    append_link_to_node!(nd, n2, lnk2, n1)
    @warn "A similar capitalization/punctuation exists ($(s1) vs $(s2)) - linking as NEAR"
end

"""
    check_alt_caps!(nd::NodeDirectory, event::Node)

Scan the size-class lane of `event` for differently-capitalized variants and
link each to `event` as NEAR. Port of Go `CheckAltCaps`; intended to run as a
post-parse pass over the directory.
"""
function check_alt_caps!(nd::NodeDirectory, event::Node)
    class = n_channel(event.s)
    # Upstream only links variants for the hash-mapped classes (n-grams + LT128).
    dir, grams = _get_directory(nd, class)
    isnothing(grams) && return
    for (key, cptr) in grams
        n = (1 <= cptr <= length(dir)) ? dir[cptr] : Node()
        if different_caps(n, event)
            near_equiv!(nd, NodePtr(class, cptr), event.nptr, key, event.s)
        end
    end
    nothing
end

check_alt_caps!(event::Node) = check_alt_caps!(_NODE_DIRECTORY[], event)

"""
    complete_caps_inferences!(nd::NodeDirectory)

Post-parse pass linking all differently-capitalized node variants as NEAR.
Mirrors the `CheckAltCaps` loop inside Go's `CompleteInferences`.
"""
function complete_caps_inferences!(nd::NodeDirectory)
    for class in (N1GRAM, N2GRAM, N3GRAM, LT128)
        dir, _ = _get_directory(nd, class)
        for node in dir
            check_alt_caps!(nd, node)
        end
    end
    nothing
end

complete_caps_inferences!() = complete_caps_inferences!(_NODE_DIRECTORY[])

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

    cptr, found = check_existing(nd, event)
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
