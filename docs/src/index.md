# SemanticSpacetime.jl

A Julia implementation of the [SSTorytime](https://github.com/markburgess/SSTorytime) knowledge graph system, based on Semantic Spacetime (SST) — a theory of process-oriented knowledge representation by Mark Burgess.

SemanticSpacetime.jl provides a typed, weighted graph API with multiple storage backends — an in-memory store for lightweight use, and a portable SQL store via [DBInterface.jl](https://github.com/JuliaDatabases/DBInterface.jl) supporting SQLite, DuckDB, PostgreSQL, and other compatible databases.

**SemanticSpacetime.jl is an independent knowledge graph based on Semantic Spacetime. It is not an RDF or Topic Maps project. It aims to be both easier to use and more powerful than RDF for representing process knowledge.**

## The SST Type System

Semantic Spacetime classifies all relationships along a signed integer axis with four fundamental types:

| STType     | Value | Description                                   |
|:-----------|:------|:----------------------------------------------|
| `NEAR`     | 0     | Proximity or similarity (spatial neighbourhood) |
| `LEADSTO`  | ±1    | Causal or temporal ordering (process flow)     |
| `CONTAINS` | ±2    | Containment or membership (part-of hierarchy)  |
| `EXPRESS`  | ±3    | Expressive properties or attributes            |

The sign distinguishes forward (+) from inverse (−) relationships. Every link in the graph is classified into one of these types, enabling principled graph analysis based on the physics of spacetime processes rather than ad hoc ontologies.

## Package Features

- **Core SST type system** — `NEAR`, `LEADSTO`, `CONTAINS`, `EXPRESS` with signed axes
- **Multiple storage backends** — In-memory, SQLite, DuckDB, PostgreSQL
- **Arrow directory** — Named, typed relationships between nodes
- **Context registration** — Scoped context labels for nodes and links
- **In-memory node directory** — N-gram bucketed lookup for fast retrieval
- **High-level API** — Simple `vertex!` / `edge!` / `hub_join!` interface
- **N4L parser and compiler** — Notes for Learning markup language
- **Search and discovery** — Text search, cone search, weighted Dijkstra paths
- **Path solving** — Bidirectional path finding with loop correction detection
- **Graph analysis** — Sources, sinks, cycles, eigenvector centrality
- **RDF integration** — Bidirectional SST ↔ RDF/Turtle conversion
- **Visualization** — CairoMakie plots and GraphViz DOT export
- **HTTP server** — JSON API via Genie.jl with 18+ endpoints
- **Text analysis** — N-gram fractionation, significance scoring, text-to-N4L

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/JuliaKnowledge/SemanticSpacetime.jl")
```

## Quick Start

```julia
using SemanticSpacetime

# Create an in-memory store (no database required)
store = MemoryStore()

# Create nodes and a link
n1 = mem_vertex!(store, "Mary had a little lamb", "nursery rhymes")
n2 = mem_vertex!(store, "Its fleece was white as snow", "nursery rhymes")
mem_edge!(store, n1, "then", n2)
```

## Contents

```@contents
Pages = [
    "getting_started.md",
    "storage.md",
    "n4l.md",
    "search.md",
    "graph_analysis.md",
    "visualization.md",
    "api/types.md",
    "api/stores.md",
    "api/arrows_contexts.md",
    "api/graph.md",
    "api/search.md",
    "api/n4l.md",
    "api/rdf.md",
    "api/text.md",
    "api/visualization.md",
    "api/server.md",
    "api/utilities.md",
]
```
