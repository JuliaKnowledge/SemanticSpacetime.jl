#=
Utility tools for Semantic Spacetime.

Provides chapter removal, notes browsing, and JSON import
functionality for the SST database.

Ported from SSTorytime/src/removeN4L.go, SSTorytime/src/notes.go,
and SSTorytime/src/demo_pocs/json.go.
=#

# ──────────────────────────────────────────────────────────────────
# Chapter removal (removeN4L)
# ──────────────────────────────────────────────────────────────────

"""
    remove_chapter!(sst::SSTConnection, chapter::String)

Delete all nodes and links belonging to a chapter from the database.
This is a destructive operation that cannot be undone.
"""
function remove_chapter!(sst::SSTConnection, chapter::String)
    isempty(chapter) && error("Chapter name must not be empty")
    ec = sql_escape(chapter)

    # Delete from PageMap first (references nodes)
    execute_sql(sst, "DELETE FROM PageMap WHERE Chap = '$(ec)'")

    # Delete nodes belonging to this chapter
    execute_sql(sst, "DELETE FROM Node WHERE Chap = '$(ec)'")

    @info "Deleted chapter" chapter=chapter
    nothing
end

# ──────────────────────────────────────────────────────────────────
# Notes browser
# ──────────────────────────────────────────────────────────────────

"""
    browse_notes(sst::SSTConnection, chapter::String;
                 page::Int=1, width::Int=SCREENWIDTH) -> String

Format notes from a chapter for terminal display. Retrieves the
page map for the given chapter and renders each note with its
context, chapter heading, and linked content.

Returns a formatted string suitable for terminal output.
"""
function browse_notes(sst::SSTConnection, chapter::String;
                      page::Int=1, width::Int=SCREENWIDTH)
    ec = sql_escape(chapter)
    search = "%" * ec * "%"

    sql = """SELECT Chap, Alias, Ctx, Line, Path FROM PageMap
             WHERE lower(Chap) LIKE lower('$(search)')
             ORDER BY Line ASC
             LIMIT $(CAUSAL_CONE_MAXLIMIT) OFFSET $((page - 1) * CAUSAL_CONE_MAXLIMIT)"""

    io = IOBuffer()
    last_chap = ""
    last_ctx = ""

    try
        result = execute_sql_strict(sst.conn, sql)
        for row in LibPQ.Columns(result)
            chap = something(row[1], "")
            ctx_ptr = something(row[3], 0)
            ctx_str = ctx_ptr > 0 ? get_context(ctx_ptr) : ""

            if chap != last_chap || ctx_str != last_ctx
                println(io)
                println(io, repeat('-', min(width - LEFTMARGIN - RIGHTMARGIN, 60)))
                println(io)
                println(io, "Title: ", chap)
                println(io, "Context: ", ctx_str)
                println(io, repeat('-', min(width - LEFTMARGIN - RIGHTMARGIN, 60)))
                println(io)
                last_chap = chap
                last_ctx = ctx_str
            end

            # Parse and render path links
            path_val = row[5]
            if !isnothing(path_val) && !ismissing(path_val)
                links = parse_link_array(string(path_val))
                for (j, lnk) in enumerate(links)
                    node = get_db_node_by_nodeptr(sst, lnk.dst)
                    if j == 1
                        print(io, "\n", node.s, " ")
                    else
                        arrow = get_arrow_by_ptr(lnk.arr)
                        print(io, "(", arrow.long, ") ", node.s, " ")
                    end
                end
            end
        end
    catch e
        @warn "Notes browse failed" chapter=chapter exception=e
    end

    println(io)
    return String(take!(io))
end

# ──────────────────────────────────────────────────────────────────
# JSON import
# ──────────────────────────────────────────────────────────────────

"""
    import_json!(sst::SSTConnection, json_str::String;
                 chapter::String="json_import") -> Vector{Node}

Import a JSON structure as SST nodes and links. Each key-value pair
in the JSON becomes a node (key) with a CONTAINS link to its value
node(s). Nested objects create nested containment structures.
Arrays create multiple CONTAINS links from the parent key.

Returns a vector of all created nodes.
"""
function import_json!(sst::SSTConnection, json_str::String;
                      chapter::String="json_import")
    data = JSON3.read(json_str)
    nodes = Node[]
    _import_json_value!(sst, data, chapter, nodes, "")
    return nodes
end

"""
    _import_json_value!(sst, value, chapter, nodes, parent_key)

Recursively import a JSON value into the SST graph.
"""
function _import_json_value!(sst::SSTConnection, value, chapter::String,
                             nodes::Vector{Node}, parent_key::String)
    if value isa AbstractDict
        for (k, v) in pairs(value)
            key_str = String(k)
            key_node = vertex!(sst, key_str, chapter)
            push!(nodes, key_node)
            _import_json_child!(sst, key_node, v, chapter, nodes)
        end
    elseif value isa AbstractVector
        for item in value
            _import_json_value!(sst, item, chapter, nodes, parent_key)
        end
    else
        val_str = string(value)
        if !isempty(val_str)
            val_node = vertex!(sst, val_str, chapter)
            push!(nodes, val_node)
        end
    end
end

"""
    _import_json_child!(sst, parent_node, value, chapter, nodes)

Import a child JSON value and link it to the parent node with
a CONTAINS relationship.
"""
function _import_json_child!(sst::SSTConnection, parent_node::Node, value,
                             chapter::String, nodes::Vector{Node})
    # Look up a suitable CONTAINS arrow
    contains_arrow = get_arrow_by_name("contains")
    if isnothing(contains_arrow)
        contains_arrow = get_arrow_by_name("has")
    end

    if value isa AbstractDict
        for (k, v) in pairs(value)
            key_str = String(k)
            key_node = vertex!(sst, key_str, chapter)
            push!(nodes, key_node)
            if !isnothing(contains_arrow)
                edge!(sst, parent_node, contains_arrow.short, key_node)
            end
            _import_json_child!(sst, key_node, v, chapter, nodes)
        end
    elseif value isa AbstractVector
        for item in value
            _import_json_child!(sst, parent_node, item, chapter, nodes)
        end
    else
        val_str = string(value)
        if !isempty(val_str)
            val_node = vertex!(sst, val_str, chapter)
            push!(nodes, val_node)
            if !isnothing(contains_arrow)
                edge!(sst, parent_node, contains_arrow.short, val_node)
            end
        end
    end
end
