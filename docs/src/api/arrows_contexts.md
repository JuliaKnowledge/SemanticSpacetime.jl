# Arrows and Contexts

## Arrow Directory

```@docs
insert_arrow!
insert_inverse_arrow!
get_arrow_by_name
get_arrow_by_ptr
get_stindex_by_name
get_sttype_from_arrows
print_stindex
add_mandatory_arrows!
```

## Arrow Closures

```@docs
ClosureRule
load_arrow_closures
apply_arrow_closures!
complete_inferences!
complete_closeness!
complete_sequences!
```

## Context Management

```@docs
register_context!
try_context
get_context
compile_context_string
normalize_context_string
```

## Node Directory

```@docs
new_node_directory
append_text_to_directory!
check_existing_or_alt_caps
get_node_txt_from_ptr
get_memory_node_from_ptr
```

## Appointed Nodes

```@docs
get_appointed_nodes_by_arrow
get_appointed_nodes_by_sttype
parse_appointed_node_cluster
```
