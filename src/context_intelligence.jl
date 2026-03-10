#=
Context intelligence for Semantic Spacetime.

Provides STM (Short-Term Memory) tracking for contextual fragments,
intent/ambient separation, and context intersection analysis.

Ported from SSTorytime/pkg/SSTorytime/SSTorytime.go.
=#

# ──────────────────────────────────────────────────────────────────
# STM History type
# ──────────────────────────────────────────────────────────────────

"""
    STMHistory

Tracks frequency, timing, and context key for a short-term memory fragment.
"""
mutable struct STMHistory
    freq::Float64
    last::Int64
    delta::Int64
    time_key::String
end

STMHistory() = STMHistory(0.0, 0, 0, "")

# ──────────────────────────────────────────────────────────────────
# Module-level STM state
# ──────────────────────────────────────────────────────────────────

const STM_INT_FRAG = Ref{Dict{String,STMHistory}}()  # intentional (exceptional) fragments
const STM_AMB_FRAG = Ref{Dict{String,STMHistory}}()   # ambient (repeated) fragments
const FORGOTTEN = 10800  # seconds before forgetting
const TEXT_SIZE_LIMIT = 30

"""
    reset_stm!()

Reset the STM intentional and ambient fragment tracking state.
"""
function reset_stm!()
    STM_INT_FRAG[] = Dict{String,STMHistory}()
    STM_AMB_FRAG[] = Dict{String,STMHistory}()
end

# ──────────────────────────────────────────────────────────────────
# Context analysis
# ──────────────────────────────────────────────────────────────────

"""
    context_intent_analysis(spectrum::Dict{String,Int}, clusters::Vector{String})

Separate intentional (low frequency < 3) from ambient fragments.
Returns (intentional::Vector{String}, ambient::Vector{String}).
"""
function context_intent_analysis(spectrum::Dict{String,Int}, clusters::Vector{String})
    INTENT_LIMIT = 3

    intentional = String[]
    for (f, count) in spectrum
        if count < INTENT_LIMIT
            push!(intentional, f)
        end
    end

    # Remove intentional fragments from spectrum
    for f in intentional
        delete!(spectrum, f)
    end

    # Prune intentional fragments from clusters
    for (i, cl) in enumerate(clusters)
        for del in intentional
            cl = replace(cl, del * ", " => "")
            cl = replace(cl, del => "")
        end
        clusters[i] = cl
    end

    # Rebuild spectrum from pruned clusters
    new_spectrum = Dict{String,Int}()
    for cl in clusters
        pruned = strip(cl, [' ', ','])
        !isempty(pruned) && (new_spectrum[pruned] = get(new_spectrum, pruned, 0) + 1)
    end

    # One more round of diffs for final separation
    ambient_map = Dict{String,Int}()
    context_list = sort!(collect(keys(new_spectrum)))

    for ci in 1:length(context_list)
        for cj in (ci+1):length(context_list)
            shared, different = diff_clusters(context_list[ci], context_list[cj])
            if !isempty(shared) && !isempty(different) &&
               length(different) <= length(context_list[ci]) + length(context_list[cj])
                ambient_map[strip(shared)] = get(ambient_map, strip(shared), 0) + 1
                ambient_map[strip(different)] = get(ambient_map, strip(different), 0) + 1
            end
        end
    end

    ambient = sort!(collect(keys(ambient_map)))
    return (intentional, ambient)
end

# ──────────────────────────────────────────────────────────────────
# STM context tracking
# ──────────────────────────────────────────────────────────────────

"""
    update_stm_context(store::AbstractSSTStore, ambient::String, key::String, now::Int64, params)::String

Update STM context from search parameters. Extracts tokens from the params
and delegates to `add_context`.
"""
function update_stm_context(store::AbstractSSTStore, ambient::String, key::String, now::Int64, params)::String
    context = String[]
    if hasproperty(params, :name)
        append!(context, params.name isa Vector ? params.name : [params.name])
    end
    if hasproperty(params, :context)
        for ct in params.context
            !isempty(ct) && push!(context, ct)
        end
    end
    return add_context(store, ambient, key, now, context)
end

"""
    add_context(store::AbstractSSTStore, ambient::String, key::String, now::Int64, tokens::Vector{String})::String

Add tokens to STM tracking, prune forgotten entries, and return
the combined context string of all active STM fragments.
"""
function add_context(store::AbstractSSTStore, ambient::String, key::String, now::Int64, tokens::Vector{String})::String
    for token in tokens
        (isempty(token) || token == "%%") && continue
        commit_context_token!(token, now, ambient)
    end

    # Collect active context, pruning forgotten entries
    format = Dict{String,Int}()

    for (fr, hist) in STM_AMB_FRAG[]
        if hist.delta > FORGOTTEN
            delete!(STM_AMB_FRAG[], fr)
            continue
        end
        format[fr] = get(format, fr, 0) + 1
    end

    for (fr, hist) in STM_INT_FRAG[]
        if hist.delta > FORGOTTEN
            delete!(STM_INT_FRAG[], fr)
            continue
        end
        format[fr] = get(format, fr, 0) + 1
    end

    parts = sort!(collect(keys(format)))
    return join(parts, ",")
end

"""
    commit_context_token!(token::AbstractString, now::Int64, key::AbstractString)

Track a token in STM. If previously seen, moves it from intentional to ambient.
"""
function commit_context_token!(token::AbstractString, now::Int64, key::AbstractString)
    t = String(token)
    k = String(key)

    # Check if already known ambient
    already = false
    last = STMHistory()

    if haskey(STM_AMB_FRAG[], t)
        last = STM_AMB_FRAG[][t]
        already = true
    elseif haskey(STM_INT_FRAG[], t)
        last = STM_INT_FRAG[][t]
        already = true
    end

    if !already
        last.last = now
    end

    obs = STMHistory()
    obs.freq = last.freq + 1.0
    obs.last = now
    obs.time_key = k
    obs.delta = now - last.last

    if already
        delete!(STM_INT_FRAG[], t)
        STM_AMB_FRAG[][t] = obs
    else
        STM_INT_FRAG[][t] = obs
    end
end

# ──────────────────────────────────────────────────────────────────
# Context intersection and diffing
# ──────────────────────────────────────────────────────────────────

"""
    intersect_context_parts(context_clusters::Vector{String})

Compute pairwise overlap between context clusters.
Returns (count, unique_clusters, overlap_matrix).
"""
function intersect_context_parts(context_clusters::Vector{String})
    idemp = Dict{String,Int}()
    for s in context_clusters
        idemp[s] = get(idemp, s, 0) + 1
    end

    cluster_list = sort!(collect(keys(idemp)))
    n = length(cluster_list)

    adj = Vector{Vector{Int}}()
    for ci in 1:n
        row = Int[]
        for cj in (ci+1):n
            shared, _ = diff_clusters(cluster_list[ci], cluster_list[cj])
            push!(row, length(shared))
        end
        push!(adj, row)
    end

    return (n, cluster_list, adj)
end

"""
    diff_clusters(l1::AbstractString, l2::AbstractString)

Return (shared, different) parts of two comma-separated context strings.
"""
function diff_clusters(l1::AbstractString, l2::AbstractString)
    spectrum1 = [strip(s) for s in split(String(l1), ", ")]
    spectrum2 = [strip(s) for s in split(String(l2), ", ")]

    m1 = _list_to_map(spectrum1)
    m2 = _list_to_map(spectrum2)

    return overlap_matrix(m1, m2)
end

"""
    overlap_matrix(m1::Dict{String,Int}, m2::Dict{String,Int})

Return (shared_string, different_string) representing overlap and unique
parts of two token frequency maps.
"""
function overlap_matrix(m1::Dict{String,Int}, m2::Dict{String,Int})
    common = Dict{String,Int}()
    separate = Dict{String,Int}()

    for ng in keys(m1)
        if get(m2, ng, 0) > 0
            common[ng] = get(common, ng, 0) + 1
        else
            separate[ng] = get(separate, ng, 0) + 1
        end
    end

    for ng in keys(m2)
        if get(m1, ng, 0) > 0
            delete!(separate, ng)
            common[ng] = get(common, ng, 0) + 1
        else
            if !haskey(common, ng)
                separate[ng] = get(separate, ng, 0) + 1
            end
        end
    end

    shared_str = join(sort!(collect(keys(common))), ",")
    diff_str = join(sort!(collect(keys(separate))), ",")
    return (shared_str, diff_str)
end

"""
    get_context_token_frequencies(fraglist::Vector{String}) -> Dict{String,Int}

Build a frequency map from a list of comma-separated context strings.
"""
function get_context_token_frequencies(fraglist::Vector{String})::Dict{String,Int}
    spectrum = Dict{String,Int}()
    for l in fraglist
        fragments = [strip(s) for s in split(l, ", ")]
        for f in fragments
            !isempty(f) && (spectrum[f] = get(spectrum, f, 0) + 1)
        end
    end
    return spectrum
end

# ──────────────────────────────────────────────────────────────────
# Context interferometry (deprecated stub)
# ──────────────────────────────────────────────────────────────────

"""
    context_interferometry(context_clusters::Vector{String}) -> Nothing

Deprecated/placeholder. In the original Go source this function was deleted
(body replaced with `// deleted`). Retained here as a no-op stub for API
compatibility. Use `intersect_context_parts` and `diff_clusters` instead.
"""
function context_interferometry(context_clusters::Vector{String})
    nothing
end

# ──────────────────────────────────────────────────────────────────
# Node context extraction
# ──────────────────────────────────────────────────────────────────

"""
    get_node_context_string(store::AbstractSSTStore, node::Node) -> String

Get the context string from a node's ghost link (empty arrow, LEADSTO type).
The context is stored as an incoming link with the "empty" arrow.
"""
function get_node_context_string(store::AbstractSSTStore, node::Node)::String
    empty_entry = get_arrow_by_name("empty")
    isnothing(empty_entry) && return ""

    # LEADSTO ghost link: check both +LEADSTO and -LEADSTO channels
    for sttype_val in [Int(LEADSTO), -Int(LEADSTO)]
        stindex = sttype_to_index(sttype_val)
        (stindex < 1 || stindex > ST_TOP) && continue
        stindex > length(node.incidence) && continue
        for lnk in node.incidence[stindex]
            if lnk.arr == empty_entry.ptr
                return get_context(lnk.ctx)
            end
        end
    end
    return ""
end

"""
    get_node_context(store::AbstractSSTStore, node::Node) -> Vector{String}

Get the context strings attached to a node via the empty arrow ghost link.
Returns a vector of context labels parsed from the comma-separated context string.
"""
function get_node_context(store::AbstractSSTStore, node::Node)::Vector{String}
    str = get_node_context_string(store, node)
    isempty(str) && return String[]
    return [strip(s) for s in split(str, ",") if !isempty(strip(s))]
end

# ──────────────────────────────────────────────────────────────────
# Internal helpers
# ──────────────────────────────────────────────────────────────────

function _list_to_map(l::Vector{<:AbstractString})::Dict{String,Int}
    m = Dict{String,Int}()
    for s in l
        t = strip(String(s))
        !isempty(t) && (m[t] = get(m, t, 0) + 1)
    end
    return m
end
