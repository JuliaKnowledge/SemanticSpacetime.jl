#=
Arrow directory management for Semantic Spacetime.

Arrows are named, typed relationships between nodes. Each arrow has a
long name, short alias, Semantic Spacetime type index, and integer pointer.
Arrows must be registered before they can be used in links.

Ported from SSTorytime/pkg/SSTorytime/SSTorytime.go.
=#

# ──────────────────────────────────────────────────────────────────
# Arrow state (module-level, matching Go's global variables)
# ──────────────────────────────────────────────────────────────────

const _ARROW_DIRECTORY = ArrowEntry[]
const _ARROW_SHORT_DIR = Dict{String, ArrowPtr}()
const _ARROW_LONG_DIR  = Dict{String, ArrowPtr}()
const _INVERSE_ARROWS  = Dict{ArrowPtr, ArrowPtr}()
const _IGNORE_ARROWS   = ArrowPtr[]

# Thread-safe counter for arrow pointer allocation
const _ARROW_DIRECTORY_TOP = Ref{ArrowPtr}(0)

"""
    reset_arrows!()

Reset all arrow state. Primarily for testing.
"""
function reset_arrows!()
    empty!(_ARROW_DIRECTORY)
    empty!(_ARROW_SHORT_DIR)
    empty!(_ARROW_LONG_DIR)
    empty!(_INVERSE_ARROWS)
    empty!(_IGNORE_ARROWS)
    _ARROW_DIRECTORY_TOP[] = 0
    nothing
end

# ──────────────────────────────────────────────────────────────────
# STType name ↔ index conversion
# ──────────────────────────────────────────────────────────────────

"""
    get_stindex_by_name(stname::AbstractString, pm::AbstractString) -> Int

Convert a Semantic Spacetime type name and sign into a 1-based array index.
`stname` is one of "NEAR", "LEADSTO", "CONTAINS", "EXPRESS" (case-insensitive).
`pm` is "+" or "-" (or "" for NEAR).
"""
function get_stindex_by_name(stname::AbstractString, pm::AbstractString)
    name = uppercase(strip(stname))
    base = if name == "NEAR" || name == "NR" || name == "NEAR/SIMILAR" || name == "SIMILARITY" || name == "NEARNESS"
        Int(NEAR)
    elseif name == "LEADSTO" || name == "LT" || name == "LEADS TO" || name == "LEADS_TO"
        Int(LEADSTO)
    elseif name == "CONTAINS" || name == "CN" || name == "PART OF"
        Int(CONTAINS)
    elseif name == "EXPRESS" || name == "EP" || name == "EXPRESSES" || name == "PROPERTY" || name == "PROPERTIES"
        Int(EXPRESS)
    else
        error("Unknown ST type name: $stname")
    end

    sign = if strip(pm) == "-"
        -1
    elseif strip(pm) == "+" || strip(pm) == "both"
        1
    else
        base == 0 ? 1 : 1  # default positive
    end

    return sttype_to_index(sign * base)
end

"""
    print_stindex(stindex::Int) -> String

Return a human-readable label for an ST array index.
"""
function print_stindex(stindex::Int)
    st = index_to_sttype(stindex)
    absval = abs(st)
    name = if absval == 0
        "NEAR"
    elseif absval == 1
        "LEADSTO"
    elseif absval == 2
        "CONTAINS"
    elseif absval == 3
        "EXPRESS"
    else
        "UNKNOWN"
    end
    sign = st < 0 ? "-" : (st > 0 ? "+" : "")
    return "$sign$name"
end

# ──────────────────────────────────────────────────────────────────
# Arrow registration
# ──────────────────────────────────────────────────────────────────

"""
    insert_arrow!(stname, alias, name, pm) -> ArrowPtr

Register a new arrow type in the directory. Returns the allocated ArrowPtr.

- `stname`: ST type name ("NEAR", "LEADSTO", "CONTAINS", "EXPRESS")
- `alias`: Short name/alias for the arrow
- `name`: Long descriptive name
- `pm`: Sign string ("+" or "-")
"""
function insert_arrow!(stname::AbstractString, alias::AbstractString,
                       name::AbstractString, pm::AbstractString)
    short = strip(alias)
    long  = strip(name)

    # Check if already registered
    if haskey(_ARROW_SHORT_DIR, short)
        return _ARROW_SHORT_DIR[short]
    end
    if haskey(_ARROW_LONG_DIR, long)
        return _ARROW_LONG_DIR[long]
    end

    _ARROW_DIRECTORY_TOP[] += 1
    ptr = _ARROW_DIRECTORY_TOP[]
    stindex = get_stindex_by_name(stname, pm)

    entry = ArrowEntry(stindex, long, short, ptr)
    push!(_ARROW_DIRECTORY, entry)

    _ARROW_SHORT_DIR[short] = ptr
    _ARROW_LONG_DIR[long] = ptr

    return ptr
end

"""
    insert_inverse_arrow!(fwd::ArrowPtr, bwd::ArrowPtr)

Register a pair of arrows as inverses of each other.
"""
function insert_inverse_arrow!(fwd::ArrowPtr, bwd::ArrowPtr)
    _INVERSE_ARROWS[fwd] = bwd
    _INVERSE_ARROWS[bwd] = fwd
    nothing
end

# ──────────────────────────────────────────────────────────────────
# Arrow lookup
# ──────────────────────────────────────────────────────────────────

"""
    get_arrow_by_name(name::AbstractString) -> Union{ArrowEntry, Nothing}

Look up an arrow by its short or long name.
"""
function get_arrow_by_name(name::AbstractString)
    s = strip(name)
    if haskey(_ARROW_SHORT_DIR, s)
        ptr = _ARROW_SHORT_DIR[s]
        return _ARROW_DIRECTORY[ptr]
    end
    if haskey(_ARROW_LONG_DIR, s)
        ptr = _ARROW_LONG_DIR[s]
        return _ARROW_DIRECTORY[ptr]
    end
    return nothing
end

"""
    get_arrow_by_ptr(ptr::ArrowPtr) -> ArrowEntry

Look up an arrow by its pointer. Throws if not found.
"""
function get_arrow_by_ptr(ptr::ArrowPtr)
    1 <= ptr <= length(_ARROW_DIRECTORY) || error("Arrow pointer out of bounds: $ptr")
    return _ARROW_DIRECTORY[ptr]
end

"""
    get_inverse_arrow(ptr::ArrowPtr) -> Union{ArrowPtr, Nothing}

Get the inverse of an arrow, or nothing if no inverse is registered.
"""
function get_inverse_arrow(ptr::ArrowPtr)
    return get(_INVERSE_ARROWS, ptr, nothing)
end

"""
    get_sttype_from_arrows(arrows::Vector{ArrowPtr}) -> Vector{Int}

Extract the set of unique ST type indices from a list of arrow pointers.
"""
function get_sttype_from_arrows(arrows::Vector{ArrowPtr})
    sttypes = Set{Int}()
    for aptr in arrows
        entry = get_arrow_by_ptr(aptr)
        push!(sttypes, entry.stindex)
    end
    return sort!(collect(sttypes))
end

"""
    arrow_directory() -> Vector{ArrowEntry}

Return a copy of the current arrow directory.
"""
arrow_directory() = copy(_ARROW_DIRECTORY)

"""
    inverse_arrows() -> Dict{ArrowPtr, ArrowPtr}

Return a copy of the inverse arrow mapping.
"""
inverse_arrows() = copy(_INVERSE_ARROWS)
