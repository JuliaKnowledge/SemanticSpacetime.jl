# SemanticSpacetime.jl

A Julia port of the [SSTorytime](https://github.com/markburgess/SSTorytime) knowledge graph system, based on Semantic Spacetime (SST) — a theory of process-oriented knowledge representation.

SemanticSpacetime.jl provides a typed, weighted graph database API backed by PostgreSQL for building, querying, and analysing knowledge maps.

## The SST Type System

Semantic Spacetime classifies all relationships along a signed integer axis with four fundamental types:

| STType     | Value | Description                                   |
|:-----------|:------|:----------------------------------------------|
| `NEAR`     | 0     | Proximity or similarity (spatial neighbourhood) |
| `LEADSTO`  | ±1    | Causal or temporal ordering (process flow)     |
| `CONTAINS` | ±2    | Containment or membership (part-of hierarchy)  |
| `EXPRESS`  | ±3    | Expressive properties or attributes            |

The sign distinguishes forward (+) from inverse (−) relationships. Every link in the graph is classified into one of these types, enabling principled graph analysis.

## Package Features

- **Core SST type system** — `NEAR`, `LEADSTO`, `CONTAINS`, `EXPRESS` with signed axes
- **Arrow directory** — Named, typed relationships between nodes
- **Context registration** — Scoped context labels for nodes and links
- **In-memory node directory** — N-gram bucketed lookup for fast retrieval
- **PostgreSQL backend** — Full database support via LibPQ.jl
- **In-memory store** — `MemoryStore` for testing and embedded use (no database required)
- **High-level API** — Simple `vertex!` / `edge!` / `hub_join!` interface
- **Graph analysis** — Sources, sinks, cycles, eigenvector centrality
- **Causal cone search** — Forward and backward traversal with NCCS filtering
- **Path solving** — Bidirectional path finding with loop correction detection
- **N4L parser** — Notes for Learning markup language compiler
- **Text to N4L** — Automatic extraction of significant sentences
- **Weighted search** — Dijkstra shortest path and BFS with weight filtering
- **ETC validation** — Event/Thing/Concept type inference and consistency checks
- **Inhibition contexts** — Include/exclude filtering for search results

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/JuliaKnowledge/SemanticSpacetime.jl")
```
