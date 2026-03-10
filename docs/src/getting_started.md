# Getting Started

## Quick Start with PostgreSQL

```julia
using SemanticSpacetime

# Open a connection to the SST database
sst = open_sst()

# Create nodes (vertices)
n1 = vertex!(sst, "Mary had a little lamb", "nursery rhymes")
n2 = vertex!(sst, "Its fleece was white as snow", "nursery rhymes")

# Create a directed link (edge) between nodes
edge!(sst, n1, "then", n2, String[], 1.0f0)

# Close the connection
close_sst(sst)
```

## In-Memory Usage (No Database)

For testing or lightweight use, `MemoryStore` provides the same graph operations without requiring PostgreSQL:

```julia
using SemanticSpacetime

# Register some arrows first
add_mandatory_arrows!()

# Create an in-memory store
store = MemoryStore()

# Create nodes
n1 = mem_vertex!(store, "hello", "greetings")
n2 = mem_vertex!(store, "world", "greetings")

# Create edges (arrows must be registered)
mem_edge!(store, n1, "then", n2)

# Query
println(node_count(store))   # 2
println(link_count(store))   # 2 (forward + inverse)

# Search
results = mem_search_text(store, "hello")
```

## Arrow Types

Arrows are named, typed relationships. They must be registered before use. The SST system provides mandatory arrows via `add_mandatory_arrows!()`, and you can register custom ones:

```julia
# Register a forward and inverse arrow pair
fwd = insert_arrow!("leadsto", "causes", "causes outcome", "+")
bwd = insert_arrow!("leadsto", "caused-by", "is caused by", "-")
insert_inverse_arrow!(fwd, bwd)
```

## Contexts

Contexts scope nodes and links. They are sorted, comma-joined string labels:

```julia
ctx_ptr = register_context!(["biology", "genetics"])
ctx_str = get_context(ctx_ptr)  # "biology,genetics"
```

## Graph Analysis

```julia
# Build an adjacency matrix from the database
adj = build_adjacency(sst)

# Find structural properties
sources = find_sources(adj)
sinks = find_sinks(adj)
loops = detect_loops(adj)
evc = eigenvector_centrality(adj)

# Get a text summary
println(graph_summary(adj))
```

## Text Size Classes

Nodes are bucketed by text length for efficient lookup:

| Constant | Value | Description |
|:---------|:------|:------------|
| `N1GRAM` | 1 | Single word |
| `N2GRAM` | 2 | Two words |
| `N3GRAM` | 3 | Three words |
| `LT128`  | 4 | < 128 characters |
| `LT1024` | 5 | < 1024 characters |
| `GT1024` | 6 | ≥ 1024 characters |

Use [`n_channel`](@ref) to determine the class for a given string.
