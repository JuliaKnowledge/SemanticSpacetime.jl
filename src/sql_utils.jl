#=
SQL serialization utilities for Semantic Spacetime.

Provides formatting and parsing of PostgreSQL array literals,
link strings, Dirac notation, and other SQL/search helpers.

Note: sql_escape is defined in types.jl.
=#

# ──────────────────────────────────────────────────────────────────
# SQL array formatting
# ──────────────────────────────────────────────────────────────────

"""
    format_sql_string_array(arr::Vector{String}) -> String

Convert a string array to a PostgreSQL array literal.
"""
function format_sql_string_array(arr::Vector{String})::String
    isempty(arr) && return "'{ }'"
    sorted = sort(arr)
    parts = String[]
    for s in sorted
        !isempty(s) && push!(parts, "\"$(sql_escape(s))\"")
    end
    return "'{ $(join(parts, ", ")) }' "
end

"""
    format_sql_int_array(arr::Vector{Int}) -> String

Convert an integer array to a PostgreSQL array literal.
"""
function format_sql_int_array(arr::Vector{Int})::String
    isempty(arr) && return "'{ }'"
    sorted = sort(arr)
    return "'{ $(join(sorted, ", ")) }' "
end

"""
    format_sql_nodeptr_array(arr::Vector{NodePtr}) -> String

Convert a NodePtr array to a PostgreSQL array literal.
"""
function format_sql_nodeptr_array(arr::Vector{NodePtr})::String
    isempty(arr) && return "'{ }'"
    parts = ["\"($(n.class),$(n.cptr))\"" for n in arr]
    return "'{ $(join(parts, ", ")) }' "
end

"""
    format_sql_link_array(arr::Vector{Link}) -> String

Convert a Link array to a PostgreSQL array literal.
"""
function format_sql_link_array(arr::Vector{Link})::String
    parts = String[]
    for lnk in arr
        l = "($(Int(lnk.arr)), $(lnk.wgt), $(Int(lnk.ctx)), \\\"($(lnk.dst.class),$(lnk.dst.cptr))\\\")"
        push!(parts, "\"$l\"")
    end
    return "{$(join(parts, ","))}"
end

# ──────────────────────────────────────────────────────────────────
# SQL array parsing
# ──────────────────────────────────────────────────────────────────

"""
    parse_sql_array_string(s::AbstractString) -> Vector{String}

Parse a PostgreSQL array string into a string vector.
"""
function parse_sql_array_string(s::AbstractString)::Vector{String}
    s = replace(s, "{" => "", "}" => "")
    items = String[]
    current = Char[]
    protected = false
    for ch in s
        if ch == '"'
            protected = !protected
            continue
        end
        if !protected && ch == ','
            push!(items, strip(String(current)))
            empty!(current)
            continue
        end
        push!(current, ch)
    end
    !isempty(current) && push!(items, strip(String(current)))
    return items
end

"""
    parse_sql_nptr_array(s::AbstractString) -> Vector{NodePtr}

Parse a PostgreSQL NodePtr array string.
"""
function parse_sql_nptr_array(s::AbstractString)::Vector{NodePtr}
    strs = parse_sql_array_string(s)
    ptrs = NodePtr[]
    for str in strs
        m = match(r"\((\d+),(\d+)\)", str)
        !isnothing(m) && push!(ptrs, NodePtr(parse(Int, m[1]), parse(Int, m[2])))
    end
    return ptrs
end

"""
    parse_sql_link_string(s::AbstractString) -> Link

Parse a SQL link string like "77,0.34,334,4,2" into a Link.
"""
function parse_sql_link_string(s::AbstractString)::Link
    s = replace(s, "\"" => "", "\\" => "", "(" => "", ")" => "")
    items = split(s, ",")
    items = [strip(String(i)) for i in items]
    length(items) < 5 && return Link(0, 0.0f0, 0, NO_NODE_PTR)
    arr = parse(Int, items[1])
    wgt = parse(Float32, items[2])
    ctx = parse(Int, items[3])
    cls = parse(Int, items[4])
    cptr = parse(Int, items[5])
    return Link(arr, wgt, ctx, NodePtr(cls, cptr))
end

"""
    parse_link_path(s::AbstractString) -> Vector{Vector{Link}}

Parse a link path string (lines of semicolon-separated links).
"""
function parse_link_path(s::AbstractString)::Vector{Vector{Link}}
    result = Vector{Link}[]
    s = strip(s)
    for line in split(s, "\n")
        line = strip(String(line))
        isempty(line) && continue
        links = [parse_sql_link_string(String(l)) for l in split(line, ";") if !isempty(strip(String(l)))]
        !isempty(links) && push!(result, links)
    end
    return result
end

# ──────────────────────────────────────────────────────────────────
# String/array conversions
# ──────────────────────────────────────────────────────────────────

"""
    array2str(arr::Vector{String}) -> String

Convert string array to comma-separated string.
"""
function array2str(arr::Vector{String})::String
    join(arr, ", ")
end

"""
    str2array(s::AbstractString) -> (Vector{String}, Int)

Parse comma-separated string to array. Returns (array, non_empty_count).
"""
function str2array(s::AbstractString)::Tuple{Vector{String},Int}
    s = replace(s, "{" => "", "}" => "", "\"" => "")
    arr = [strip(String(x)) for x in split(s, ",")]
    non_zero = count(!isempty, arr)
    return (arr, non_zero)
end

# ──────────────────────────────────────────────────────────────────
# DB channel mapping
# ──────────────────────────────────────────────────────────────────

"""
    sttype_db_channel(sttype::Int) -> String

Map signed STtype to DB column name.
"""
function sttype_db_channel(sttype::Int)::String
    sttype == 0 && return "In0"
    sttype == 1 && return "Il1"
    sttype == 2 && return "Ic2"
    sttype == 3 && return "Ie3"
    sttype == -1 && return "Im1"
    sttype == -2 && return "Im2"
    sttype == -3 && return "Im3"
    error("Illegal ST link class: $sttype")
end

"""
    storage_class(s::AbstractString) -> (Int, Int)

Classify text by n-gram count (spaces) into (length, storage_class).
"""
function storage_class(s::AbstractString)::Tuple{Int,Int}
    l = length(s)
    spaces = count(==(' '), s)
    spaces == 0 && return (l, N1GRAM)
    spaces == 1 && return (l, N2GRAM)
    spaces == 2 && return (l, N3GRAM)
    l < 128 && return (l, LT128)
    l < 1024 && return (l, LT1024)
    return (l, GT1024)
end

# ──────────────────────────────────────────────────────────────────
# Dirac notation
# ──────────────────────────────────────────────────────────────────

"""
    dirac_notation(s::AbstractString) -> (Bool, String, String, String)

Parse Dirac bra-ket notation: <a|b> or <a|context|b>.
Returns (ok, bra_target, ket_target, context).
"""
function dirac_notation(s::AbstractString)::Tuple{Bool,String,String,String}
    isempty(s) && return (false, "", "", "")
    (s[1] == '<' && s[end] == '>') || return (false, "", "", "")
    matrix = s[2:end-1]
    params = split(matrix, "|")
    if length(params) == 2
        return (true, String(params[2]), String(params[1]), "")
    elseif length(params) == 3
        return (true, String(params[3]), String(params[1]), String(params[2]))
    end
    return (false, "", "", "")
end

# ──────────────────────────────────────────────────────────────────
# STtype naming
# ──────────────────────────────────────────────────────────────────

"""
    sttype_name(sttype::Int) -> String

Get STtype human-readable name.
"""
function sttype_name(sttype::Int)::String
    sttype == -Int(EXPRESS) && return "-is property of"
    sttype == -Int(CONTAINS) && return "-contained by"
    sttype == -Int(LEADSTO) && return "-comes from"
    sttype == Int(NEAR) && return "=Similarity"
    sttype == Int(LEADSTO) && return "+leads to"
    sttype == Int(CONTAINS) && return "+contains"
    sttype == Int(EXPRESS) && return "+property"
    return "Unknown ST type"
end

# ──────────────────────────────────────────────────────────────────
# String utilities
# ──────────────────────────────────────────────────────────────────

"""
    escape_json_string(s::AbstractString) -> String

Escape string for JSON output (remove newlines, escape quotes).
"""
function escape_json_string(s::AbstractString)::String
    result = Char[]
    for ch in s
        if ch == '\n'
            continue
        elseif ch == '"'
            push!(result, '\\')
            push!(result, '"')
        else
            push!(result, ch)
        end
    end
    return String(result)
end

"""
    context_string(context::Vector{String}) -> String

Convert context array to space-separated string.
"""
function context_string(context::Vector{String})::String
    join(context, " ")
end

"""
    similar_string(full::AbstractString, like::AbstractString) -> Bool

Fuzzy string matching — returns true if strings are equal,
either is empty, either is "any", or `like` is a substring of `full`.
"""
function similar_string(full::AbstractString, like::AbstractString)::Bool
    full == like && return true
    (isempty(full) || isempty(like)) && return true
    (full == "any" || like == "any") && return true
    return occursin(like, full)
end

"""
    in_list(s::AbstractString, list::Vector{String}) -> (Int, Bool)

Check if item is in list. Returns (index, found).
"""
function in_list(s::AbstractString, list::Vector{String})::Tuple{Int,Bool}
    for (i, v) in enumerate(list)
        v == s && return (i, true)
    end
    return (-1, false)
end

"""
    match_arrows(arrows::Vector{ArrowPtr}, arr::ArrowPtr) -> Bool

Check if arrow pointer matches any in list.
"""
function match_arrows(arrows::Vector{ArrowPtr}, arr::ArrowPtr)::Bool
    arr in arrows
end

"""
    match_contexts(context1::Vector{String}, context2_ptr::ContextPtr) -> Bool

Check if any context1 item matches context2.
"""
function match_contexts(context1::Vector{String}, context2_ptr::ContextPtr)::Bool
    (isempty(context1) || context2_ptr == 0) && return true
    context2 = split(get_context(context2_ptr), ",")
    for c1 in context1
        for c2 in context2
            similar_string(String(c1), strip(String(c2))) && return true
        end
    end
    return false
end

"""
    matches_in_context(s::AbstractString, context::Vector{String}) -> Bool

Check if string matches any context.
"""
function matches_in_context(s::AbstractString, context::Vector{String})::Bool
    for c in context
        similar_string(s, c) && return true
    end
    return false
end

"""
    arrow2int(arr::Vector{ArrowPtr}) -> Vector{Int}

Convert ArrowPtr vector to Int vector.
"""
function arrow2int(arr::Vector{ArrowPtr})::Vector{Int}
    [Int(a) for a in arr]
end

# ──────────────────────────────────────────────────────────────────
# Collection conversions
# ──────────────────────────────────────────────────────────────────

"""
    list2map(l::Vector{<:AbstractString}) -> Dict{String,Int}

Convert a list of strings to a frequency map (counts occurrences).
"""
function list2map(l::Vector{<:AbstractString})::Dict{String,Int}
    result = Dict{String,Int}()
    for s in l
        key = strip(s)
        result[key] = get(result, key, 0) + 1
    end
    return result
end

"""
    map2list(m::Dict{String,Int}) -> Vector{String}

Convert a frequency map to a sorted list of its keys.
"""
function map2list(m::Dict{String,Int})::Vector{String}
    return sort!([strip(s) for s in keys(m)])
end

"""
    list2string(list::Vector{<:AbstractString}) -> String

Convert a list of strings to a sorted, comma-separated string.
"""
function list2string(list::Vector{<:AbstractString})::String
    return join(sort(list), ",")
end

"""
    parse_map_link_array(s::AbstractString) -> Vector{Link}

Parse a PageMap-style link array string (without outer braces)
into a vector of Links.
"""
function parse_map_link_array(s::AbstractString)::Vector{Link}
    array = Link[]
    s = strip(s)
    length(s) <= 2 && return array
    strarray = split(s, "\",\"")
    for item in strarray
        link = parse_sql_link_string(item)
        push!(array, link)
    end
    return array
end
