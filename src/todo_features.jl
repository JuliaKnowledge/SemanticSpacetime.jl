#=
Todo features for Semantic Spacetime:
1. Focal/Hierarchical View (CONTAINS tree traversal)
2. ETC Validation in Compilation
3. Provenance and Attribution (EXPRESS annotations)
=#

using Dates

# ══════════════════════════════════════════════════════════════════
# 1. Focal / Hierarchical View
# ══════════════════════════════════════════════════════════════════

"""
    FocalView

A hierarchical view rooted at a node, traversing CONTAINS arrows.
"""
struct FocalView
    root::NodePtr
    children::Vector{NodePtr}
    parent::Union{NodePtr, Nothing}
    breadcrumb::Vector{NodePtr}  # path from root to current
    depth::Int
end

# ST index for +CONTAINS = sttype_to_index(Int(CONTAINS)) = 2 + 3 + 1 = 6
const _CONTAINS_POS_IDX = sttype_to_index(Int(CONTAINS))
# ST index for -CONTAINS = sttype_to_index(-Int(CONTAINS)) = -2 + 3 + 1 = 2
const _CONTAINS_NEG_IDX = sttype_to_index(-Int(CONTAINS))

"""
    _get_contained_children(store::MemoryStore, nptr::NodePtr) -> Vector{NodePtr}

Return NodePtrs of nodes that `nptr` contains (via positive CONTAINS links).
"""
function _get_contained_children(store::MemoryStore, nptr::NodePtr)
    node = mem_get_node(store, nptr)
    node === nothing && return NodePtr[]
    children = NodePtr[]
    for lnk in node.incidence[_CONTAINS_POS_IDX]
        lnk.dst != NO_NODE_PTR && push!(children, lnk.dst)
    end
    return children
end

"""
    _get_containing_parent(store::MemoryStore, nptr::NodePtr) -> Union{NodePtr, Nothing}

Return the first node that contains `nptr` (via negative CONTAINS / "belongs to" links).
"""
function _get_containing_parent(store::MemoryStore, nptr::NodePtr)
    node = mem_get_node(store, nptr)
    node === nothing && return nothing
    for lnk in node.incidence[_CONTAINS_NEG_IDX]
        lnk.dst != NO_NODE_PTR && return lnk.dst
    end
    return nothing
end

"""
    focal_view(store::MemoryStore, root::NodePtr; depth::Int=1) -> FocalView

Build a hierarchical view from `root` by traversing CONTAINS arrows downward.
Children are nodes that `root` contains (via positive CONTAINS arrows).
"""
function focal_view(store::MemoryStore, root::NodePtr; depth::Int=1)
    children = _get_contained_children(store, root)
    parent = _get_containing_parent(store, root)
    return FocalView(root, children, parent, NodePtr[root], depth)
end

"""
    drill_down(store::MemoryStore, fv::FocalView, child::NodePtr) -> FocalView

Drill into a child node, making it the new focal root while preserving breadcrumb.
"""
function drill_down(store::MemoryStore, fv::FocalView, child::NodePtr)
    child in fv.children || error("NodePtr $child is not a child of the current focal root")
    new_children = _get_contained_children(store, child)
    new_breadcrumb = vcat(fv.breadcrumb, [child])
    parent = fv.root
    return FocalView(child, new_children, parent, new_breadcrumb, fv.depth + 1)
end

"""
    drill_up(store::MemoryStore, fv::FocalView) -> FocalView

Go up one level in the hierarchy using the breadcrumb trail.
"""
function drill_up(store::MemoryStore, fv::FocalView)
    length(fv.breadcrumb) <= 1 && error("Already at the top of the hierarchy")
    new_root = fv.breadcrumb[end-1]
    new_children = _get_contained_children(store, new_root)
    new_breadcrumb = fv.breadcrumb[1:end-1]
    parent = _get_containing_parent(store, new_root)
    return FocalView(new_root, new_children, parent, new_breadcrumb, fv.depth - 1)
end

"""
    _node_label(store::MemoryStore, nptr::NodePtr) -> String

Return a display label for a node pointer.
"""
function _node_label(store::MemoryStore, nptr::NodePtr)
    node = mem_get_node(store, nptr)
    node === nothing && return "???"
    return node.s
end

"""
    tree_view(store::MemoryStore, root::NodePtr; max_depth::Int=3) -> String

Render a text tree view of the hierarchy from root.
"""
function tree_view(store::MemoryStore, root::NodePtr; max_depth::Int=3)
    buf = IOBuffer()
    _tree_view_recurse!(buf, store, root, "", true, max_depth, 0)
    return String(take!(buf))
end

function _tree_view_recurse!(buf::IOBuffer, store::MemoryStore, nptr::NodePtr,
                              prefix::String, is_last::Bool, max_depth::Int, depth::Int)
    connector = depth == 0 ? "" : (is_last ? "└── " : "├── ")
    println(buf, prefix * connector * _node_label(store, nptr))

    depth >= max_depth && return

    children = _get_contained_children(store, nptr)
    child_prefix = depth == 0 ? "" : prefix * (is_last ? "    " : "│   ")
    for (i, child) in enumerate(children)
        _tree_view_recurse!(buf, store, child, child_prefix, i == length(children), max_depth, depth + 1)
    end
end

"""
    hierarchy_roots(store::MemoryStore) -> Vector{NodePtr}

Find all nodes that contain other nodes but are not contained by any node.
These are the top-level roots of the containment hierarchy.
"""
function hierarchy_roots(store::MemoryStore)
    roots = NodePtr[]
    for (nptr, node) in store.nodes
        has_children = !isempty(node.incidence[_CONTAINS_POS_IDX])
        has_parent = !isempty(node.incidence[_CONTAINS_NEG_IDX])
        if has_children && !has_parent
            push!(roots, nptr)
        end
    end
    return sort!(roots)
end

# ══════════════════════════════════════════════════════════════════
# 2. ETC Validation in Compilation
# ══════════════════════════════════════════════════════════════════

"""
    validate_compiled_graph!(store::MemoryStore; verbose::Bool=false) -> Vector{String}

Run ETC validation on all nodes in the store. First infers ETC types,
then validates them. Returns a flat list of warnings about type
mismatches (e.g., a Thing with only LEADSTO links, an Event with no
temporal arrows).
"""
function validate_compiled_graph!(store::MemoryStore; verbose::Bool=false)
    all_warnings = String[]

    for (nptr, node) in store.nodes
        # Infer ETC from link structure
        node.psi = infer_etc(node)

        if verbose
            psi_str = show_psi(node.psi)
            if !isempty(psi_str)
                push!(all_warnings, "INFO: Node \"$(node.s)\" inferred as $psi_str")
            end
        end

        # Validate consistency
        warns = validate_etc(node)
        append!(all_warnings, warns)
    end

    return all_warnings
end

# ══════════════════════════════════════════════════════════════════
# 3. Provenance and Attribution
# ══════════════════════════════════════════════════════════════════

"""
    Provenance

Metadata tracking the origin of a node or link.
"""
struct Provenance
    source::String      # source file or identifier
    line::Int           # line number (0 if unknown)
    timestamp::DateTime # when the data was added
    author::String      # who created it
end

const _PROV_PREFIX_SOURCE = "prov:source:"
const _PROV_PREFIX_LINE   = "prov:line:"
const _PROV_PREFIX_TIME   = "prov:time:"
const _PROV_PREFIX_AUTHOR = "prov:author:"

# ST index for +EXPRESS = sttype_to_index(Int(EXPRESS)) = 3 + 3 + 1 = 7
const _EXPRESS_POS_IDX = sttype_to_index(Int(EXPRESS))

"""
    set_provenance!(store::MemoryStore, nptr::NodePtr, prov::Provenance)

Attach provenance metadata to a node via EXPRESS annotation nodes.
Creates annotation nodes linked via the `note` arrow.
"""
function set_provenance!(store::MemoryStore, nptr::NodePtr, prov::Provenance)
    node = mem_get_node(store, nptr)
    node === nothing && error("Node not found: $nptr")

    note_entry = get_arrow_by_name("note")
    note_entry === nothing && error("Arrow 'note' not registered. Load config or call add_mandatory_arrows!() first.")

    chap = node.chap

    # Create annotation nodes for each provenance field
    src_node = mem_vertex!(store, _PROV_PREFIX_SOURCE * prov.source, chap)
    mem_edge!(store, node, note_entry.short, src_node)

    if prov.line > 0
        line_node = mem_vertex!(store, _PROV_PREFIX_LINE * string(prov.line), chap)
        mem_edge!(store, node, note_entry.short, line_node)
    end

    time_node = mem_vertex!(store, _PROV_PREFIX_TIME * string(prov.timestamp), chap)
    mem_edge!(store, node, note_entry.short, time_node)

    if !isempty(prov.author)
        auth_node = mem_vertex!(store, _PROV_PREFIX_AUTHOR * prov.author, chap)
        mem_edge!(store, node, note_entry.short, auth_node)
    end

    nothing
end

"""
    get_provenance(store::MemoryStore, nptr::NodePtr) -> Union{Provenance, Nothing}

Retrieve provenance metadata from a node's EXPRESS annotations.
"""
function get_provenance(store::MemoryStore, nptr::NodePtr)
    node = mem_get_node(store, nptr)
    node === nothing && return nothing

    source = ""
    line = 0
    timestamp = DateTime(0)
    author = ""

    # Scan EXPRESS+ links for provenance annotation nodes
    for lnk in node.incidence[_EXPRESS_POS_IDX]
        dst_node = mem_get_node(store, lnk.dst)
        dst_node === nothing && continue
        txt = dst_node.s

        if startswith(txt, _PROV_PREFIX_SOURCE)
            source = txt[length(_PROV_PREFIX_SOURCE)+1:end]
        elseif startswith(txt, _PROV_PREFIX_LINE)
            line = parse(Int, txt[length(_PROV_PREFIX_LINE)+1:end]; base=10)
        elseif startswith(txt, _PROV_PREFIX_TIME)
            try
                timestamp = DateTime(txt[length(_PROV_PREFIX_TIME)+1:end])
            catch
                # leave as default
            end
        elseif startswith(txt, _PROV_PREFIX_AUTHOR)
            author = txt[length(_PROV_PREFIX_AUTHOR)+1:end]
        end
    end

    isempty(source) && return nothing
    return Provenance(source, line, timestamp, author)
end

"""
    compile_n4l_with_provenance!(store::MemoryStore, text::String;
        source::String="<string>", author::String="", config_dir=nothing) -> N4LCompileResult

Like compile_n4l_string! but attaches provenance to every created node.
"""
function compile_n4l_with_provenance!(store::MemoryStore, text::String;
                                       source::String="<string>",
                                       author::String="",
                                       config_dir::Union{String, Nothing}=nothing)
    # Record nodes before compilation
    before_nptrs = Set(keys(store.nodes))

    result = compile_n4l_string!(store, text; config_dir=config_dir)

    # Attach provenance to all newly created nodes
    now_ts = Dates.now()
    prov = Provenance(source, 0, now_ts, author)
    for nptr in keys(store.nodes)
        nptr in before_nptrs && continue
        set_provenance!(store, nptr, prov)
    end

    return result
end
