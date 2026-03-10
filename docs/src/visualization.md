# Visualization

SemanticSpacetime.jl provides two visualization approaches: CairoMakie plots for interactive/raster output, and GraphViz DOT export for graph layout.

## CairoMakie Plots

All CairoMakie functions gracefully handle missing dependencies — they return `nothing` with a warning if CairoMakie is not installed.

### Causal Cone

```julia
cone = forward_cone(store, nptr)
fig = plot_cone(store, cone.paths; title="Forward Cone")
save_plot(fig, "cone.png")
```

### Node Orbit

```julia
orbits = get_node_orbit(store, nptr)
fig = plot_orbit(store, nptr, orbits; title="Node Orbit")
```

### Graph Summary

Bar chart of node count by text size class:

```julia
fig = plot_graph_summary(store)
```

### Adjacency Heatmap

```julia
adj_matrix = ...  # Float32 matrix
fig = plot_adjacency_heatmap(adj_matrix; labels=node_labels)
```

### Saving

All figures can be saved to PNG, SVG, or PDF:

```julia
save_plot(fig, "output.png")
save_plot(fig, "output.svg")
save_plot(fig, "output.pdf")
```

## GraphViz DOT Export

Export the graph as a [DOT](https://graphviz.org/doc/info/lang.html) string for use with GraphViz tools:

```julia
# Get DOT string
dot_str = to_dot(store; title="My Graph")

# Filter by chapter
dot_str = to_dot(store; chapter="nursery rhymes")

# Save directly to file
save_dot(store, "graph.dot")
```

Edges are colored by ST type. The DOT output can be rendered with `dot`, `neato`, or other GraphViz layout engines:

```bash
dot -Tpng graph.dot -o graph.png
dot -Tsvg graph.dot -o graph.svg
```

## ST Type Color Scheme

Both CairoMakie and DOT export use a consistent color scheme for ST types:

| ST Type | Value | Color |
|:--------|:------|:------|
| -EXPRESS | -3 | Purple |
| -CONTAINS | -2 | Blue |
| -LEADSTO | -1 | Cyan |
| NEAR | 0 | Green |
| +LEADSTO | +1 | Yellow |
| +CONTAINS | +2 | Orange |
| +EXPRESS | +3 | Red |

The color mapping is available as the `ST_COLORS` constant.
