#=
Inhibition/NOT contexts in search for Semantic Spacetime.

Provides include/exclude context filtering for node search.
=#

# ──────────────────────────────────────────────────────────────────
# InhibitionContext
# ──────────────────────────────────────────────────────────────────

"""
    InhibitionContext

Represents include/exclude context filters for search.
Nodes matching `include` but not `exclude` pass the filter.
"""
struct InhibitionContext
    include::Vector{String}
    exclude::Vector{String}
end

InhibitionContext() = InhibitionContext(String[], String[])

Base.show(io::IO, ic::InhibitionContext) =
    print(io, "InhibitionContext(include=$(ic.include), exclude=$(ic.exclude))")

# ──────────────────────────────────────────────────────────────────
# Parsing
# ──────────────────────────────────────────────────────────────────

"""
    parse_inhibition_context(query::String) -> InhibitionContext

Parse "context A,B NOT C,D" into include/exclude lists.
The `NOT` keyword (case-insensitive) separates the include and exclude parts.
"""
function parse_inhibition_context(query::String)
    s = strip(query)
    isempty(s) && return InhibitionContext()

    # Split on NOT (case-insensitive)
    parts = split(s, r"\bNOT\b"i; limit=2)

    include_part = strip(String(parts[1]))
    exclude_part = length(parts) > 1 ? strip(String(parts[2])) : ""

    inc = _parse_context_list(include_part)
    exc = _parse_context_list(exclude_part)

    return InhibitionContext(inc, exc)
end

function _parse_context_list(s::AbstractString)
    s = strip(String(s))
    isempty(s) && return String[]
    parts = split(s, r"[,\s]+")
    return filter(!isempty, [strip(String(p)) for p in parts])
end

# ──────────────────────────────────────────────────────────────────
# Matching
# ──────────────────────────────────────────────────────────────────

"""
    matches_inhibition(ctx_string::String, inhibition::InhibitionContext) -> Bool

Check if a context string matches the include list and doesn't
match the exclude list. A context matches include if it contains
all include terms. It fails if it contains any exclude term.
Empty include list matches everything.
"""
function matches_inhibition(ctx_string::String, inhibition::InhibitionContext)
    ctx_lower = lowercase(ctx_string)
    ctx_parts = Set(filter(!isempty, [strip(p) for p in split(ctx_lower, ',')]))

    # Check include: all include terms must be present
    if !isempty(inhibition.include)
        for inc in inhibition.include
            if lowercase(inc) ∉ ctx_parts
                return false
            end
        end
    end

    # Check exclude: no exclude terms may be present
    for exc in inhibition.exclude
        if lowercase(exc) ∈ ctx_parts
            return false
        end
    end

    return true
end

# ──────────────────────────────────────────────────────────────────
# Search with inhibition
# ──────────────────────────────────────────────────────────────────

"""
    search_with_inhibition(store::MemoryStore, query::String,
                           inhibition::InhibitionContext) -> Vector{Node}

Search for nodes by text substring, filtering by inhibition context.
A node passes if any of its link contexts match the inhibition filter,
or if it has no links with context (uncontextualized nodes pass by default
when include is empty).
"""
function search_with_inhibition(store::MemoryStore, query::String,
                                inhibition::InhibitionContext)
    q = lowercase(strip(query))
    results = Node[]

    for node in values(store.nodes)
        # Text match
        occursin(q, lowercase(node.s)) || continue

        # Context match via inhibition
        if _node_matches_inhibition(node, inhibition)
            push!(results, node)
        end
    end

    return results
end

"""
Check if any link context on a node matches the inhibition filter.
"""
function _node_matches_inhibition(node::Node, inhibition::InhibitionContext)
    has_any_ctx = false

    for st_links in node.incidence
        for lnk in st_links
            lnk.ctx <= 0 && continue
            ctx_str = get_context(lnk.ctx)
            isempty(ctx_str) && continue
            has_any_ctx = true
            if matches_inhibition(ctx_str, inhibition)
                return true
            end
        end
    end

    # Uncontextualized nodes pass when include is empty
    if !has_any_ctx && isempty(inhibition.include)
        return true
    end

    return false
end
