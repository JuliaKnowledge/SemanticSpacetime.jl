#=
Database link operations for Semantic Spacetime.

Manages link creation, appending, and bulk upload to PostgreSQL.

Ported from SSTorytime/pkg/SSTorytime/SSTorytime.go.
=#

# ──────────────────────────────────────────────────────────────────
# Link operations
# ──────────────────────────────────────────────────────────────────

"""
    append_db_link_to_node!(sst::SSTConnection, nptr::NodePtr, lnk::Link, sttype::Int) -> Bool

Append a link to a node's incidence list in the database for the
given ST type. Idempotent — does nothing if the link already exists.
Returns true if the link was added.
"""
function append_db_link_to_node!(sst::SSTConnection, nptr::NodePtr, lnk::Link, sttype::Int)
    stindex = sttype_to_index(sttype)
    col = ST_COLUMN_NAMES[stindex]
    txtlink = "($(lnk.arr),$(lnk.wgt),$(lnk.ctx),$(format_nodeptr(lnk.dst))::NodePtr)::Link"
    np = format_nodeptr(nptr)

    sql = """UPDATE Node SET $(col) = array_append($(col), $(txtlink))
             WHERE NPtr = '$(np)'::NodePtr
             AND ($(col) IS NULL OR NOT $(txtlink) = ANY($(col)))"""

    execute_sql(sst, sql)
    return true
end

"""
    idemp_db_add_link!(sst::SSTConnection, from::Node, link::Link, to::Node)

Idempotently add a link between two nodes in the database.
Also adds the inverse link in the opposite ST direction.
"""
function idemp_db_add_link!(sst::SSTConnection, from::Node, link::Link, to::Node)
    arrow = get_arrow_by_ptr(link.arr)
    sttype = index_to_sttype(arrow.stindex)

    # Forward link
    append_db_link_to_node!(sst, from.nptr, link, sttype)

    # Inverse link
    inv_arr = get_inverse_arrow(link.arr)
    if !isnothing(inv_arr)
        inv_link = Link(inv_arr, link.wgt, link.ctx, from.nptr)
        append_db_link_to_node!(sst, to.nptr, inv_link, -sttype)
    end

    nothing
end

"""
    append_link_to_node!(from::NodePtr, link::Link, to::NodePtr)

Append a link to a node's in-memory incidence list (for the global node directory).
"""
function append_link_to_node!(from::NodePtr, link::Link, to::NodePtr)
    nd = _NODE_DIRECTORY[]
    node = get_memory_node_from_ptr(nd, from)
    node.s == "" && return nothing

    arrow = get_arrow_by_ptr(link.arr)
    stindex = arrow.stindex
    merge_link_list!(node.incidence[stindex], link)

    nothing
end

"""
    merge_link_list!(linklist::Vector{Link}, lnk::Link)

Add a link to a list if it doesn't already exist (idempotent merge).
"""
function merge_link_list!(linklist::Vector{Link}, lnk::Link)
    for existing in linklist
        if existing == lnk
            return nothing
        end
    end
    push!(linklist, lnk)
    nothing
end

# ──────────────────────────────────────────────────────────────────
# SQL command generation (no execution)
# ──────────────────────────────────────────────────────────────────

"""
    append_db_link_to_node_command(sst::SSTConnection, nptr::NodePtr, lnk::Link, sttype::Int) -> String

Generate the SQL command string to append a link to a node's
incidence list, without executing it. Useful for batching inside
transactions.
"""
function append_db_link_to_node_command(sst::SSTConnection, nptr::NodePtr, lnk::Link, sttype::Int)::String
    if sttype < -Int(EXPRESS) || sttype > Int(EXPRESS)
        error("ST type out of bounds: $sttype")
    end
    if nptr == lnk.dst
        return ""
    end
    stindex = sttype_to_index(sttype)
    col = ST_COLUMN_NAMES[stindex]
    txtlink = "($(lnk.arr),$(lnk.wgt),$(lnk.ctx),$(format_nodeptr(lnk.dst))::NodePtr)::Link"
    np = format_nodeptr(nptr)
    return "UPDATE Node SET $(col) = array_append($(col), $(txtlink)) WHERE NPtr = '$(np)'::NodePtr AND ($(col) IS NULL OR NOT $(txtlink) = ANY($(col)));\n"
end

"""
    append_db_link_array_to_node(sst::SSTConnection, nptr::NodePtr, array::String, sttype::Int) -> String

Generate the SQL command string to set a node's link array for a
given ST type, without executing it. Used during bulk upload.
"""
function append_db_link_array_to_node(sst::SSTConnection, nptr::NodePtr, array::String, sttype::Int)::String
    if sttype < -Int(EXPRESS) || sttype > Int(EXPRESS)
        error("ST type out of bounds: $sttype")
    end
    stindex = sttype_to_index(sttype)
    col = ST_COLUMN_NAMES[stindex]
    np = format_nodeptr(nptr)
    return "UPDATE Node SET $(col) = '$(array)' WHERE NPtr = '$(np)'::NodePtr;\n"
end
