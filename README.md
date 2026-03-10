# SemanticSpacetime.jl

[![Build Status](https://github.com/JuliaKnowledge/SemanticSpacetime.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/JuliaKnowledge/SemanticSpacetime.jl/actions/workflows/CI.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A Julia port of the [SSTorytime](https://github.com/markburgess/SSTorytime) knowledge graph system, based on Semantic Spacetime (SST) — a theory of process-oriented knowledge representation. SemanticSpacetime.jl provides a typed, weighted graph database API backed by PostgreSQL for building, querying, and analysing knowledge maps.

**SemanticSpacetime.jl is an independent knowledge graph based on Semantic Spacetime. It is not an RDF or Topic Maps project. It aims to be both easier to use and more powerful than RDF for representing process knowledge.**

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/JuliaKnowledge/SemanticSpacetime.jl")
```

Or from the Pkg REPL:

```
pkg> add https://github.com/JuliaKnowledge/SemanticSpacetime.jl
```

## Quick Start

```julia
using SemanticSpacetime

# Open a connection to the SST database (PostgreSQL)
sst = open_sst()

# Create nodes (vertices)
n1 = vertex!(sst, "Mary had a little lamb", "nursery rhymes")
n2 = vertex!(sst, "Its fleece was white as snow", "nursery rhymes")

# Create a directed link (edge) between nodes
edge!(sst, n1, "then", n2, String[], 1.0f0)

# Close the connection
close_sst(sst)
```

## Features

| Feature | Status | Module |
|---------|--------|--------|
| Core SST type system (NEAR/LEADSTO/CONTAINS/EXPRESS) | ✅ | `types.jl` |
| Arrow directory (named, typed relationships) | ✅ | `arrows.jl` |
| Context registration and normalization | ✅ | `context.jl` |
| In-memory node directory with n-gram bucketing | ✅ | `node_directory.jl` |
| PostgreSQL database backend (LibPQ) | ✅ | `database.jl`, `schema.jl` |
| Idempotent node and link operations | ✅ | `db_nodes.jl`, `db_links.jl` |
| High-level Vertex/Edge/Hub API | ✅ | `api.jl` |
| Database queries (nodes, chapters, contexts) | ✅ | `db_queries.jl` |
| Graph analysis (sources, sinks, cycles, centrality) | ✅ | `graph_report.jl` |
| N4L compiler (Notes For Learning) | 🔲 Planned | — |
| Search and path solving | 🔲 Planned | — |
| Web interface / HTTP server | 🔲 Planned | — |
| Visualization (GraphViz DOT export) | 🔲 Planned | — |

## The SST Type System

Semantic Spacetime classifies all relationships along a signed integer axis with four fundamental types:

| STType | Value | Description |
|--------|-------|-------------|
| `NEAR` | 0 | Proximity or similarity (spatial neighbourhood) |
| `LEADSTO` | ±1 | Causal or temporal ordering (process flow) |
| `CONTAINS` | ±2 | Containment or membership (part-of hierarchy) |
| `EXPRESS` | ±3 | Expressive properties or attributes |

The sign distinguishes forward (+) from inverse (−) relationships. Every link in the graph is classified into one of these types, enabling principled graph analysis based on the physics of spacetime processes rather than ad hoc ontologies.

## N4L — Notes For Learning

N4L is a lightweight markup language for entering knowledge as semi-structured notes. It is designed to make data entry as painless as possible — you write natural notes and N4L compiles them into a typed knowledge graph. N4L support for SemanticSpacetime.jl is planned for a future release. See the [SSTorytime N4L documentation](https://github.com/markburgess/SSTorytime/blob/main/docs/N4L.md) for the language specification.

## API Reference

### Core Types

- `STType` — Enum: `NEAR`, `LEADSTO`, `CONTAINS`, `EXPRESS`
- `NodePtr(class, cptr)` — Two-part pointer identifying a node by text-size class and position
- `ArrowPtr` — Integer index into the arrow directory
- `ContextPtr` — Integer index into the context directory
- `Node(text, chapter)` — A node with text content, chapter, and incidence lists
- `Link(arr, wgt, ctx, dst)` — A typed, weighted, contextual edge
- `ArrowEntry` — Arrow directory entry (stindex, long, short, ptr)
- `SSTConnection` — Database connection wrapper

### Database Lifecycle

- `open_sst(; load_arrows, host, port)` — Open a PostgreSQL connection
- `close_sst(sst)` — Close the connection
- `configure!(sst)` — Create schema and optionally load arrows/contexts

### High-Level Graph API

- `vertex!(sst, name, chapter)` — Create or retrieve a node
- `edge!(sst, from, arrow, to, context, weight)` — Create a directed link
- `hub_join!(sst, name, chapter, from_ptrs, arrow, context, weights)` — Multi-link through a hub
- `graph_to_db!(sst)` — Bulk upload in-memory graph to database

### Arrow Functions

- `insert_arrow!(stname, alias, name, pm)` — Register an arrow type
- `insert_inverse_arrow!(fwd, bwd)` — Register inverse arrow pair
- `get_arrow_by_name(name)` — Look up arrow by short or long name
- `get_arrow_by_ptr(ptr)` — Look up arrow by pointer

### Context Functions

- `register_context!(context)` — Register a context label vector
- `try_context(context)` — Look up or register a context
- `get_context(ptr)` — Retrieve context string by pointer

### Graph Analysis

- `AdjacencyMatrix` — Sparse adjacency representation (Dict-based)
- `build_adjacency(sst; arrows, chapter)` — Build adjacency matrix from database
- `find_sources(adj)` — Find nodes with no incoming links
- `find_sinks(adj)` — Find nodes with no outgoing links
- `detect_loops(adj)` — Find cycles using DFS
- `eigenvector_centrality(adj; max_iter, tol)` — Compute eigenvector centrality
- `symmetrize(adj)` — Make adjacency symmetric
- `graph_summary(adj)` — Text summary of graph properties

## Dependencies

- [LibPQ.jl](https://github.com/iamed2/LibPQ.jl) — PostgreSQL connectivity
- [JSON3.jl](https://github.com/quinnj/JSON3.jl) — JSON serialization
- [LinearAlgebra](https://docs.julialang.org/en/v1/stdlib/LinearAlgebra/) — Matrix operations (stdlib)
- [BenchmarkTools.jl](https://github.com/JuliaCI/BenchmarkTools.jl) — Performance benchmarking

## Related Projects

- [SSTorytime](https://github.com/markburgess/SSTorytime) — The original Go implementation by Mark Burgess
- [Smart Spacetime](https://www.amazon.com/dp/1797773704) — Conceptual background book by Mark Burgess

## Contributing

Contributions are welcome! Please open an [issue](https://github.com/JuliaKnowledge/SemanticSpacetime.jl/issues) or submit a [pull request](https://github.com/JuliaKnowledge/SemanticSpacetime.jl/pulls) on GitHub.

## License

[MIT](LICENSE)

## Author

Simon Frost ([@sdwfrost](https://github.com/sdwfrost))
