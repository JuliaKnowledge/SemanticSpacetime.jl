#=
Context registration, normalization, and lookup for Semantic Spacetime.

Contexts are sorted, comma-joined string labels that scope nodes and links.
Each unique context string gets an integer pointer for efficient storage.

Ported from SSTorytime/pkg/SSTorytime/SSTorytime.go.
=#

# ──────────────────────────────────────────────────────────────────
# Context state (module-level)
# ──────────────────────────────────────────────────────────────────

const _CONTEXT_DIRECTORY = ContextEntry[]
const _CONTEXT_DIR       = Dict{String, ContextPtr}()
const _CONTEXT_TOP       = Ref{ContextPtr}(0)

"""
    reset_contexts!()

Reset all context state. Primarily for testing.
"""
function reset_contexts!()
    empty!(_CONTEXT_DIRECTORY)
    empty!(_CONTEXT_DIR)
    _CONTEXT_TOP[] = 0
    nothing
end

# ──────────────────────────────────────────────────────────────────
# Context string manipulation
# ──────────────────────────────────────────────────────────────────

"""
    compile_context_string(context::Vector{String}) -> String

Combine a vector of context labels into a single canonical
comma-separated string (sorted, deduplicated, stripped).
"""
function compile_context_string(context::Vector{String})
    parts = filter(!isempty, strip.(context))
    isempty(parts) && return ""
    return join(sort!(unique(parts)), ",")
end

"""
    normalize_context_string(ctx::Vector{String}) -> String

Normalize a context vector: sort, deduplicate, join with commas.
Alias for `compile_context_string` matching the Go API.
"""
normalize_context_string(ctx::Vector{String}) = compile_context_string(ctx)

# ──────────────────────────────────────────────────────────────────
# Context registration
# ──────────────────────────────────────────────────────────────────

"""
    register_context!(context::Vector{String}) -> ContextPtr

Register a context (given as a vector of labels) in the directory.
Returns the pointer to the existing or newly created entry.
"""
function register_context!(context::Vector{String})
    compiled = compile_context_string(context)
    isempty(compiled) && return ContextPtr(0)

    if haskey(_CONTEXT_DIR, compiled)
        return _CONTEXT_DIR[compiled]
    end

    _CONTEXT_TOP[] += 1
    ptr = _CONTEXT_TOP[]
    entry = ContextEntry(compiled, ptr)
    push!(_CONTEXT_DIRECTORY, entry)
    _CONTEXT_DIR[compiled] = ptr
    return ptr
end

"""
    try_context(context::Vector{String}) -> ContextPtr

Look up or register a context. Returns 0 for empty contexts.
"""
function try_context(context::Vector{String})
    compiled = compile_context_string(context)
    isempty(compiled) && return ContextPtr(0)

    if haskey(_CONTEXT_DIR, compiled)
        return _CONTEXT_DIR[compiled]
    end

    return register_context!(context)
end

# ──────────────────────────────────────────────────────────────────
# Context lookup
# ──────────────────────────────────────────────────────────────────

"""
    get_context(ptr::ContextPtr) -> String

Retrieve the context string for a given pointer.
Returns "" for pointer 0 or out-of-range pointers.
"""
function get_context(ptr::ContextPtr)
    ptr <= 0 && return ""
    ptr > length(_CONTEXT_DIRECTORY) && return ""
    return _CONTEXT_DIRECTORY[ptr].context
end

"""
    get_context_ptr(context_string::AbstractString) -> ContextPtr

Look up the pointer for a context string. Returns 0 if not found.
"""
function get_context_ptr(context_string::AbstractString)
    return get(_CONTEXT_DIR, String(context_string), ContextPtr(0))
end

"""
    context_directory() -> Vector{ContextEntry}

Return a copy of the current context directory.
"""
context_directory() = copy(_CONTEXT_DIRECTORY)

"""
    merge_context_lists(one::Vector{String}, two::Vector{String}) -> ContextPtr

Merge two context label lists and register the combined context.
"""
function merge_context_lists(one::Vector{String}, two::Vector{String})
    combined = vcat(one, two)
    return register_context!(combined)
end
