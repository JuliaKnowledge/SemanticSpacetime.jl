#=
Session tracking (LastSeen) for Semantic Spacetime.

Provides in-memory tracking of when sections and node pointers were
last accessed, for building temporal context.

Ported from SSTorytime/pkg/SSTorytime/SSTorytime.go.
=#

# ──────────────────────────────────────────────────────────────────
# Module-level tracking state
# ──────────────────────────────────────────────────────────────────

const LAST_SEEN_SECTIONS = Ref{Dict{String,LastSeen}}()
const LAST_SEEN_NPTRS = Ref{Dict{NodePtr,LastSeen}}()

"""
    reset_session_tracking!()

Reset all in-memory session tracking state.
"""
function reset_session_tracking!()
    LAST_SEEN_SECTIONS[] = Dict{String,LastSeen}()
    LAST_SEEN_NPTRS[] = Dict{NodePtr,LastSeen}()
end

# ──────────────────────────────────────────────────────────────────
# Update operations
# ──────────────────────────────────────────────────────────────────

"""
    update_last_saw_section!(store::AbstractSSTStore, name::AbstractString)

Record that the given section was accessed at the current time.
"""
function update_last_saw_section!(store::AbstractSSTStore, name::AbstractString)
    sname = String(name)
    now = round(Int64, Dates.datetime2unix(Dates.now()))

    if haskey(LAST_SEEN_SECTIONS[], sname)
        ls = LAST_SEEN_SECTIONS[][sname]
        ls.pdelta = Float64(now - ls.last)
        ls.ndelta = 0.0
        ls.last = now
        ls.freq += 1
    else
        LAST_SEEN_SECTIONS[][sname] = LastSeen(
            sname, now, now, 0.0, 0.0, 1, NO_NODE_PTR, Coords()
        )
    end
end

"""
    update_last_saw_nptr!(store::AbstractSSTStore, nptr::NodePtr, name::AbstractString)

Record that the given node pointer was accessed at the current time.
"""
function update_last_saw_nptr!(store::AbstractSSTStore, nptr::NodePtr, name::AbstractString)
    now = round(Int64, Dates.datetime2unix(Dates.now()))

    if haskey(LAST_SEEN_NPTRS[], nptr)
        ls = LAST_SEEN_NPTRS[][nptr]
        ls.pdelta = Float64(now - ls.last)
        ls.ndelta = 0.0
        ls.last = now
        ls.freq += 1
    else
        LAST_SEEN_NPTRS[][nptr] = LastSeen(
            String(name), now, now, 0.0, 0.0, 1, nptr, Coords()
        )
    end
end

# ──────────────────────────────────────────────────────────────────
# Query operations
# ──────────────────────────────────────────────────────────────────

"""
    get_last_saw_section(store::AbstractSSTStore) -> Vector{LastSeen}

Return all tracked sections, sorted by section name, with updated ndelta.
"""
function get_last_saw_section(store::AbstractSSTStore)::Vector{LastSeen}
    now = round(Int64, Dates.datetime2unix(Dates.now()))
    result = LastSeen[]

    for (name, ls) in LAST_SEEN_SECTIONS[]
        ls.ndelta = Float64(now - ls.last)
        push!(result, ls)
    end

    sort!(result, by=ls -> ls.section)
    return result
end

"""
    get_last_saw_nptr(store::AbstractSSTStore, nptr::NodePtr) -> LastSeen

Return the LastSeen record for a specific node pointer.
Returns a default LastSeen if not tracked.
"""
function get_last_saw_nptr(store::AbstractSSTStore, nptr::NodePtr)::LastSeen
    if haskey(LAST_SEEN_NPTRS[], nptr)
        now = round(Int64, Dates.datetime2unix(Dates.now()))
        ls = LAST_SEEN_NPTRS[][nptr]
        ls.ndelta = Float64(now - ls.last)
        return ls
    end
    return LastSeen("", 0, 0, 0.0, 0.0, 0, NO_NODE_PTR, Coords())
end

"""
    get_newly_seen_nptrs(store::AbstractSSTStore, horizon::Int) -> Set{NodePtr}

Return the set of node pointers that were last seen within `horizon` hours.
If `horizon` <= 0, returns all tracked node pointers.
"""
function get_newly_seen_nptrs(store::AbstractSSTStore, horizon::Int)::Set{NodePtr}
    nptrs = Set{NodePtr}()
    now = round(Int64, Dates.datetime2unix(Dates.now()))
    threshold = horizon * 3600

    for (nptr, ls) in LAST_SEEN_NPTRS[]
        if horizon <= 0 || (now - ls.last) < threshold
            push!(nptrs, nptr)
        end
    end

    return nptrs
end
