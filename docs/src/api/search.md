# Search API

## Search

```@docs
SearchParameters
decode_search_field
search_nodes
search_text
get_db_node_ptr_matching_nccs
decode_search_command
fill_in_parameters
```

## Weighted Search

```@docs
WeightedPath
weighted_search
dijkstra_path
rank_by_weight
```

## ETC Validation

```@docs
infer_etc
validate_etc
collapse_psi
show_psi
validate_graph_types
```

## Inhibition Context

```@docs
InhibitionContext
parse_inhibition_context
matches_inhibition
search_with_inhibition
```

## Causal Cone Search

```@docs
ConeResult
forward_cone
backward_cone
entire_nc_cone
select_stories_by_arrow
get_fwd_paths_as_links
get_entire_cone_paths_as_links
```

## Path Solving

```@docs
PathResult
find_paths
detect_path_loops
```

## Unified Search

```@docs
UnifiedSearchParams
unified_search
combinatorial_search
cross_chapter_search
```

## Focal View

```@docs
FocalView
focal_view
drill_down
drill_up
tree_view
hierarchy_roots
```
