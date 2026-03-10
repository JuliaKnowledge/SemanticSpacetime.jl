#=
Advanced graph traversal for Semantic Spacetime.

Adjoint operations, wave front overlap, constrained cone paths,
matroid/supernode grouping, bidirectional path search, and longest
axial path.

Ported from SSTorytime/pkg/SSTorytime/SSTorytime.go
(AdjointArrows, WaveFrontsOverlap, GetConstrainedConePaths,
 GetPathsAndSymmetries, GetLongestAxialPath, etc.).
=#

# ──────────────────────────────────────────────────────────────────
# Adjoint operations
# ──────────────────────────────────────────────────────────────────

"""
    adjoint_arrows(arrowptrs::Vector{ArrowPtr}) -> Vector{ArrowPtr}

Return the inverse of each arrow pointer, deduplicated.
Arrows without a registered inverse are silently dropped.
"""
function adjoint_arrows(arrowptrs::Vector{ArrowPtr})::Vector{ArrowPtr}
    result = ArrowPtr[]
    seen = Set{ArrowPtr}()
    for aptr in arrowptrs
        inv = get_inverse_arrow(aptr)
        if !isnothing(inv) && !(inv in seen)
            push!(seen, inv)
            push!(result, inv)
        end
    end
    return result
end

"""
    adjoint_sttype(sttypes::Vector{Int}) -> Vector{Int}

Return negated and reversed ST types (adjoint in the ST spectrum).
"""
function adjoint_sttype(sttypes::Vector{Int})::Vector{Int}
    result = [-st for st in reverse(sttypes)]
    return result
end

"""
    adjoint_link_path(path::Vector{Link}) -> Vector{Link}

Reverse a link path and replace each arrow with its inverse.
Links whose arrows have no registered inverse are kept with the original arrow.
"""
function adjoint_link_path(path::Vector{Link})::Vector{Link}
    isempty(path) && return Link[]
    result = Vector{Link}(undef, length(path))
    n = length(path)
    for i in 1:n
        lnk = path[n - i + 1]
        inv = get_inverse_arrow(lnk.arr)
        arr = isnothing(inv) ? lnk.arr : inv
        result[i] = Link(arr, lnk.wgt, lnk.ctx, lnk.dst)
    end
    return result
end

# ──────────────────────────────────────────────────────────────────
# Wave front operations
# ──────────────────────────────────────────────────────────────────

"""
    wave_front(paths::Vector{Vector{Link}}, num::Int) -> Vector{NodePtr}

Collect the wave front: the last `Dst` from each path.
`num` is unused but kept for API compatibility with the Go version.
"""
function wave_front(paths::Vector{Vector{Link}}, num::Int)::Vector{NodePtr}
    front = NodePtr[]
    for path in paths
        isempty(path) && continue
        push!(front, last(path).dst)
    end
    return front
end

"""
    nodes_overlap(left::Vector{NodePtr}, right::Vector{NodePtr}) -> Dict{Int,Vector{Int}}

Find matching NodePtrs between `left` and `right` wave fronts.
Returns a dict mapping left-index => [right-indices] where left[l] == right[r].
(Indices are 1-based.)
"""
function nodes_overlap(left::Vector{NodePtr}, right::Vector{NodePtr})::Dict{Int,Vector{Int}}
    result = Dict{Int,Vector{Int}}()
    # Build index of right side
    right_idx = Dict{NodePtr, Vector{Int}}()
    for (r, nptr) in enumerate(right)
        push!(get!(right_idx, nptr, Int[]), r)
    end
    for (l, nptr) in enumerate(left)
        if haskey(right_idx, nptr)
            result[l] = right_idx[nptr]
        end
    end
    return result
end

"""
    wave_fronts_overlap(store::AbstractSSTStore,
                        left_paths::Vector{Vector{Link}},
                        right_paths::Vector{Vector{Link}},
                        ldepth::Int, rdepth::Int)

Expand wave fronts from left (forward) and right (backward) path sets,
find overlapping nodes, and splice paths together.

Returns `(solutions::Vector{Vector{Link}}, loops::Vector{Vector{Link}})`.
"""
function wave_fronts_overlap(store::AbstractSSTStore,
                             left_paths::Vector{Vector{Link}},
                             right_paths::Vector{Vector{Link}},
                             ldepth::Int, rdepth::Int)
    solutions = Vector{Link}[]
    loops = Vector{Link}[]

    left_front = wave_front(left_paths, ldepth)
    right_front = wave_front(right_paths, rdepth)

    overlap = nodes_overlap(left_front, right_front)

    for (l_idx, r_indices) in overlap
        for r_idx in r_indices
            # Splice: left path + adjoint of right path (skip overlap node)
            lpath = left_paths[l_idx]
            rpath = right_paths[r_idx]
            adj_rpath = adjoint_link_path(rpath)
            spliced = right_complement_join(lpath, adj_rpath)
            if is_dag(spliced)
                push!(solutions, spliced)
            else
                push!(loops, spliced)
            end
        end
    end

    return (solutions, loops)
end

"""
    left_join(splice::Vector{Link}, seq::Vector{Link}) -> Vector{Link}

Concatenate two link sequences.
"""
function left_join(splice::Vector{Link}, seq::Vector{Link})::Vector{Link}
    return vcat(splice, seq)
end

"""
    right_complement_join(splice::Vector{Link}, adjoint::Vector{Link}) -> Vector{Link}

Concatenate splice with adjoint, skipping the first element of adjoint
(which is the overlap node).
"""
function right_complement_join(splice::Vector{Link}, adjoint::Vector{Link})::Vector{Link}
    if length(adjoint) <= 1
        return copy(splice)
    end
    return vcat(splice, adjoint[2:end])
end

"""
    is_dag(seq::Vector{Link}) -> Bool

Check that no `NodePtr` destination appears more than once in the link sequence.
"""
function is_dag(seq::Vector{Link})::Bool
    seen = Set{NodePtr}()
    for lnk in seq
        lnk.dst in seen && return false
        push!(seen, lnk.dst)
    end
    return true
end

# ──────────────────────────────────────────────────────────────────
# Matroid / supernode grouping
# ──────────────────────────────────────────────────────────────────

"""
    together!(matroid::Vector{Vector{NodePtr}}, n1::NodePtr, n2::NodePtr)

Group `n1` and `n2` into the same supernode set within the matroid.
If either node already belongs to a set, the other is merged into it.
If both belong to different sets, the sets are merged.
If neither exists, a new set is created.
"""
function together!(matroid::Vector{Vector{NodePtr}}, n1::NodePtr, n2::NodePtr)
    idx1 = _find_in_matroid(matroid, n1)
    idx2 = _find_in_matroid(matroid, n2)

    if idx1 == 0 && idx2 == 0
        # Neither found — create new group
        push!(matroid, NodePtr[n1])
        if n1 != n2
            idemp_add_nodeptr!(matroid[end], n2)
        end
    elseif idx1 != 0 && idx2 == 0
        idemp_add_nodeptr!(matroid[idx1], n2)
    elseif idx1 == 0 && idx2 != 0
        idemp_add_nodeptr!(matroid[idx2], n1)
    elseif idx1 != idx2
        # Merge sets
        for nptr in matroid[idx2]
            idemp_add_nodeptr!(matroid[idx1], nptr)
        end
        deleteat!(matroid, idx2)
    end
    # If idx1 == idx2, already in the same group — nothing to do
    nothing
end

function _find_in_matroid(matroid::Vector{Vector{NodePtr}}, n::NodePtr)::Int
    for (i, group) in enumerate(matroid)
        if in_node_set(group, n)
            return i
        end
    end
    return 0
end

"""
    idemp_add_nodeptr!(set::Vector{NodePtr}, n::NodePtr)

Idempotent add: push `n` only if not already in `set`.
"""
function idemp_add_nodeptr!(set::Vector{NodePtr}, n::NodePtr)
    in_node_set(set, n) || push!(set, n)
    nothing
end

"""
    in_node_set(list::Vector{NodePtr}, node::NodePtr) -> Bool

Check whether `node` is present in `list`.
"""
function in_node_set(list::Vector{NodePtr}, node::NodePtr)::Bool
    for n in list
        n == node && return true
    end
    return false
end

# ──────────────────────────────────────────────────────────────────
# Constrained cone paths
# ──────────────────────────────────────────────────────────────────

"""
    get_constrained_cone_paths(store::AbstractSSTStore, start::Vector{NodePtr},
                               depth::Int; chapter::String="",
                               context::Vector{String}=String[],
                               arrows::Vector{ArrowPtr}=ArrowPtr[],
                               sttypes::Vector{Int}=Int[],
                               limit::Int=100, forward::Bool=true)

Expand cone from each start node, filtering by chapter, context,
arrow types, and ST types. When `forward=true` (default), follows
positive ST channels; when `forward=false`, follows negative ST channels.
Returns `(paths, count)`.
"""
function get_constrained_cone_paths(store::AbstractSSTStore, start::Vector{NodePtr},
                                    depth::Int; chapter::String="",
                                    context::Vector{String}=String[],
                                    arrows::Vector{ArrowPtr}=ArrowPtr[],
                                    sttypes::Vector{Int}=Int[],
                                    limit::Int=100, forward::Bool=true)
    all_paths = Vector{Link}[]
    count = 0

    arrow_set = isempty(arrows) ? nothing : Set(arrows)
    sttype_set = isempty(sttypes) ? nothing : Set(sttypes)

    for nptr in start
        paths, c = _constrained_expand(store, nptr, depth, chapter, context,
                                        arrow_set, sttype_set, limit - count, forward)
        append!(all_paths, paths)
        count += c
        count >= limit && break
    end

    return (all_paths, count)
end

function _constrained_expand(store::AbstractSSTStore, start::NodePtr, depth::Int,
                             chapter::String, context::Vector{String},
                             arrow_set, sttype_set, limit::Int, forward::Bool=true)
    paths = Vector{Link}[]
    _constrained_expand_inner!(store, start, depth, limit, chapter, context,
                               arrow_set, sttype_set, paths, Link[], Set{NodePtr}(), forward)
    return (paths, length(paths))
end

function _constrained_expand_inner!(store::AbstractSSTStore, current::NodePtr,
                                    remaining::Int, limit::Int,
                                    chapter::String, context::Vector{String},
                                    arrow_set, sttype_set,
                                    paths::Vector{Vector{Link}},
                                    prefix::Vector{Link},
                                    visited::Set{NodePtr},
                                    forward::Bool=true)
    length(paths) >= limit && return nothing
    remaining <= 0 && return nothing

    node = mem_get_node(store, current)
    isnothing(node) && return nothing

    # Chapter filter
    if !isempty(chapter) && !isempty(node.chap)
        !occursin(lowercase(chapter), lowercase(node.chap)) && return nothing
    end

    push!(visited, current)

    for stidx in 1:ST_TOP
        st = index_to_sttype(stidx)
        if forward
            st <= 0 && continue  # forward only
        else
            st >= 0 && continue  # backward only
        end

        # ST type filter
        if !isnothing(sttype_set) && !(st in sttype_set)
            continue
        end

        for lnk in node.incidence[stidx]
            lnk.dst in visited && continue
            length(paths) >= limit && return nothing

            # Arrow filter
            if !isnothing(arrow_set) && !(lnk.arr in arrow_set)
                continue
            end

            # Context filter
            if !isempty(context) && lnk.ctx > 0
                ctx_str = get_context(lnk.ctx)
                if !isempty(ctx_str) && !any(c -> occursin(lowercase(c), lowercase(ctx_str)), context)
                    continue
                end
            end

            new_prefix = vcat(prefix, [lnk])
            push!(paths, copy(new_prefix))

            _constrained_expand_inner!(store, lnk.dst, remaining - 1, limit,
                                       chapter, context, arrow_set, sttype_set,
                                       paths, new_prefix, copy(visited), forward)
        end
    end
    nothing
end

"""
    get_constrained_fwd_links(store::AbstractSSTStore, start::Vector{NodePtr};
                              chapter::String="", context::Vector{String}=String[],
                              sttypes::Vector{Int}=Int[],
                              arrows::Vector{ArrowPtr}=ArrowPtr[],
                              limit::Int=100)

Get immediate forward links from start nodes matching constraints.
Returns `Vector{Link}`.
"""
function get_constrained_fwd_links(store::AbstractSSTStore, start::Vector{NodePtr};
                                   chapter::String="", context::Vector{String}=String[],
                                   sttypes::Vector{Int}=Int[],
                                   arrows::Vector{ArrowPtr}=ArrowPtr[],
                                   limit::Int=100)
    result = Link[]
    arrow_set = isempty(arrows) ? nothing : Set(arrows)
    sttype_set = isempty(sttypes) ? nothing : Set(sttypes)

    for nptr in start
        node = mem_get_node(store, nptr)
        isnothing(node) && continue

        if !isempty(chapter) && !isempty(node.chap)
            !occursin(lowercase(chapter), lowercase(node.chap)) && continue
        end

        for stidx in 1:ST_TOP
            st = index_to_sttype(stidx)
            st <= 0 && continue

            if !isnothing(sttype_set) && !(st in sttype_set)
                continue
            end

            for lnk in node.incidence[stidx]
                length(result) >= limit && return result

                if !isnothing(arrow_set) && !(lnk.arr in arrow_set)
                    continue
                end

                if !isempty(context) && lnk.ctx > 0
                    ctx_str = get_context(lnk.ctx)
                    if !isempty(ctx_str) && !any(c -> occursin(lowercase(c), lowercase(ctx_str)), context)
                        continue
                    end
                end

                push!(result, lnk)
            end
        end
    end
    return result
end

# ──────────────────────────────────────────────────────────────────
# Bidirectional path search with wave front overlap
# ──────────────────────────────────────────────────────────────────

"""
    get_paths_and_symmetries(store::AbstractSSTStore,
                             start_set::Vector{NodePtr},
                             end_set::Vector{NodePtr};
                             chapter::String="",
                             context::Vector{String}=String[],
                             arrows::Vector{ArrowPtr}=ArrowPtr[],
                             sttypes::Vector{Int}=Int[],
                             mindepth::Int=1, maxdepth::Int=10)

Bidirectional search using wave front overlap. Expands forward from
start_set and backward (adjoint) from end_set, splicing at overlap.

Returns `(solutions::Vector{Vector{Link}}, loops::Vector{Vector{Link}})`.
"""
function get_paths_and_symmetries(store::AbstractSSTStore,
                                  start_set::Vector{NodePtr},
                                  end_set::Vector{NodePtr};
                                  chapter::String="",
                                  context::Vector{String}=String[],
                                  arrows::Vector{ArrowPtr}=ArrowPtr[],
                                  sttypes::Vector{Int}=Int[],
                                  mindepth::Int=1, maxdepth::Int=10)
    all_solutions = Vector{Link}[]
    all_loops = Vector{Link}[]

    inv_arrows = adjoint_arrows(arrows)
    inv_sttypes = adjoint_sttype(sttypes)

    for depth in mindepth:maxdepth
        # Forward expansion from start
        left_paths, _ = get_constrained_cone_paths(store, start_set, depth;
                            chapter=chapter, context=context,
                            arrows=arrows, sttypes=sttypes)

        # Backward expansion from end (using inverse arrows/sttypes)
        right_paths, _ = get_constrained_cone_paths(store, end_set, depth;
                            chapter=chapter, context=context,
                            arrows=isempty(inv_arrows) ? arrows : inv_arrows,
                            sttypes=isempty(inv_sttypes) ? sttypes : inv_sttypes,
                            forward=false)

        solutions, loops = wave_fronts_overlap(store, left_paths, right_paths,
                                               depth, depth)

        append!(all_solutions, solutions)
        append!(all_loops, loops)

        !isempty(solutions) && break
    end

    return (all_solutions, all_loops)
end

"""
    get_paths_and_symmetries_legacy(store::AbstractSSTStore,
                                    start_set::Vector{NodePtr},
                                    end_set::Vector{NodePtr};
                                    chapter::String="",
                                    context::Vector{String}=String[],
                                    arrowptrs::Vector{ArrowPtr}=ArrowPtr[],
                                    sttypes::Vector{Int}=Int[],
                                    mindepth::Int=1, maxdepth::Int=10)

Legacy bidirectional wave-front path search (sequential version of Go's parallel implementation).
Alternates expanding left and right depths independently.

Returns `Vector{Vector{Link}}`.
"""
function get_paths_and_symmetries_legacy(store::AbstractSSTStore,
                                         start_set::Vector{NodePtr},
                                         end_set::Vector{NodePtr};
                                         chapter::String="",
                                         context::Vector{String}=String[],
                                         arrowptrs::Vector{ArrowPtr}=ArrowPtr[],
                                         sttypes::Vector{Int}=Int[],
                                         mindepth::Int=1, maxdepth::Int=10)::Vector{Vector{Link}}
    isempty(start_set) && return Vector{Link}[]
    isempty(end_set) && return Vector{Link}[]

    adj_arrowptrs = adjoint_arrows(arrowptrs)
    adj_sttypes = adjoint_sttype(sttypes)

    ldepth = 1
    rdepth = 1

    for turn in 0:(2*maxdepth)
        left_paths, lnum = get_constrained_cone_paths(store, start_set, ldepth;
                               chapter=chapter, context=context,
                               arrows=arrowptrs, sttypes=sttypes)
        right_paths, rnum = get_constrained_cone_paths(store, end_set, rdepth;
                                chapter=chapter, context=context,
                                arrows=isempty(adj_arrowptrs) ? arrowptrs : adj_arrowptrs,
                                sttypes=isempty(adj_sttypes) ? sttypes : adj_sttypes,
                                forward=false)

        solutions, loop_corrections = wave_fronts_overlap(store, left_paths, right_paths,
                                                           ldepth, rdepth)

        !isempty(solutions) && return solutions
        !isempty(loop_corrections) && return loop_corrections

        if turn % 2 == 0
            ldepth += 1
        else
            rdepth += 1
        end

        (ldepth >= maxdepth && rdepth >= maxdepth) && break
    end

    return Vector{Link}[]
end

"""
    get_longest_axial_path(store::AbstractSSTStore, nptr::NodePtr,
                           arrowptr::ArrowPtr; limit::Int=100) -> Vector{Link}

Follow a single arrow type from `nptr` as far as possible, returning
the longest chain of links using only that arrow.
"""
function get_longest_axial_path(store::AbstractSSTStore, nptr::NodePtr,
                                arrowptr::ArrowPtr; limit::Int=100)::Vector{Link}
    path = Link[]
    visited = Set{NodePtr}([nptr])
    current = nptr

    for _ in 1:limit
        node = mem_get_node(store, current)
        isnothing(node) && break

        found = false
        for stidx in 1:ST_TOP
            for lnk in node.incidence[stidx]
                if lnk.arr == arrowptr && !(lnk.dst in visited)
                    push!(path, lnk)
                    push!(visited, lnk.dst)
                    current = lnk.dst
                    found = true
                    break
                end
            end
            found && break
        end
        found || break
    end

    return path
end

"""
    truncate_paths_by_arrow(path::Vector{Link}, arrow::ArrowPtr)

Truncate path at the first link that does not match `arrow`.
Returns the prefix of matching links.
"""
function truncate_paths_by_arrow(path::Vector{Link}, arrow::ArrowPtr)
    result = Link[]
    for lnk in path
        lnk.arr != arrow && break
        push!(result, lnk)
    end
    return result
end
