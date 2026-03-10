# Graph Analysis

SemanticSpacetime.jl includes tools for structural analysis of knowledge graphs.

## Adjacency Matrix

Build a sparse adjacency matrix from a store or database connection:

```julia
adj = build_adjacency(sst)
# Or filter by arrow type and chapter:
adj = build_adjacency(sst; arrows=["then"], chapter="nursery rhymes")
```

The [`AdjacencyMatrix`](@ref) is a Dict-based sparse representation.

## Structural Properties

```julia
sources = find_sources(adj)             # nodes with no incoming links
sinks = find_sinks(adj)                 # nodes with no outgoing links
loops = detect_loops(adj)               # cycles via DFS
evc = eigenvector_centrality(adj)       # centrality scores
sym = symmetrize(adj)                   # make adjacency symmetric
println(graph_summary(adj))             # text summary
```

## Node Orbits

An orbit is the set of nodes reachable from a given node, organized by ST type and distance (ring number):

```julia
orbits = get_node_orbit(store, nptr)
satellites = assemble_satellites_by_sttype(store, nptr)
```

## Centrality

```julia
bc = betweenness_centrality(store, nodes)
sn = super_nodes(store, cone_paths)
```

## Graph Traversal

Advanced traversal operations for constrained searches and wavefront expansion:

```julia
# Wavefront expansion from a set of starting nodes
front = wave_front(store, start_set; max_depth=3)

# Constrained cone with arrow filtering
paths = get_constrained_cone_paths(store, nptr; arrows=["then"])

# Longest axial path through the graph
longest = get_longest_axial_path(store, nptr)
```

## DAG Validation

```julia
is_dag(adj)  # true if the graph has no cycles
```
