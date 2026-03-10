# Storage API

## Abstract Interface

```@docs
AbstractSSTStore
```

## In-Memory Store

```@docs
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

## DBStore (SQLite / DuckDB)

```@docs
DBStore
open_sqlite
open_duckdb
close_db
db_vertex!
db_edge!
db_get_node
db_get_links
db_get_nodes_by_name
db_search_nodes
db_get_chapters
db_get_chapter_nodes
db_stats
db_upload_arrows!
db_load_arrows!
db_upload_contexts!
db_load_contexts!
```

## PostgreSQL Connection

```@docs
SSTConnection
open_sst
close_sst
configure!
```

## High-Level Graph API

```@docs
vertex!
edge!
hub_join!
graph_to_db!
```

## DB Sync

```@docs
download_arrows_from_db!
download_contexts_from_db!
synchronize_nptrs!
cache_node!
get_cached_node
reset_node_cache!
```
