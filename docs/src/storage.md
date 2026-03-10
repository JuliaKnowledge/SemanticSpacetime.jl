# Storage Backends

SemanticSpacetime.jl supports three categories of storage backend:

## MemoryStore

An in-memory graph store with no external dependencies. Data lives only in the Julia process and is lost when the session ends.

```julia
store = MemoryStore()
n1 = mem_vertex!(store, "concept A", "chapter1")
n2 = mem_vertex!(store, "concept B", "chapter1")
mem_edge!(store, n1, "leadsto", n2)
```

Key functions: [`mem_vertex!`](@ref), [`mem_edge!`](@ref), [`mem_get_node`](@ref), [`mem_search_text`](@ref), [`node_count`](@ref), [`link_count`](@ref).

## DBStore (SQLite, DuckDB)

A portable SQL store that works with any [DBInterface.jl](https://github.com/JuliaDatabases/DBInterface.jl)-compatible database. SQLite and DuckDB are supported via package extensions — load the backend package to activate the extension.

```julia
using SemanticSpacetime, SQLite
store = open_sqlite("my_graph.db")

# Use the same API as MemoryStore
db_vertex!(store, "concept A", "chapter1")
```

Key functions: [`open_sqlite`](@ref), [`open_duckdb`](@ref), [`close_db`](@ref), [`db_vertex!`](@ref), [`db_edge!`](@ref), [`db_get_node`](@ref), [`db_search_nodes`](@ref).

### Schema

`DBStore` automatically creates the required tables on first use via `create_db_schema!`. The schema stores nodes, links, arrows, contexts, and page map events in normalized relational tables.

### Arrow and Context Persistence

Arrows and contexts can be uploaded to the database for persistence and shared across sessions:

```julia
db_upload_arrows!(store)    # save current arrow directory
db_load_arrows!(store)      # restore from database
db_upload_contexts!(store)  # save context directory
db_load_contexts!(store)    # restore from database
```

## SSTConnection (PostgreSQL)

The original PostgreSQL backend using LibPQ.jl. This is suitable for large-scale, multi-user deployments. It uses PostgreSQL-specific features including array columns and full-text search via `tsvector`.

```julia
sst = open_sst(; host="localhost", port=5432)
configure!(sst)  # create schema and load arrows/contexts
```

Key functions: [`open_sst`](@ref), [`close_sst`](@ref), [`configure!`](@ref), [`vertex!`](@ref), [`edge!`](@ref), [`graph_to_db!`](@ref).

## Choosing a Backend

| Backend | Best for | Persistence | Dependencies |
|:--------|:---------|:------------|:-------------|
| `MemoryStore` | Testing, scripting, small graphs | None (in-process) | None |
| `DBStore` + SQLite | Single-user, file-based, portable | File | SQLite.jl |
| `DBStore` + DuckDB | Analytics, columnar workloads | File | DuckDB.jl |
| `SSTConnection` | Multi-user, large-scale | Server | LibPQ.jl + PostgreSQL |
