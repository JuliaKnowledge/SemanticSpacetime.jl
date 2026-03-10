#=
Appointed Nodes subsystem for Semantic Spacetime.

Finds nodes that are "appointed" — pointed to by the same type of arrow —
and groups them by arrow type or STType. Supports both in-memory
(MemoryStore) and database-backed (SSTConnection) stores.

Ported from SSTorytime/pkg/SSTorytime/SSTorytime.go
(GetAppointedNodesByArrow, GetAppointedNodesBySTType, ParseAppointedNodeCluster).
=#

# ──────────────────────────────────────────────────────────────────
# Memory-backed appointed node queries
# ──────────────────────────────────────────────────────────────────

"""
    get_appointed_nodes_by_arrow(store::MemoryStore, arrow::Int;
                                 context::Vector{String}=String[],
                                 chapter::AbstractString="any",
                                 size::Int=100) -> Dict{Int, Vector{Appointment}}

Get appointed nodes grouped by arrow type (memory-backed).
Finds nodes that have incoming links with the specified arrow,
groups them by arrow pointer, and filters by chapter and context.
"""
function get_appointed_nodes_by_arrow(store::MemoryStore, arrow::Int;
                                      context::Vector{String}=String[],
                                      chapter::AbstractString="any",
                                      size::Int=100)::Dict{Int, Vector{Appointment}}
    result = Dict{Int, Vector{Appointment}}()
    inv_arrow = get_inverse_arrow(arrow)

    for (nptr, node) in store.nodes
        # Filter by chapter
        if chapter != "any" && !isempty(chapter)
            !similar_string(node.chap, chapter) && continue
        end

        count = 0
        for stindex in 1:ST_TOP
            for link in node.incidence[stindex]
                target_arr = isnothing(inv_arrow) ? arrow : inv_arrow
                if link.arr == target_arr
                    # Context filter
                    if !isempty(context)
                        !match_contexts(context, link.ctx) && continue
                    end

                    ctx_str = link.ctx > 0 ? split(get_context(link.ctx), ",") : String[]
                    appt = Appointment(link.arr, index_to_sttype(stindex),
                                       node.chap, ctx_str, nptr, [link.dst])
                    if !haskey(result, link.arr)
                        result[link.arr] = Appointment[]
                    end
                    push!(result[link.arr], appt)
                    count += 1
                    count >= size && break
                end
            end
            count >= size && break
        end
    end
    return result
end

"""
    get_appointed_nodes_by_sttype(store::MemoryStore, sttype::Int;
                                  context::Vector{String}=String[],
                                  chapter::AbstractString="any",
                                  size::Int=100) -> Dict{Int, Vector{Appointment}}

Get appointed nodes grouped by STType (memory-backed).
Scans nodes for incoming links in the specified ST channel,
groups results by arrow pointer.
"""
function get_appointed_nodes_by_sttype(store::MemoryStore, sttype::Int;
                                       context::Vector{String}=String[],
                                       chapter::AbstractString="any",
                                       size::Int=100)::Dict{Int, Vector{Appointment}}
    result = Dict{Int, Vector{Appointment}}()
    stindex = sttype_to_index(sttype)
    (stindex < 1 || stindex > ST_TOP) && return result

    for (nptr, node) in store.nodes
        if chapter != "any" && !isempty(chapter)
            !similar_string(node.chap, chapter) && continue
        end

        count = 0
        for link in node.incidence[stindex]
            if !isempty(context)
                !match_contexts(context, link.ctx) && continue
            end

            ctx_str = link.ctx > 0 ? split(get_context(link.ctx), ",") : String[]
            appt = Appointment(link.arr, sttype, node.chap, ctx_str, nptr, [link.dst])
            if !haskey(result, link.arr)
                result[link.arr] = Appointment[]
            end
            push!(result[link.arr], appt)
            count += 1
            count >= size && break
        end
    end
    return result
end

# ──────────────────────────────────────────────────────────────────
# Database-backed appointed node queries
# ──────────────────────────────────────────────────────────────────

"""
    get_appointed_nodes_by_arrow(sst::SSTConnection, arrow::Int;
                                 context::Vector{String}=String[],
                                 chapter::AbstractString="any",
                                 size::Int=100) -> Dict{Int, Vector{Appointment}}

Get appointed nodes grouped by arrow type using the PostgreSQL stored procedure.
"""
function get_appointed_nodes_by_arrow(sst::SSTConnection, arrow::Int;
                                      context::Vector{String}=String[],
                                      chapter::AbstractString="any",
                                      size::Int=100)::Dict{Int, Vector{Appointment}}
    result = Dict{Int, Vector{Appointment}}()
    cn = format_sql_string_array(context)
    ec = sql_escape(chapter)

    sql = "SELECT * FROM GetAppointments($(arrow), 0, $(cn), '$(ec)', $(size))"

    try
        qresult = execute_sql_strict(sst.conn, sql)
        for row in LibPQ.Columns(qresult)
            appt = parse_appointed_node_cluster(string(row[1]))
            if appt.arr != 0
                if !haskey(result, appt.arr)
                    result[appt.arr] = Appointment[]
                end
                push!(result[appt.arr], appt)
            end
        end
    catch e
        @warn "GetAppointments query failed" arrow=arrow exception=e
    end

    return result
end

"""
    get_appointed_nodes_by_sttype(sst::SSTConnection, sttype::Int;
                                  context::Vector{String}=String[],
                                  chapter::AbstractString="any",
                                  size::Int=100) -> Dict{Int, Vector{Appointment}}

Get appointed nodes grouped by STType using the PostgreSQL stored procedure.
"""
function get_appointed_nodes_by_sttype(sst::SSTConnection, sttype::Int;
                                       context::Vector{String}=String[],
                                       chapter::AbstractString="any",
                                       size::Int=100)::Dict{Int, Vector{Appointment}}
    result = Dict{Int, Vector{Appointment}}()
    cn = format_sql_string_array(context)
    ec = sql_escape(chapter)

    sql = "SELECT * FROM GetAppointments(0, $(sttype), $(cn), '$(ec)', $(size))"

    try
        qresult = execute_sql_strict(sst.conn, sql)
        for row in LibPQ.Columns(qresult)
            appt = parse_appointed_node_cluster(string(row[1]))
            if appt.arr != 0
                if !haskey(result, appt.arr)
                    result[appt.arr] = Appointment[]
                end
                push!(result[appt.arr], appt)
            end
        end
    catch e
        @warn "GetAppointments query failed" sttype=sttype exception=e
    end

    return result
end

# ──────────────────────────────────────────────────────────────────
# PostgreSQL tuple parsing
# ──────────────────────────────────────────────────────────────────

"""
    parse_appointed_node_cluster(whole::AbstractString) -> Appointment

Parse a PostgreSQL appointment cluster tuple string into an Appointment.
Expected format: `(arr,sttype,chapter,"{ctx1,ctx2}",\"(class,cptr)\","{\"(c,p)\",...}")`
"""
function parse_appointed_node_cluster(whole::AbstractString)::Appointment
    s = strip(whole)
    isempty(s) && return Appointment()

    # Strip outer parens
    if startswith(s, "(") && endswith(s, ")")
        s = s[2:end-1]
    end

    runes = collect(s)
    fields = String[]
    current = Char[]
    depth = 0

    for ch in runes
        if ch in ('{', '(', '"')
            depth += 1
            push!(current, ch)
        elseif ch in ('}', ')', '"') && depth > 0
            depth -= 1
            push!(current, ch)
        elseif ch == ',' && depth == 0
            push!(fields, String(current))
            empty!(current)
        else
            push!(current, ch)
        end
    end
    !isempty(current) && push!(fields, String(current))

    length(fields) < 6 && return Appointment()

    arr = something(tryparse(Int, strip(fields[1])), 0)
    sttype = something(tryparse(Int, strip(fields[2])), 0)
    chap = strip(fields[3], ['"', ' '])
    ctx = parse_sql_array_string(fields[4])
    nto = _parse_nptr_field(fields[5])
    nfrom = parse_sql_nptr_array(fields[6])

    return Appointment(arr, sttype, chap, ctx, nto, nfrom)
end

"""Parse a single NodePtr from a field string."""
function _parse_nptr_field(s::AbstractString)::NodePtr
    cleaned = strip(s, ['"', ' ', '\\'])
    m = match(r"\((\d+),(\d+)\)", cleaned)
    isnothing(m) && return NO_NODE_PTR
    return NodePtr(parse(Int, m[1]), parse(Int, m[2]))
end
