#=
Todo Features 2: Unified Search, Combinatorial Search, and SQL Database Indexing.

Implements three features from the project roadmap:
1. Unified in-memory search combining text, context, weight, and ST type filtering
2. Combinatorial multi-term AND/OR/product search patterns
3. SQL database indexing into SST graph via DBInterface.jl
=#

import DBInterface

# ──────────────────────────────────────────────────────────────────
# 1. Unified Search
# ──────────────────────────────────────────────────────────────────

"""
    UnifiedSearchParams

Parameters for a unified graph search combining text, context, weights, and structure.
"""
struct UnifiedSearchParams
    text::String
    chapters::Vector{String}
    contexts::Vector{String}
    exclude_contexts::Vector{String}
    min_weight::Float32
    sttype_filter::Union{Nothing, STType}
    max_results::Int
end

function UnifiedSearchParams(;
    text::String="",
    chapters::Vector{String}=String[],
    contexts::Vector{String}=String[],
    exclude_contexts::Vector{String}=String[],
    min_weight::Float32=0.0f0,
    sttype_filter::Union{Nothing, STType}=nothing,
    max_results::Int=100,
)
    UnifiedSearchParams(text, chapters, contexts, exclude_contexts,
                        min_weight, sttype_filter, max_results)
end

"""
    unified_search(store::MemoryStore, params::UnifiedSearchParams) -> Vector{Node}

Perform a unified search combining text matching, chapter/context filtering,
inhibition, and weight thresholds.
"""
function unified_search(store::MemoryStore, params::UnifiedSearchParams)
    results = Node[]

    q = lowercase(strip(params.text))

    for node in values(store.nodes)
        # Text filter
        if !isempty(q) && !occursin(q, lowercase(node.s))
            continue
        end

        # Chapter filter
        if !isempty(params.chapters) && !(node.chap in params.chapters)
            continue
        end

        # Exclude-context filter: skip nodes with links in excluded contexts
        if !isempty(params.exclude_contexts) && _has_excluded_context(node, params.exclude_contexts)
            continue
        end

        # Context inclusion filter: at least one link must match all required contexts
        if !isempty(params.contexts) && !_has_required_contexts(node, params.contexts)
            continue
        end

        # Weight filter: at least one incident link must meet min_weight
        if params.min_weight > 0.0f0 && !_has_min_weight_link(node, params.min_weight)
            continue
        end

        # ST type filter: at least one incident link must be of the required type
        if params.sttype_filter !== nothing && !_has_sttype_link(node, params.sttype_filter)
            continue
        end

        push!(results, node)
        length(results) >= params.max_results && break
    end

    return results
end

function _has_excluded_context(node::Node, exclude::Vector{String})
    for st_links in node.incidence
        for lnk in st_links
            lnk.ctx <= 0 && continue
            ctx_str = lowercase(get_context(lnk.ctx))
            for exc in exclude
                if occursin(lowercase(exc), ctx_str)
                    return true
                end
            end
        end
    end
    return false
end

function _has_required_contexts(node::Node, required::Vector{String})
    for st_links in node.incidence
        for lnk in st_links
            lnk.ctx <= 0 && continue
            ctx_str = lowercase(get_context(lnk.ctx))
            all_found = true
            for req in required
                if !occursin(lowercase(req), ctx_str)
                    all_found = false
                    break
                end
            end
            all_found && return true
        end
    end
    return false
end

function _has_min_weight_link(node::Node, min_weight::Float32)
    for st_links in node.incidence
        for lnk in st_links
            lnk.wgt >= min_weight && return true
        end
    end
    return false
end

function _has_sttype_link(node::Node, sttype::STType)
    fwd_idx = sttype_to_index(Int(sttype))
    bwd_idx = sttype_to_index(-Int(sttype))
    if 1 <= fwd_idx <= length(node.incidence) && !isempty(node.incidence[fwd_idx])
        return true
    end
    if sttype != NEAR && 1 <= bwd_idx <= length(node.incidence) && !isempty(node.incidence[bwd_idx])
        return true
    end
    return false
end

"""
    unified_search(store::MemoryStore, query::String; chapters=String[], max_results::Int=100) -> Vector{Node}

Convenience form: parse a natural language query like
`"fever NOT cold in:patients min_weight:0.5 st:leadsto"`.

Supported syntax:
- Plain text: substring match on `node.s`
- `NOT term`: exclude nodes whose name matches `term`
- `in:chapter`: restrict to chapter
- `st:leadsto` / `st:contains` / `st:express` / `st:near`: filter by ST type
- `w>0.5`: minimum weight on incident links
"""
function unified_search(store::MemoryStore, query::String;
                        chapters::Vector{String}=String[],
                        max_results::Int=100)
    parsed = _parse_unified_query(query)
    # Merge caller-supplied chapters with parsed ones
    all_chapters = isempty(parsed.chapters) ? chapters : vcat(parsed.chapters, chapters)
    params = UnifiedSearchParams(
        text=parsed.text,
        chapters=all_chapters,
        contexts=String[],
        exclude_contexts=parsed.exclude_terms,
        min_weight=parsed.min_weight,
        sttype_filter=parsed.sttype_filter,
        max_results=max_results,
    )

    results = unified_search(store, params)

    # Post-filter: remove nodes matching NOT terms by name
    if !isempty(parsed.exclude_terms)
        filter!(n -> !any(t -> occursin(lowercase(t), lowercase(n.s)), parsed.exclude_terms), results)
    end

    return results
end

struct _ParsedQuery
    text::String
    exclude_terms::Vector{String}
    chapters::Vector{String}
    sttype_filter::Union{Nothing, STType}
    min_weight::Float32
end

function _parse_unified_query(query::String)
    tokens = split(strip(query))
    text_parts = String[]
    exclude_terms = String[]
    chapters = String[]
    sttype_filter = nothing
    min_weight = 0.0f0

    i = 1
    while i <= length(tokens)
        tok = String(tokens[i])

        if uppercase(tok) == "NOT" && i < length(tokens)
            i += 1
            push!(exclude_terms, String(tokens[i]))
        elseif startswith(lowercase(tok), "in:")
            push!(chapters, tok[4:end])
        elseif startswith(lowercase(tok), "st:")
            stname = lowercase(tok[4:end])
            if stname == "leadsto"
                sttype_filter = LEADSTO
            elseif stname == "contains"
                sttype_filter = CONTAINS
            elseif stname == "express"
                sttype_filter = EXPRESS
            elseif stname == "near"
                sttype_filter = NEAR
            end
        elseif startswith(tok, "w>")
            try
                min_weight = Float32(parse(Float64, tok[3:end]))
            catch
                push!(text_parts, tok)
            end
        else
            push!(text_parts, tok)
        end
        i += 1
    end

    text = join(text_parts, " ")
    return _ParsedQuery(text, exclude_terms, chapters, sttype_filter, min_weight)
end

# ──────────────────────────────────────────────────────────────────
# 2. Combinatorial Search Patterns
# ──────────────────────────────────────────────────────────────────

"""
    combinatorial_search(store::MemoryStore, terms::Vector{String}; mode::Symbol=:and) -> Vector{Vector{Node}}

Search for multiple terms simultaneously.
- `:and` — return a single vector containing nodes matching ALL terms
- `:or`  — return a single vector containing nodes matching ANY term
- `:product` — return Cartesian product of matches for each term
"""
function combinatorial_search(store::MemoryStore, terms::Vector{String}; mode::Symbol=:and)
    isempty(terms) && return Vector{Node}[]

    per_term = [mem_search_text(store, t) for t in terms]

    if mode == :and
        if isempty(per_term)
            return Vector{Node}[]
        end
        # Intersection: nodes present in all per_term result sets
        common_nptrs = Set(n.nptr for n in per_term[1])
        for results in per_term[2:end]
            intersect!(common_nptrs, Set(n.nptr for n in results))
        end
        combined = filter(n -> n.nptr in common_nptrs, per_term[1])
        return [combined]

    elseif mode == :or
        seen = Set{NodePtr}()
        combined = Node[]
        for results in per_term
            for n in results
                if !(n.nptr in seen)
                    push!(seen, n.nptr)
                    push!(combined, n)
                end
            end
        end
        return [combined]

    elseif mode == :product
        # Return each term's results as a separate vector
        return per_term

    else
        error("Unknown combinatorial_search mode: $mode. Use :and, :or, or :product")
    end
end

"""
    cross_chapter_search(store::MemoryStore, query::String, chapters::Vector{String}) -> Dict{String, Vector{Node}}

Search for a query across multiple chapters, returning results grouped by chapter.
"""
function cross_chapter_search(store::MemoryStore, query::String, chapters::Vector{String})
    result = Dict{String, Vector{Node}}()
    all_matches = mem_search_text(store, query)

    for chap in chapters
        result[chap] = filter(n -> n.chap == chap, all_matches)
    end

    return result
end

# ──────────────────────────────────────────────────────────────────
# 3. SQL Database Indexing
# ──────────────────────────────────────────────────────────────────

"""
    SQLIndexConfig

Configuration for indexing a SQL database into SST.
"""
struct SQLIndexConfig
    tables::Vector{String}
    label_columns::Dict{String,String}
    skip_columns::Vector{String}
    chapter_prefix::String
    detect_foreign_keys::Bool
end

function SQLIndexConfig(;
    tables::Vector{String}=String[],
    label_columns::Dict{String,String}=Dict{String,String}(),
    skip_columns::Vector{String}=String[],
    chapter_prefix::String="db",
    detect_foreign_keys::Bool=true,
)
    SQLIndexConfig(tables, label_columns, skip_columns, chapter_prefix, detect_foreign_keys)
end

"""
    index_sql_database!(store::MemoryStore, db;
                        config::SQLIndexConfig=SQLIndexConfig()) -> Dict{String,Int}

Index a SQL database into the SST graph.
- Each table becomes a chapter (prefixed with `config.chapter_prefix`)
- Each row becomes a node (labeled by primary key or configured column)
- Foreign key columns create LEADSTO edges between nodes
- Other columns become EXPRESS (note) annotations

Returns a Dict mapping table names to number of nodes created.
"""
function index_sql_database!(store::MemoryStore, db;
                             config::SQLIndexConfig=SQLIndexConfig())
    counts = Dict{String,Int}()

    tables = _get_tables(db, config)

    # Gather foreign key info per table
    fk_map = Dict{String, Vector{Tuple{String,String,String}}}()  # table => [(col, ref_table, ref_col)]
    if config.detect_foreign_keys
        for tbl in tables
            fk_map[tbl] = _get_foreign_keys(db, tbl)
        end
    end

    # Collect all row data upfront (avoids iterator consumption issues)
    table_data = Dict{String, Tuple{Vector{String}, Vector{Vector{Any}}}}()
    for tbl in tables
        table_data[tbl] = _collect_rows(db, "SELECT * FROM $(tbl)")
    end

    # First pass: create nodes for all rows
    node_map = Dict{String, Dict{String, Node}}()  # table => (row_label => Node)
    # Also build a column-value index for FK lookups: (table, col, val_str) => label
    col_val_index = Dict{Tuple{String,String,String}, String}()

    for tbl in tables
        chapter = config.chapter_prefix * "." * tbl
        label_col = get(config.label_columns, tbl, nothing)

        col_names, all_rows = table_data[tbl]
        isempty(col_names) && (counts[tbl] = 0; node_map[tbl] = Dict{String,Node}(); continue)

        # Find label column index
        label_idx = if label_col !== nothing
            findfirst(==(label_col), col_names)
        else
            findfirst(c -> !(c in config.skip_columns), col_names)
        end
        label_idx === nothing && (label_idx = 1)

        tbl_nodes = Dict{String, Node}()
        row_count = 0

        fk_cols = config.detect_foreign_keys ? Set(fk[1] for fk in get(fk_map, tbl, Tuple{String,String,String}[])) : Set{String}()

        for row_values in all_rows
            label_val = string(row_values[label_idx])
            node = mem_vertex!(store, label_val, chapter)
            tbl_nodes[label_val] = node
            row_count += 1

            # Index all column values for FK reverse lookup
            for (j, cname) in enumerate(col_names)
                val = row_values[j]
                val === missing && continue
                col_val_index[(tbl, cname, string(val))] = label_val
            end

            # Create property annotations for non-label, non-skip, non-FK columns
            for (j, cname) in enumerate(col_names)
                j == label_idx && continue
                cname in config.skip_columns && continue
                cname in fk_cols && continue
                val = row_values[j]
                val === missing && continue

                prop_text = "$cname: $(string(val))"
                prop_node = mem_vertex!(store, prop_text, chapter)
                note_arrow = get_arrow_by_name("note")
                if note_arrow !== nothing
                    mem_edge!(store, node, "note", prop_node)
                end
            end
        end

        node_map[tbl] = tbl_nodes
        counts[tbl] = row_count
    end

    # Second pass: create FK edges
    if config.detect_foreign_keys
        for tbl in tables
            fks = get(fk_map, tbl, Tuple{String,String,String}[])
            isempty(fks) && continue

            label_col = get(config.label_columns, tbl, nothing)
            col_names, all_rows = table_data[tbl]
            isempty(col_names) && continue

            label_idx = if label_col !== nothing
                findfirst(==(label_col), col_names)
            else
                findfirst(c -> !(c in config.skip_columns), col_names)
            end
            label_idx === nothing && (label_idx = 1)

            for row_values in all_rows
                label_val = string(row_values[label_idx])
                src_node = get(get(node_map, tbl, Dict{String,Node}()), label_val, nothing)
                src_node === nothing && continue

                for (fk_col, ref_tbl, ref_col) in fks
                    fk_idx = findfirst(==(fk_col), col_names)
                    fk_idx === nothing && continue
                    fk_val = row_values[fk_idx]
                    fk_val === missing && continue

                    # Look up the referenced node via column-value index
                    ref_label = get(col_val_index, (ref_tbl, ref_col, string(fk_val)), nothing)
                    if ref_label !== nothing
                        ref_nodes = get(node_map, ref_tbl, Dict{String,Node}())
                        dst_node = get(ref_nodes, ref_label, nothing)
                        if dst_node !== nothing
                            then_arrow = get_arrow_by_name("then")
                            if then_arrow !== nothing
                                mem_edge!(store, src_node, "then", dst_node)
                            end
                        end
                    end
                end
            end
        end
    end

    return counts
end

# ──────────────────────────────────────────────────────────────────
# SQL introspection helpers (SQLite dialect)
# ──────────────────────────────────────────────────────────────────

function _get_tables(db, config::SQLIndexConfig)
    if !isempty(config.tables)
        return config.tables
    end
    result = DBInterface.execute(db, "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
    return [String(row[:name]) for row in result]
end

function _get_columns(db, table::String)
    result = DBInterface.execute(db, "PRAGMA table_info($(table))")
    return [(name=String(row[:name]), type=String(row[:type]), pk=row[:pk] != 0) for row in result]
end

function _get_foreign_keys(db, table::String)
    fks = Tuple{String,String,String}[]
    result = DBInterface.execute(db, "PRAGMA foreign_key_list($(table))")
    for row in result
        ref_table = String(row[:table])
        from_col = String(row[:from])
        to_col = String(row[:to])
        push!(fks, (from_col, ref_table, to_col))
    end
    return fks
end

"""Collect rows from a query result, returning (column_names, row_data)."""
function _collect_rows(db, query::String)
    result = DBInterface.execute(db, query)
    col_names = String[]
    rows = Vector{Any}[]
    for row in result
        if isempty(col_names)
            col_names = [String(k) for k in propertynames(row)]
        end
        push!(rows, [row[Symbol(c)] for c in col_names])
    end
    return (col_names, rows)
end
