# Search and Path Solving

SemanticSpacetime.jl provides several search and traversal strategies.

## Text Search

### In-Memory

```julia
results = mem_search_text(store, "lamb")
```

### Database

```julia
ptrs = search_nodes(sst, "lamb", "nursery rhymes")
results = search_text(sst, "lamb")
```

The database search uses PostgreSQL `tsvector` full-text indexing for fast lookups.

## Causal Cone Search

A causal cone is the set of all nodes reachable by following links forward (future cone) or backward (past cone) from a starting node.

```julia
# Forward cone — what follows from this node?
cone = forward_cone(store, start_nptr; max_depth=5)

# Backward cone — what leads to this node?
cone = backward_cone(store, start_nptr; max_depth=5)
```

The result is a [`ConeResult`](@ref) containing paths and supernodes (nodes appearing in multiple paths).

## Path Solving

Find paths between two nodes:

```julia
result = find_paths(store, from_nptr, to_nptr; max_depth=10)
println(result.dag_paths)     # acyclic paths
println(result.loop_paths)    # paths containing cycles
```

Detect loops within paths:

```julia
loops = detect_path_loops(paths)
```

## Weighted Search

BFS with weight filtering and Dijkstra's shortest path:

```julia
# BFS with minimum weight threshold
paths = weighted_search(store, start_nptr; max_depth=5, min_weight=0.5)

# Shortest weighted path (weight = inverse distance)
path = dijkstra_path(store, from_nptr, to_nptr)

# Rank paths by total weight
ranked = rank_by_weight(paths; descending=true)
```

## Story Selection

Follow sequences (stories) through the graph by arrow type:

```julia
stories = select_stories_by_arrow(store, start_nptr, arrow_ptr)
```

## Inhibition Context

Filter search results with include/exclude rules:

```julia
ctx = parse_inhibition_context("+biology,-chemistry")
filtered = search_with_inhibition(store, query, ctx)
```

## Unified Search

A single entry point that dispatches to the appropriate search strategy:

```julia
params = UnifiedSearchParams(query="lamb", chapter="nursery rhymes")
results = unified_search(store, params)
```
