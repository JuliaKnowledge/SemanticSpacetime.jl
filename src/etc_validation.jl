#=
Event/Thing/Concept validation for Semantic Spacetime.

Implements ETC type inference, validation, and display functions.
References Go functions CompleteETCTypes, CollapsePsi, ShowPsi
from SSTorytime/pkg/SSTorytime/SSTorytime.go.
=#

# ──────────────────────────────────────────────────────────────────
# ETC inference
# ──────────────────────────────────────────────────────────────────

"""
    infer_etc(node::Node) -> Etc

Infer Event/Thing/Concept classification from a node's link structure.
Iterates over all ST channels and collapses the classification.
"""
function infer_etc(node::Node)
    etc = Etc()
    for st in 1:ST_TOP
        if !isempty(node.incidence[st])
            etc, _ = collapse_psi(node, st)
        end
    end
    return etc
end

# ──────────────────────────────────────────────────────────────────
# Collapse Psi (per-channel classification)
# ──────────────────────────────────────────────────────────────────

"""
    collapse_psi(node::Node, stindex::Int) -> (Etc, String)

Collapse node classification along a specific ST dimension.
Follows SST Gamma(3,4) inference rules from the Go implementation.
"""
function collapse_psi(node::Node, stindex::Int)
    etc = Etc(node.psi.e, node.psi.t, node.psi.c)
    sttype = index_to_sttype(stindex)
    message = ""

    links = node.incidence[stindex]
    isempty(links) && return (etc, message)

    # Get arrow name for the first link
    arrow_name = ""
    if links[1].arr > 0 && links[1].arr <= length(_ARROW_DIRECTORY)
        arrow_name = _ARROW_DIRECTORY[links[1].arr].long
    end

    if sttype == Int(NEAR)
        # NEAR links are ambiguous — no change

    elseif sttype == Int(LEADSTO) || sttype == -Int(LEADSTO)
        # Skip bogus empty/debug links
        for lnk in links
            if lnk.arr > 0 && lnk.arr <= length(_ARROW_DIRECTORY)
                aname = _ARROW_DIRECTORY[lnk.arr].long
                if aname != "empty" && aname != "debug"
                    arrow_name = aname
                    break
                end
            end
        end
        if arrow_name == "empty" || arrow_name == "debug"
            return (etc, message)
        else
            etc.e = true
            etc.t = false
            etc.c = false
        end

    elseif sttype == Int(CONTAINS)
        etc.t = true
        etc.c = false  # concept can't contain

    elseif sttype == -Int(CONTAINS)
        etc.t = true

    elseif sttype == Int(EXPRESS)
        if !etc.e
            etc.c = true
            etc.t = true
        end

    elseif sttype == -Int(EXPRESS)
        etc.t = true
        etc.c = false
    end

    message = "Node \"$(node.s)\"  (seems to be of type)  $(show_psi(etc))"
    return (etc, message)
end

# ──────────────────────────────────────────────────────────────────
# Show Psi
# ──────────────────────────────────────────────────────────────────

"""
    show_psi(etc::Etc) -> String

Display ETC classification as a comma-separated string.
Matches the Go ShowPsi function output format.
"""
function show_psi(etc::Etc)
    result = ""
    etc.e && (result *= "event,")
    etc.t && (result *= "thing,")
    etc.c && (result *= "concept,")
    return result
end

# ──────────────────────────────────────────────────────────────────
# Validation
# ──────────────────────────────────────────────────────────────────

"""
    validate_etc(node::Node) -> Vector{String}

Return warnings about suspicious type assignments.
Checks for inconsistencies between the node's ETC classification
and its actual link structure.
"""
function validate_etc(node::Node)
    warnings = String[]
    etc = node.psi

    has_leadsto = false
    has_contains = false
    has_express = false
    has_near = false

    for st in 1:ST_TOP
        isempty(node.incidence[st]) && continue
        sttype = abs(index_to_sttype(st))
        if sttype == Int(LEADSTO)
            has_leadsto = true
        elseif sttype == Int(CONTAINS)
            has_contains = true
        elseif sttype == Int(EXPRESS)
            has_express = true
        elseif sttype == Int(NEAR)
            has_near = true
        end
    end

    # A "Thing" with only temporal (LEADSTO) links is suspicious
    if etc.t && !etc.e && has_leadsto && !has_contains && !has_express
        push!(warnings, "Node \"$(node.s)\" classified as Thing but has only LEADSTO links (expected CONTAINS)")
    end

    # An "Event" with no LEADSTO links
    if etc.e && !has_leadsto
        push!(warnings, "Node \"$(node.s)\" classified as Event but has no LEADSTO links")
    end

    # A "Concept" with CONTAINS links (concepts shouldn't contain)
    if etc.c && has_contains && !has_express
        push!(warnings, "Node \"$(node.s)\" classified as Concept but has CONTAINS links (concepts don't contain)")
    end

    # No links at all but has a classification
    if !has_leadsto && !has_contains && !has_express && !has_near
        if etc.e || etc.t || etc.c
            push!(warnings, "Node \"$(node.s)\" has ETC classification but no links")
        end
    end

    return warnings
end

# ──────────────────────────────────────────────────────────────────
# Graph-wide validation
# ──────────────────────────────────────────────────────────────────

"""
    validate_graph_types(store::MemoryStore) -> Dict{NodePtr, Vector{String}}

Validate all nodes in a graph. Returns a dictionary mapping node pointers
to their validation warnings. Only nodes with warnings are included.
"""
function validate_graph_types(store::MemoryStore)
    results = Dict{NodePtr, Vector{String}}()
    for (nptr, node) in store.nodes
        warns = validate_etc(node)
        if !isempty(warns)
            results[nptr] = warns
        end
    end
    return results
end
