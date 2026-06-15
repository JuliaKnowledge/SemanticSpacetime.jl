# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

SemanticSpacetime.jl is a Julia port of [SSTorytime](https://github.com/markburgess/SSTorytime)
(Mark Burgess's Go implementation), based on **Semantic Spacetime (SST)** — a theory of
process-oriented knowledge representation. It provides a typed, weighted, contextual graph API
with multiple storage backends. It is deliberately *not* an RDF or Topic Maps project.

Much of the code is a direct port of the Go original — when porting or debugging, the Go source
in a sibling `../SSTorytime` checkout is the reference (`src/types.jl` headers cite the Go file
they came from, e.g. `SSTorytime/pkg/SSTorytime/SSTorytime.go`). `test/test_cross_language.jl`
checks parity against it.

This package is part of the `juliaknowledge` monorepo; see `../CLAUDE.md` for ecosystem-wide
context.

## Build & Test Commands

```bash
# Full test suite (DB-backed tests skipped by default)
julia --project=. -e 'using Pkg; Pkg.test()'

# Include PostgreSQL-dependent tests (test/test_database.jl)
SST_TEST_DB=1 julia --project=. -e 'using Pkg; Pkg.test()'

# Run a single test file standalone (each is self-contained)
julia --project=. -e 'using Test, SemanticSpacetime; include("test/test_memory_store.jl")'

# Build docs
julia --project=docs -e 'include("docs/make.jl")'

# Benchmarks live in their own environment
julia --project=benchmarks benchmarks/run_benchmarks.jl
# Go/Python comparison benchmarks require the sibling ../SSTorytime checkout
```

`test/runtests.jl` includes ~42 test files under one top-level `@testset`. DB-dependent tests
are gated behind `if haskey(ENV, "SST_TEST_DB")`.

## Core Architecture

### The SST type system (`src/types.jl`)

All relationships are classified on a **signed integer axis** with four magnitudes, via the
`STType` enum: `NEAR=0`, `LEADSTO=±1`, `CONTAINS=±2`, `EXPRESS=±3`. The sign distinguishes
forward (+) from inverse (−). This 7-value spectrum (−3..+3) is mapped to 1-based array indices
(1..7) by `sttype_to_index` / `index_to_sttype`, using `ST_ZERO` (3) and `ST_TOP` (7). Node
incidence lists are sized by `ST_TOP` and indexed per channel (`ST_COLUMN_NAMES` are the DB
columns `Im3..Ie3`).

### Storage backends — the central abstraction

`AbstractSSTStore` (`src/memory_store.jl`) is the supertype for storage. Three concrete paths:

- **`MemoryStore`** (`src/memory_store.jl`) — pure in-memory, no DB. The default for tests and
  lightweight use. API: `mem_vertex!`, `mem_edge!`, `mem_get_node`, `mem_search_text`, etc.
- **`DBStore`** (`src/db_store.jl`) — portable SQL via DBInterface.jl. API: `db_vertex!`,
  `db_edge!`, `db_get_node`, `db_search_nodes`, `db_stats`, etc. Opened through extensions:
  `open_sqlite()` / `open_duckdb()`.
- **`SSTConnection`** (`src/database.jl`, `src/schema.jl`, `src/db_*.jl`) — the original
  PostgreSQL-oriented backend via LibPQ. API: `open_sst`, `configure!`, `vertex!`, `edge!`,
  `hub_join!`, `graph_to_db!`.

When adding storage features, support both in-memory and persistent modes (monorepo convention).

### Module-level registry state

Arrow and context directories are **module-level mutable state**, not per-store. `MemoryStore`
intentionally reuses the global arrow/context directories. Consequences:

- Call `add_mandatory_arrows!()` (from `src/n4l_parser.jl`) **before creating any links** — the
  README quick-start does this first.
- Arrows: `insert_arrow!`, `insert_inverse_arrow!`, `get_arrow_by_name`, `get_arrow_by_ptr`
  (`src/arrows.jl`).
- Contexts: `register_context!`, `try_context`, `get_context` (`src/context.jl`).
- Tests that mutate this global state should isolate it; `with_registry_state` / `with_config`
  do-block helpers (`src/macros.jl`) exist for scoping it.

### Node addressing

Nodes are addressed by `NodePtr` (a two-part pointer: text-size *class* + position within that
class). Size classes are n-gram/length buckets (`N1GRAM`, `N2GRAM`, `N3GRAM`, `LT128`, `LT1024`,
`GT1024`). The `NodeDirectory` (`src/node_directory.jl`) does n-gram bucketing for fast text
lookup. `NO_NODE_PTR` is the null sentinel.

### Subsystem map (`src/SemanticSpacetime.jl` is the include manifest)

- **N4L** (Notes For Learning markup): `n4l_parser.jl` → `n4l_compiler.jl` (parse result →
  store) → `n4l_standalone.jl` (validation/summary). `@n4l_str`, `@compile` macros. See the
  `vignettes/04-n4l-language/` vignette and the upstream N4L spec.
- **Search / traversal**: `search.jl`, `weighted_search.jl` (Dijkstra), `cone_search.jl`
  (forward/backward causal cones), `pathsolve.jl` (paths with loop correction),
  `graph_traversal.jl` (adjoints, wave fronts, constrained cones), `node_orbits.jl`
  (centrality, super-nodes), `inhibition.jl` (NOT-context search).
- **Analysis**: `graph_report.jl` (sources/sinks/cycles/eigenvector centrality),
  `matrix_ops.jl` (symbolic matrix algebra), `etc_validation.jl` (type inference/validation).
- **Text**: `text_analysis.jl` (n-gram fractionation, intentionality), `text2n4l.jl`
  (TextRank-style significant-sentence extraction), `context_intelligence.jl` (STM tracking).
- **I/O & web**: `rdf_integration.jl` (bidirectional SST↔Turtle — a hand-rolled minimal
  Turtle subset, `MemoryStore` only; not full RDF/N-Triples/JSON-LD), `http_server.jl` +
  `web_types.jl` (Genie server, JSON for the web UI in `src/public/`), `assets.jl` (note-keyed
  asset attachments), `visualization.jl` (CairoMakie plots + GraphViz DOT export),
  `db_sync.jl`, `tools.jl`.
- **`todo_features*.jl`** — three files of later-added features (focal view, unified/combinatorial
  search, SQL indexing, provenance, log-analysis pipeline, text-breakdown assistant). New
  feature work has tended to land here.

## Conventions

- **Extension pattern**: SQLite and DuckDB are weakdeps; their `open_sqlite`/`open_duckdb`
  methods live in `ext/SQLiteExt.jl` and `ext/DuckDBExt.jl` and only activate under
  `using SQLite` / `using DuckDB`. PostgreSQL/LibPQ, Genie, and CairoMakie are hard deps in the
  main install.
- **Everything is exported**: the single large `export` block at the bottom of
  `src/SemanticSpacetime.jl` is the public API surface. Add new public symbols there.
- **Docs**: Documenter.jl (`docs/make.jl`) plus 17 vignettes in `vignettes/`, each shipped as
  `.md`, `.html`, and `.pdf`. The `.html`/`.pdf` are generated artifacts — edit the `.md`.
- **Test fixtures**: N4L examples and SST config under `test/fixtures/`; resolve paths via
  `test/fixture_paths.jl`.
