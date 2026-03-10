# API Reference

## Core Types and Constants

```@docs
STType
NodePtr
ClassedNodePtr
ArrowPtr
ContextPtr
Node
Link
ArrowEntry
ContextEntry
Etc
PageMap
Appointment
NodeDirectory
SSTConnection
NO_NODE_PTR
ST_ZERO
ST_TOP
CAUSAL_CONE_MAXLIMIT
N1GRAM
N2GRAM
N3GRAM
LT128
LT1024
GT1024
SCREENWIDTH
LEFTMARGIN
RIGHTMARGIN
CREDENTIALS_FILE
n_channel
```

## Arrow Directory

```@docs
insert_arrow!
insert_inverse_arrow!
get_arrow_by_name
get_arrow_by_ptr
get_stindex_by_name
get_sttype_from_arrows
print_stindex
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

## Database Connection

```@docs
open_sst
close_sst
configure!
```

## In-Memory Store

```@docs
AbstractSSTStore
MemoryStore
mem_vertex!
mem_edge!
mem_get_node
mem_get_nodes_by_name
mem_get_chapters
mem_search_text
node_count
link_count
```

## High-Level Graph API

```@docs
vertex!
edge!
hub_join!
graph_to_db!
```

## Graph Analysis

```@docs
AdjacencyMatrix
build_adjacency
find_sources
find_sinks
detect_loops
eigenvector_centrality
symmetrize
graph_summary
```

## Search

```@docs
SearchParameters
decode_search_field
search_nodes
search_text
get_db_node_ptr_matching_nccs
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
```

## Path Solving

```@docs
PathResult
find_paths
detect_path_loops
```

## Text to N4L

```@docs
TextRank
TextSignificance
score_sentence
extract_significant_sentences
text_to_n4l
```

## N4L Parser

```@docs
N4LState
N4LResult
N4LParseError
parse_n4l
parse_n4l_file
parse_config_file
find_config_dir
read_config_files
add_mandatory_arrows!
has_errors
has_warnings
ROLE_EVENT
ROLE_RELATION
ROLE_SECTION
ROLE_CONTEXT
ROLE_CONTEXT_ADD
ROLE_CONTEXT_SUBTRACT
ROLE_BLANK_LINE
ROLE_LINE_ALIAS
ROLE_LOOKUP
ROLE_COMPOSITION
ROLE_RESULT
```

## N4L Compiler

```@docs
N4LCompileResult
compile_n4l!
compile_n4l_file!
compile_n4l_string!
```

## N4L Validation & Summary

```@docs
N4LValidationResult
validate_n4l
validate_n4l_file
n4l_summary
```

## RDF Integration

```@docs
RDFTriple
SSTNamespace
PredicateMapping
sst_namespace
sst_to_rdf
rdf_to_sst!
export_turtle
import_turtle!
triples_to_turtle
parse_turtle
```

## HTTP Server

```@docs
serve
```

## Utility Tools

```@docs
remove_chapter!
browse_notes
import_json!
```
