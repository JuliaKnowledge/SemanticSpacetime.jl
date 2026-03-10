#=
Node orbit system and centrality analysis for Semantic Spacetime.

Computes orbits (neighborhoods) around nodes organized by ST type,
betweenness centrality from path solutions, and supernode grouping
from conic paths.

Ported from SSTorytime/pkg/SSTorytime/SSTorytime.go
(GetNodeOrbit, AssembleSatellitesBySTtype, BetweennessCentrality,
 SuperNodesByConicPath, GetPathTransverseSuperNodes).
=#

# ──────────────────────────────────────────────────────────────────
# Node orbits
# ──────────────────────────────────────────────────────────────────

"""
    get_node_orbit(store::AbstractSSTStore, nptr::NodePtr;
                   exclude_vector::String="", limit::Int=100)

Compute the orbit of a node — its neighborhood organized by ST type.
Returns `Vector{Vector{Orbit}}` of length `ST_TOP`, where each
inner vector contains `Orbit` entries for that ST channel.

Uses forward cone expansion to sweep the neighborhood, then
assembles satellites by ST type index.
"""
function get_node_orbit(store::AbstractSSTStore, nptr::NodePtr;
                        exclude_vector::String="", limit::Int=100)
    orbits = [Orbit[] for _ in 1:ST_TOP]

    node = mem_get_node(store, nptr)
    isnothing(node) && return orbits

    # Sweep using forward cone paths (entire neighborhood)
    cone = forward_cone(store, nptr; depth=3, limit=limit)
    sweep = cone.paths

    for stidx in 1:ST_TOP
        orbits[stidx] = assemble_satellites_by_sttype(store, stidx, orbits[stidx],
                                                       sweep; exclude_vector=exclude_vector,
                                                       probe_radius=3, limit=limit)
    end

    return orbits
end

"""
    assemble_satellites_by_sttype(store::AbstractSSTStore, stindex::Int,
                                  satellite::Vector{Orbit},
                                  sweep::Vector{Vector{Link}};
                                  exclude_vector::String="",
                                  probe_radius::Int=3,
                                  limit::Int=100) -> Vector{Orbit}

From the sweep paths, extract links belonging to the given ST type index
and assemble them into Orbit entries with radius information.
"""
function assemble_satellites_by_sttype(store::AbstractSSTStore, stindex::Int,
                                       satellite::Vector{Orbit},
                                       sweep::Vector{Vector{Link}};
                                       exclude_vector::String="",
                                       probe_radius::Int=3,
                                       limit::Int=100)::Vector{Orbit}
    result = copy(satellite)
    already = Set{String}()

    # Seed the already-seen set from existing satellites
    for orb in result
        push!(already, orb.text)
    end

    for path in sweep
        for (depth, lnk) in enumerate(path)
            depth > probe_radius && break
            length(result) >= limit && return result

            # Check if arrow matches the requested ST type
            entry = get_arrow_by_ptr(lnk.arr)
            entry.stindex != stindex && continue

            dst_node = mem_get_node(store, lnk.dst)
            isnothing(dst_node) && continue

            text = dst_node.s

            # Skip excluded vectors
            if !isempty(exclude_vector) && text == exclude_vector
                continue
            end

            ctx_str = lnk.ctx > 0 ? get_context(lnk.ctx) : ""

            orb = Orbit(
                depth,          # radius
                entry.short,    # arrow name
                stindex,        # stindex
                lnk.dst,        # destination
                ctx_str,        # context
                text,           # text
                Coords(),       # xyz (placeholder)
                Coords(),       # ooo origin (placeholder)
            )

            idemp_add_satellite!(result, orb, already)
        end
    end

    return result
end

"""
    idemp_add_satellite!(list::Vector{Orbit}, item::Orbit, already::Set{String})

Idempotent add: push `item` only if its text is not already in the set.
"""
function idemp_add_satellite!(list::Vector{Orbit}, item::Orbit, already::Set{String})
    if !(item.text in already)
        push!(already, item.text)
        push!(list, item)
    end
    nothing
end

# ──────────────────────────────────────────────────────────────────
# Betweenness centrality
# ──────────────────────────────────────────────────────────────────

"""
    tally_path(store::AbstractSSTStore, path::Vector{Link},
               between::Dict{String,Int}) -> Dict{String,Int}

Increment the betweenness counter for each node destination along a path.
Returns the updated dictionary.
"""
function tally_path(store::AbstractSSTStore, path::Vector{Link},
                    between::Dict{String,Int})::Dict{String,Int}
    for lnk in path
        node = mem_get_node(store, lnk.dst)
        isnothing(node) && continue
        key = node.s
        between[key] = get(between, key, 0) + 1
    end
    return between
end

"""
    betweenness_centrality(store::AbstractSSTStore,
                           solutions::Vector{Vector{Link}}) -> Vector{String}

Compute betweenness centrality from a set of solution paths.
Returns node names sorted by descending frequency of appearance
across all paths.
"""
function betweenness_centrality(store::AbstractSSTStore,
                                solutions::Vector{Vector{Link}})::Vector{String}
    between = Dict{String,Int}()

    for path in solutions
        tally_path(store, path, between)
    end

    # Sort by count descending
    sorted = sort(collect(between); by=last, rev=true)
    return [name for (name, _) in sorted]
end

# ──────────────────────────────────────────────────────────────────
# SuperNodes
# ──────────────────────────────────────────────────────────────────

"""
    super_nodes_by_conic_path(solutions::Vector{Vector{Link}},
                              maxdepth::Int) -> Vector{Vector{NodePtr}}

Group nodes that appear at the same depth across different solution
paths into supernode equivalence classes (matroid).
"""
function super_nodes_by_conic_path(solutions::Vector{Vector{Link}},
                                   maxdepth::Int)::Vector{Vector{NodePtr}}
    matroid = Vector{NodePtr}[]

    for depth in 1:maxdepth
        # Collect nodes at this depth across all paths
        nodes_at_depth = NodePtr[]
        for path in solutions
            if depth <= length(path)
                push!(nodes_at_depth, path[depth].dst)
            end
        end

        # Group nodes at same depth together
        for i in 1:length(nodes_at_depth)
            for j in (i+1):length(nodes_at_depth)
                if nodes_at_depth[i] != nodes_at_depth[j]
                    together!(matroid, nodes_at_depth[i], nodes_at_depth[j])
                end
            end
        end
    end

    return matroid
end

"""
    super_nodes(store::AbstractSSTStore, solutions::Vector{Vector{Link}},
                maxdepth::Int) -> Vector{String}

Compute supernodes and return their text names. Each supernode group
is represented as a string "n1 | n2 | ...".
"""
function super_nodes(store::AbstractSSTStore, solutions::Vector{Vector{Link}},
                     maxdepth::Int)::Vector{String}
    matroid = super_nodes_by_conic_path(solutions, maxdepth)
    result = String[]

    for group in matroid
        names = String[]
        for nptr in group
            node = mem_get_node(store, nptr)
            if !isnothing(node)
                push!(names, node.s)
            end
        end
        if !isempty(names)
            push!(result, join(sort!(unique!(names)), " | "))
        end
    end

    return result
end

"""
    get_path_transverse_super_nodes(store::AbstractSSTStore,
                                    solutions::Vector{Vector{Link}},
                                    maxdepth::Int) -> Vector{Vector{NodePtr}}

Find transverse supernodes — nodes that appear across multiple
solution paths at any depth.
"""
function get_path_transverse_super_nodes(store::AbstractSSTStore,
                                         solutions::Vector{Vector{Link}},
                                         maxdepth::Int)::Vector{Vector{NodePtr}}
    # Count how many paths each node appears in
    node_paths = Dict{NodePtr, Set{Int}}()

    for (pidx, path) in enumerate(solutions)
        for (depth, lnk) in enumerate(path)
            depth > maxdepth && break
            paths_set = get!(node_paths, lnk.dst, Set{Int}())
            push!(paths_set, pidx)
        end
    end

    # Group nodes that co-occur in the same set of paths
    matroid = Vector{NodePtr}[]
    for (nptr, paths_set) in node_paths
        length(paths_set) > 1 || continue
        # Find if this node should be grouped with existing ones
        placed = false
        for group in matroid
            for existing in group
                if haskey(node_paths, existing) && node_paths[existing] == paths_set
                    idemp_add_nodeptr!(group, nptr)
                    placed = true
                    break
                end
            end
            placed && break
        end
        if !placed
            push!(matroid, NodePtr[nptr])
        end
    end

    return matroid
end
