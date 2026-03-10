# Graph Analysis API

## Adjacency Matrix

```@docs
AdjacencyMatrix
add_edge!
build_adjacency
find_sources
find_sinks
detect_loops
eigenvector_centrality
symmetrize
graph_summary
```

## Graph Traversal

```@docs
adjoint_arrows
adjoint_sttype
adjoint_link_path
wave_front
nodes_overlap
wave_fronts_overlap
left_join
right_complement_join
is_dag
together!
idemp_add_nodeptr!
in_node_set
get_constrained_cone_paths
get_constrained_fwd_links
get_paths_and_symmetries
get_longest_axial_path
truncate_paths_by_arrow
```

## Node Orbits and Centrality

```@docs
get_node_orbit
assemble_satellites_by_sttype
idemp_add_satellite!
tally_path
betweenness_centrality
super_nodes_by_conic_path
super_nodes
get_path_transverse_super_nodes
```

## Coordinates

```@docs
relative_orbit
set_orbit_coords
assign_cone_coordinates
assign_story_coordinates
assign_page_coordinates
assign_chapter_coordinates
assign_context_set_coordinates
assign_fragment_coordinates
make_coordinate_directory
```

## Matrix Operations

```@docs
symbol_matrix
symbolic_multiply
get_sparse_occupancy
symmetrize_matrix
transpose_matrix
make_init_vector
matrix_op_vector
compute_evc
find_gradient_field_top
get_hill_top
```

## PageMap Operations

```@docs
upload_page_map_event!
get_page_map
get_chapters_by_chap_context
split_chapters
```
