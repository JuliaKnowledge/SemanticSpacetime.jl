#=
Weighted search operations for Semantic Spacetime.

Provides weighted path search, Dijkstra shortest path,
and path ranking by link weight.
=#

# ──────────────────────────────────────────────────────────────────
# WeightedPath
# ──────────────────────────────────────────────────────────────────

"""
    WeightedPath

A path through the graph with associated link weights.
"""
struct WeightedPath
    nodes::Vector{NodePtr}
    links::Vector{Link}
    total_weight::Float64
end

WeightedPath() = WeightedPath(NodePtr[], Link[], 0.0)

Base.show(io::IO, wp::WeightedPath) =
    print(io, "WeightedPath($(length(wp.nodes)) nodes, weight=$(wp.total_weight))")

# ──────────────────────────────────────────────────────────────────
# Weighted search (BFS with weight filtering)
# ──────────────────────────────────────────────────────────────────

"""
    weighted_search(store::MemoryStore, start::NodePtr;
                    max_depth::Int=5, min_weight::Float32=0.0f0) -> Vector{WeightedPath}

Search paths from `start` where link weights affect ranking/filtering.
Only follows links with weight ≥ `min_weight`. Returns all discovered
paths up to `max_depth` hops.
"""
function weighted_search(store::MemoryStore, start::NodePtr;
                         max_depth::Int=5, min_weight::Float32=0.0f0)
    paths = WeightedPath[]
    start_node = mem_get_node(store, start)
    isnothing(start_node) && return paths

    # BFS queue: (current_nodes, current_links, current_weight)
    queue = Tuple{Vector{NodePtr}, Vector{Link}, Float64}[]
    push!(queue, ([start], Link[], 0.0))

    while !isempty(queue)
        current_nodes, current_links, current_weight = popfirst!(queue)
        current_nptr = last(current_nodes)

        node = mem_get_node(store, current_nptr)
        isnothing(node) && continue

        found_next = false
        for st_links in node.incidence
            for lnk in st_links
                lnk.wgt < min_weight && continue
                lnk.dst == NO_NODE_PTR && continue
                # Avoid cycles
                lnk.dst in current_nodes && continue

                new_nodes = vcat(current_nodes, [lnk.dst])
                new_links = vcat(current_links, [lnk])
                new_weight = current_weight + Float64(lnk.wgt)

                path = WeightedPath(new_nodes, new_links, new_weight)
                push!(paths, path)
                found_next = true

                if length(new_nodes) - 1 < max_depth
                    push!(queue, (new_nodes, new_links, new_weight))
                end
            end
        end
    end

    return paths
end

# ──────────────────────────────────────────────────────────────────
# Dijkstra shortest path
# ──────────────────────────────────────────────────────────────────

"""
    dijkstra_path(store::MemoryStore, from::NodePtr, to::NodePtr) -> Union{WeightedPath, Nothing}

Find the shortest weighted path from `from` to `to` using Dijkstra's
algorithm. Distance = 1/link.wgt so heavier weights = shorter distance.
Links with zero weight are skipped.
"""
function dijkstra_path(store::MemoryStore, from::NodePtr, to::NodePtr)
    from == to && return WeightedPath([from], Link[], 0.0)

    dist = Dict{NodePtr, Float64}(from => 0.0)
    prev_node = Dict{NodePtr, NodePtr}()
    prev_link = Dict{NodePtr, Link}()
    visited = Set{NodePtr}()

    # Simple priority queue using a sorted list
    # (distance, node_ptr)
    pq = Tuple{Float64, NodePtr}[(0.0, from)]

    while !isempty(pq)
        # Extract minimum distance node
        sort!(pq, by=first)
        d, u = popfirst!(pq)
        u in visited && continue
        push!(visited, u)

        u == to && break

        node = mem_get_node(store, u)
        isnothing(node) && continue

        for st_links in node.incidence
            for lnk in st_links
                lnk.dst == NO_NODE_PTR && continue
                lnk.wgt <= 0.0f0 && continue
                lnk.dst in visited && continue

                edge_dist = 1.0 / Float64(lnk.wgt)
                alt = d + edge_dist

                if alt < get(dist, lnk.dst, Inf)
                    dist[lnk.dst] = alt
                    prev_node[lnk.dst] = u
                    prev_link[lnk.dst] = lnk
                    push!(pq, (alt, lnk.dst))
                end
            end
        end
    end

    # Reconstruct path
    !haskey(prev_node, to) && return nothing

    path_nodes = NodePtr[to]
    path_links = Link[]
    current = to
    total_weight = 0.0

    while current != from
        lnk = prev_link[current]
        pushfirst!(path_links, lnk)
        total_weight += Float64(lnk.wgt)
        current = prev_node[current]
        pushfirst!(path_nodes, current)
    end

    return WeightedPath(path_nodes, path_links, total_weight)
end

# ──────────────────────────────────────────────────────────────────
# Path ranking
# ──────────────────────────────────────────────────────────────────

"""
    rank_by_weight(paths::Vector{WeightedPath}; ascending::Bool=false) -> Vector{WeightedPath}

Sort paths by total weight. Default is descending (heaviest first).
"""
function rank_by_weight(paths::Vector{WeightedPath}; ascending::Bool=false)
    return sort(paths, by=p -> p.total_weight, rev=!ascending)
end
