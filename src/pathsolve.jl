#=
Path solving with loop corrections for Semantic Spacetime.

Finds all paths between two sets of nodes using bidirectional
wave-front expansion (forward from start, backward from end).
Detects "loop corrections" — paths that contain repeated nodes
(non-DAG paths in the quantum/Feynman analogy).

Ported from SSTorytime/src/pathsolve.go and
SSTorytime/pkg/SSTorytime/SSTorytime.go
(GetPathsAndSymmetries, WaveFrontsOverlap, IsDAG).
=#

# ──────────────────────────────────────────────────────────────────
# PathResult
# ──────────────────────────────────────────────────────────────────

"""
    PathResult

Result of a path-finding operation between two nodes.
`paths` contains DAG (loop-free) solutions.
`loops` contains non-DAG paths that revisit nodes (loop corrections).
"""
struct PathResult
    paths::Vector{Vector{NodePtr}}
    loops::Vector{Vector{NodePtr}}
end

PathResult() = PathResult(Vector{NodePtr}[], Vector{NodePtr}[])

# ──────────────────────────────────────────────────────────────────
# In-memory path finding
# ──────────────────────────────────────────────────────────────────

"""
    find_paths(store::MemoryStore, begin_node::NodePtr, end_node::NodePtr;
               chapter::String="", context::Vector{String}=String[],
               max_depth::Int=10) -> PathResult

Find all paths from `begin_node` to `end_node` in the in-memory
graph, up to `max_depth` hops.  Separates DAG paths from looped paths.
"""
function find_paths(store::MemoryStore, begin_node::NodePtr, end_node::NodePtr;
                    chapter::String="", context::Vector{String}=String[],
                    max_depth::Int=10)
    all_paths = Vector{NodePtr}[]
    _dfs_paths!(store, begin_node, end_node, max_depth,
                [begin_node], Set{NodePtr}([begin_node]), all_paths)

    dag_paths = Vector{NodePtr}[]
    loop_paths = Vector{NodePtr}[]

    for path in all_paths
        if _is_dag_path(path)
            push!(dag_paths, path)
        else
            push!(loop_paths, path)
        end
    end

    return PathResult(dag_paths, loop_paths)
end

"""
Depth-first search collecting all paths from `current` to `target`.
"""
function _dfs_paths!(store::MemoryStore, current::NodePtr, target::NodePtr,
                     remaining::Int, prefix::Vector{NodePtr},
                     visited::Set{NodePtr},
                     results::Vector{Vector{NodePtr}})
    remaining <= 0 && return nothing

    node = mem_get_node(store, current)
    isnothing(node) && return nothing

    # Explore forward (positive-ST) links
    for stidx in 1:ST_TOP
        st = index_to_sttype(stidx)
        st <= 0 && continue   # forward only

        for lnk in node.incidence[stidx]
            new_prefix = vcat(prefix, [lnk.dst])

            if lnk.dst == target
                push!(results, new_prefix)
                continue
            end

            lnk.dst in visited && continue

            push!(visited, lnk.dst)
            _dfs_paths!(store, lnk.dst, target, remaining - 1,
                        new_prefix, visited, results)
            delete!(visited, lnk.dst)
        end
    end

    nothing
end

# ──────────────────────────────────────────────────────────────────
# Database-backed path finding
# ──────────────────────────────────────────────────────────────────

"""
    find_paths(sst::SSTConnection, begin_node::NodePtr, end_node::NodePtr;
               chapter::String="", context::Vector{String}=String[],
               max_depth::Int=10) -> PathResult

Find paths between two nodes using bidirectional cone expansion
via the database.  Mirrors the Go `GetPathsAndSymmetries`.
"""
function find_paths(sst::SSTConnection, begin_node::NodePtr, end_node::NodePtr;
                    chapter::String="", context::Vector{String}=String[],
                    max_depth::Int=10)
    start_set = [begin_node]
    end_set = [end_node]

    # Use forward cone from start, backward cone from end
    fwd_cone = forward_cone(sst, begin_node; depth=max_depth)
    bwd_cone = backward_cone(sst, end_node; depth=max_depth)

    # Find overlapping wavefronts and splice paths
    dag_paths = Vector{NodePtr}[]
    loop_paths = Vector{NodePtr}[]

    fwd_tips = Dict{NodePtr, Vector{Vector{Link}}}()
    for path in fwd_cone.paths
        tip = last(path).dst
        paths_at = get!(fwd_tips, tip, Vector{Link}[])
        push!(paths_at, path)
    end

    for bpath in bwd_cone.paths
        btip = last(bpath).dst
        if haskey(fwd_tips, btip)
            for fpath in fwd_tips[btip]
                # Splice: forward path + reversed backward path
                full = _splice_paths_as_nodes(fpath, bpath, begin_node)
                if _is_dag_path(full)
                    push!(dag_paths, full)
                else
                    push!(loop_paths, full)
                end
            end
        end
    end

    return PathResult(dag_paths, loop_paths)
end

# ──────────────────────────────────────────────────────────────────
# Loop detection
# ──────────────────────────────────────────────────────────────────

"""
    detect_path_loops(paths::Vector{Vector{NodePtr}}) -> Vector{Vector{NodePtr}}

Extract loops (repeated node subsequences) from a set of paths.
Returns the subsequence of each path that forms a cycle.
"""
function detect_path_loops(paths::Vector{Vector{NodePtr}})
    loops = Vector{NodePtr}[]

    for path in paths
        seen = Dict{NodePtr, Int}()   # node → first index
        for (i, nptr) in enumerate(path)
            if haskey(seen, nptr)
                # Extract the loop: from first occurrence to current
                loop = path[seen[nptr]:i]
                push!(loops, loop)
            else
                seen[nptr] = i
            end
        end
    end

    return loops
end

# ──────────────────────────────────────────────────────────────────
# Internal helpers
# ──────────────────────────────────────────────────────────────────

"""Check if a node-path is a DAG (no repeated nodes)."""
function _is_dag_path(path::Vector{NodePtr})
    seen = Set{NodePtr}()
    for nptr in path
        nptr in seen && return false
        push!(seen, nptr)
    end
    return true
end

"""
Splice a forward link-path and a backward link-path into a single
node-path, starting from `root`.  The backward path is reversed
(adjoint) and its overlapping node is removed.
"""
function _splice_paths_as_nodes(fwd::Vector{Link}, bwd::Vector{Link}, root::NodePtr)
    nodes = NodePtr[root]
    for lnk in fwd
        push!(nodes, lnk.dst)
    end
    # Reverse the backward path (skip the overlapping tip)
    for i in length(bwd)-1:-1:1
        push!(nodes, bwd[i].dst)
    end
    return nodes
end
