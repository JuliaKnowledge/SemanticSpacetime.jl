# Utilities API

## Tools

```@docs
remove_chapter!
browse_notes
import_json!
```

## Session Tracking

```@docs
reset_session_tracking!
update_last_saw_section!
update_last_saw_nptr!
get_last_saw_section
get_last_saw_nptr
get_newly_seen_nptrs
```

## Display

```@docs
show_text
indent
print_node_orbit
print_link_orbit
print_link_path
show_context
print_sta_index
show_time
```

## Built-in Functions

```@docs
expand_dynamic_functions
evaluate_in_built
do_in_built_function
in_built_time_until
in_built_time_since
```

## Extended Queries

```@docs
get_arrows_matching_name
get_arrows_by_sttype
get_arrow_with_name
next_link_arrow
inc_constraint_cone_links
get_singleton_by_sttype
get_sequence_containers
already_seen
```

## Convenience Functions

```@docs
connect!
links
neighbors
nodes
eachnode
eachlink
find_nodes
map_nodes
with_store
with_config
```

## SQL Index

```@docs
SQLIndexConfig
index_sql_database!
```

## ETC Validation Integration

```@docs
validate_compiled_graph!
```
