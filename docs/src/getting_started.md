# Getting Started

## In-Memory Store

The simplest way to use SemanticSpacetime.jl requires no database at all. `MemoryStore` is ideal for experimentation, testing, and lightweight applications.

```julia
using SemanticSpacetime

# Register built-in arrow types
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

## Database-Backed Store

For persistent storage, load a database extension. The `DBStore` uses DBInterface.jl so the same API works across backends.

### SQLite

```julia
using SemanticSpacetime, SQLite

# In-memory SQLite store
store = open_sqlite()

# File-backed SQLite store
store = open_sqlite("knowledge.db")
```

### DuckDB

```julia
using SemanticSpacetime, DuckDB

store = open_duckdb()               # in-memory
store = open_duckdb("knowledge.db") # file-backed
```

### PostgreSQL

For large-scale deployments, the original PostgreSQL backend is available:

```julia
using SemanticSpacetime

sst = open_sst()  # connects via CREDENTIALS_FILE or defaults

# Create nodes and links
n1 = vertex!(sst, "Mary had a little lamb", "nursery rhymes")
n2 = vertex!(sst, "Its fleece was white as snow", "nursery rhymes")
edge!(sst, n1, "then", n2, String[], 1.0f0)

close_sst(sst)
```

## Arrow Types

Arrows are named, typed relationships. They must be registered before use. The SST system provides mandatory arrows via [`add_mandatory_arrows!`](@ref), and you can register custom ones:

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
