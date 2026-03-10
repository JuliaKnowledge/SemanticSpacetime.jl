#=
Graph analysis tools for Semantic Spacetime.

Provides adjacency matrix construction, source/sink detection,
cycle detection, eigenvector centrality, and graph summarization.

Inspired by SSTorytime/src/graph_report.go and the Go library functions
(ComputeEVC, SymmetrizeMatrix, GetDBSingletonBySTType, etc.).
=#

# ──────────────────────────────────────────────────────────────────
# AdjacencyMatrix
# ──────────────────────────────────────────────────────────────────

"""
    AdjacencyMatrix

Sparse adjacency representation for an SST graph using Dict-based
storage. Maps each node to its set of outgoing neighbours with weights.
"""
struct AdjacencyMatrix
    outgoing::Dict{NodePtr, Dict{NodePtr, Float64}}  # src -> {dst -> weight}
    incoming::Dict{NodePtr, Dict{NodePtr, Float64}}  # dst -> {src -> weight}
    nodes::Set{NodePtr}
end

"""
    AdjacencyMatrix()

Create an empty adjacency matrix.
"""
AdjacencyMatrix() = AdjacencyMatrix(
    Dict{NodePtr, Dict{NodePtr, Float64}}(),
    Dict{NodePtr, Dict{NodePtr, Float64}}(),
    Set{NodePtr}()
)

"""
    add_edge!(adj::AdjacencyMatrix, src::NodePtr, dst::NodePtr, weight::Float64=1.0)

Add a directed edge from `src` to `dst` with the given weight.
"""
function add_edge!(adj::AdjacencyMatrix, src::NodePtr, dst::NodePtr, weight::Float64=1.0)
    push!(adj.nodes, src)
    push!(adj.nodes, dst)

    if !haskey(adj.outgoing, src)
        adj.outgoing[src] = Dict{NodePtr, Float64}()
    end
    adj.outgoing[src][dst] = get(adj.outgoing[src], dst, 0.0) + weight

    if !haskey(adj.incoming, dst)
        adj.incoming[dst] = Dict{NodePtr, Float64}()
    end
    adj.incoming[dst][src] = get(adj.incoming[dst], src, 0.0) + weight

    nothing
end

# ──────────────────────────────────────────────────────────────────
# Build adjacency from database
# ──────────────────────────────────────────────────────────────────

"""
    build_adjacency(sst::SSTConnection; arrows::Vector{ArrowPtr}=ArrowPtr[], chapter::String="") -> AdjacencyMatrix

Build an adjacency matrix from the SST database. If `arrows` is non-empty,
only links using those arrow types are included. If `chapter` is non-empty,
only nodes in matching chapters are included.
"""
function build_adjacency(sst::SSTConnection; arrows::Vector{ArrowPtr}=ArrowPtr[], chapter::String="")
    adj = AdjacencyMatrix()

    # Build the WHERE clause
    where_parts = String[]
    if !isempty(chapter)
        ec = sql_escape(chapter)
        push!(where_parts, "lower(Chap) LIKE lower('%$(ec)%')")
    end

    where_clause = isempty(where_parts) ? "" : " WHERE " * join(where_parts, " AND ")

    # Determine which ST columns to scan
    if isempty(arrows)
        stindices = collect(1:ST_TOP)
    else
        stindices = get_sttype_from_arrows(arrows)
    end

    # Query all nodes
    sql = "SELECT NPtr, " * join(ST_COLUMN_NAMES, ", ") * " FROM Node" * where_clause
    result = execute_sql_strict(sst, sql)

    arrow_set = isempty(arrows) ? nothing : Set(arrows)

    for row in LibPQ.Columns(result)
        src = parse_nodeptr(string(row[1]))
        push!(adj.nodes, src)

        for (idx, stindex) in enumerate(1:ST_TOP)
            col_val = row[1 + stindex]
            if isnothing(col_val) || ismissing(col_val)
                continue
            end
            if !(stindex in stindices)
                continue
            end
            links = parse_link_array(string(col_val))
            for lnk in links
                if !isnothing(arrow_set) && !(lnk.arr in arrow_set)
                    continue
                end
                add_edge!(adj, src, lnk.dst, Float64(lnk.wgt))
            end
        end
    end

    return adj
end

# ──────────────────────────────────────────────────────────────────
# Sources and sinks
# ──────────────────────────────────────────────────────────────────

"""
    find_sources(adj::AdjacencyMatrix) -> Vector{NodePtr}

Find source nodes — nodes with no incoming links.
"""
function find_sources(adj::AdjacencyMatrix)
    sources = NodePtr[]
    for node in adj.nodes
        if !haskey(adj.incoming, node) || isempty(adj.incoming[node])
            push!(sources, node)
        end
    end
    return sort!(sources)
end

"""
    find_sinks(adj::AdjacencyMatrix) -> Vector{NodePtr}

Find sink nodes — nodes with no outgoing links.
"""
function find_sinks(adj::AdjacencyMatrix)
    sinks = NodePtr[]
    for node in adj.nodes
        if !haskey(adj.outgoing, node) || isempty(adj.outgoing[node])
            push!(sinks, node)
        end
    end
    return sort!(sinks)
end

# ──────────────────────────────────────────────────────────────────
# Cycle detection via DFS
# ──────────────────────────────────────────────────────────────────

"""
    detect_loops(adj::AdjacencyMatrix) -> Vector{Vector{NodePtr}}

Find all simple cycles in the directed graph using DFS.
Each cycle is returned as a vector of NodePtrs forming the loop.
"""
function detect_loops(adj::AdjacencyMatrix)
    cycles = Vector{Vector{NodePtr}}()
    visited = Set{NodePtr}()
    on_stack = Set{NodePtr}()
    # Map from node to its position in the current DFS path
    path = NodePtr[]
    seen_cycles = Set{Vector{NodePtr}}()

    sorted_nodes = sort!(collect(adj.nodes))

    function dfs(node::NodePtr)
        push!(visited, node)
        push!(on_stack, node)
        push!(path, node)

        if haskey(adj.outgoing, node)
            for (nbr, _) in adj.outgoing[node]
                if nbr in on_stack
                    # Found a cycle — extract it
                    idx = findfirst(==(nbr), path)
                    if !isnothing(idx)
                        cycle = path[idx:end]
                        canonical = _canonicalize_cycle(cycle)
                        if !(canonical in seen_cycles)
                            push!(seen_cycles, canonical)
                            push!(cycles, copy(cycle))
                        end
                    end
                elseif !(nbr in visited)
                    dfs(nbr)
                end
            end
        end

        pop!(path)
        delete!(on_stack, node)
    end

    for node in sorted_nodes
        if !(node in visited)
            dfs(node)
        end
    end

    return cycles
end

"""Canonicalize a cycle by rotating to start with the smallest node."""
function _canonicalize_cycle(cycle::Vector{NodePtr})
    isempty(cycle) && return cycle
    min_idx = argmin(cycle)
    n = length(cycle)
    return [cycle[mod1(min_idx + i - 1, n)] for i in 1:n]
end

# ──────────────────────────────────────────────────────────────────
# Eigenvector centrality
# ──────────────────────────────────────────────────────────────────

"""
    eigenvector_centrality(adj::AdjacencyMatrix; max_iter::Int=100, tol::Float64=1e-6) -> Dict{NodePtr, Float64}

Compute eigenvector centrality via power iteration on the adjacency matrix.
The result is normalized so the maximum value is 1.0.
"""
function eigenvector_centrality(adj::AdjacencyMatrix; max_iter::Int=100, tol::Float64=1e-6)
    nodes = sort!(collect(adj.nodes))
    n = length(nodes)
    n == 0 && return Dict{NodePtr, Float64}()

    node_idx = Dict(node => i for (i, node) in enumerate(nodes))

    # Initialize with uniform vector
    v = fill(1.0, n)

    for _ in 1:max_iter
        v_new = zeros(n)
        for (src, neighbours) in adj.outgoing
            si = node_idx[src]
            for (dst, w) in neighbours
                di = node_idx[dst]
                v_new[di] += w * v[si]
            end
        end

        # Normalize
        maxval = maximum(abs, v_new; init=0.0)
        if maxval > 0
            v_new ./= maxval
        else
            # Graph has no edges; return uniform
            fill!(v_new, 1.0 / n)
        end

        # Check convergence
        if maximum(abs, v_new .- v; init=0.0) < tol
            v = v_new
            break
        end
        v = v_new
    end

    return Dict(nodes[i] => v[i] for i in 1:n)
end

# ──────────────────────────────────────────────────────────────────
# Symmetrize
# ──────────────────────────────────────────────────────────────────

"""
    symmetrize(adj::AdjacencyMatrix) -> AdjacencyMatrix

Create a symmetric (undirected) version of the adjacency matrix.
For each directed edge (u,v) with weight w, the symmetric version
has both (u,v) and (v,u) with combined weight.
"""
function symmetrize(adj::AdjacencyMatrix)
    sym = AdjacencyMatrix()

    # Copy all nodes
    for node in adj.nodes
        push!(sym.nodes, node)
    end

    # Add edges in both directions
    for (src, neighbours) in adj.outgoing
        for (dst, w) in neighbours
            add_edge!(sym, src, dst, w)
            add_edge!(sym, dst, src, w)
        end
    end

    return sym
end

# ──────────────────────────────────────────────────────────────────
# Graph summary
# ──────────────────────────────────────────────────────────────────

"""
    graph_summary(adj::AdjacencyMatrix) -> String

Generate a text summary of graph properties: node count, link count,
sources, sinks, and top eigenvector centrality nodes.
"""
function graph_summary(adj::AdjacencyMatrix)
    io = IOBuffer()

    n_nodes = length(adj.nodes)
    n_links = sum(length(nbrs) for (_, nbrs) in adj.outgoing; init=0)
    sources = find_sources(adj)
    sinks = find_sinks(adj)
    evc = eigenvector_centrality(adj)

    println(io, "Graph Summary")
    println(io, "─────────────")
    println(io, "  Nodes:   $n_nodes")
    println(io, "  Links:   $n_links (directed)")
    println(io, "  Sources: $(length(sources))")
    println(io, "  Sinks:   $(length(sinks))")

    if !isempty(evc)
        sorted_evc = sort(collect(evc); by=last, rev=true)
        top_n = min(5, length(sorted_evc))
        println(io, "  Top centrality:")
        for i in 1:top_n
            node, val = sorted_evc[i]
            @printf(io, "    %s  %.4f\n", node, val)
        end
    end

    return String(take!(io))
end

# ──────────────────────────────────────────────────────────────────
# Betweenness centrality (adjacency-based, Brandes algorithm)
# ──────────────────────────────────────────────────────────────────

"""
    betweenness_centrality(adj::AdjacencyMatrix) -> Dict{NodePtr, Float64}

Compute betweenness centrality for each node using Brandes' algorithm.
Measures how often a node lies on shortest paths between other pairs.
"""
function betweenness_centrality(adj::AdjacencyMatrix)
    nodes = sort!(collect(adj.nodes))
    n = length(nodes)
    n == 0 && return Dict{NodePtr, Float64}()

    cb = Dict{NodePtr, Float64}(nd => 0.0 for nd in nodes)

    for s in nodes
        # BFS from s
        stack = NodePtr[]
        predecessors = Dict{NodePtr, Vector{NodePtr}}(nd => NodePtr[] for nd in nodes)
        sigma = Dict{NodePtr, Float64}(nd => 0.0 for nd in nodes)
        sigma[s] = 1.0
        dist = Dict{NodePtr, Int}(nd => -1 for nd in nodes)
        dist[s] = 0
        queue = NodePtr[s]

        while !isempty(queue)
            v = popfirst!(queue)
            push!(stack, v)
            if haskey(adj.outgoing, v)
                for (w, _) in adj.outgoing[v]
                    if dist[w] < 0
                        dist[w] = dist[v] + 1
                        push!(queue, w)
                    end
                    if dist[w] == dist[v] + 1
                        sigma[w] += sigma[v]
                        push!(predecessors[w], v)
                    end
                end
            end
        end

        delta = Dict{NodePtr, Float64}(nd => 0.0 for nd in nodes)
        while !isempty(stack)
            w = pop!(stack)
            for v in predecessors[w]
                delta[v] += (sigma[v] / sigma[w]) * (1.0 + delta[w])
            end
            if w != s
                cb[w] += delta[w]
            end
        end
    end

    return cb
end

# ──────────────────────────────────────────────────────────────────
# Build adjacency from MemoryStore
# ──────────────────────────────────────────────────────────────────

"""
    build_adjacency(store::MemoryStore; arrows::Vector{ArrowPtr}=ArrowPtr[], chapter::String="") -> AdjacencyMatrix

Build an adjacency matrix from a MemoryStore.
"""
function build_adjacency(store::MemoryStore; arrows::Vector{ArrowPtr}=ArrowPtr[], chapter::String="")
    adj = AdjacencyMatrix()
    arrow_set = isempty(arrows) ? nothing : Set(arrows)

    for (nptr, node) in store.nodes
        if !isempty(chapter) && !isempty(node.chap)
            !occursin(lowercase(chapter), lowercase(node.chap)) && continue
        end
        push!(adj.nodes, nptr)
        for stidx in 1:ST_TOP
            for lnk in node.incidence[stidx]
                if !isnothing(arrow_set) && !(lnk.arr in arrow_set)
                    continue
                end
                add_edge!(adj, nptr, lnk.dst, Float64(lnk.wgt))
            end
        end
    end

    return adj
end
