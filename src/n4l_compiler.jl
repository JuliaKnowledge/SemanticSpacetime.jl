#=
N4L compiler: transfers parsed N4L results into an SST store.

The N4L parser builds an in-memory NodeDirectory with nodes and links.
The compiler walks that directory and creates corresponding vertices
and edges in an AbstractSSTStore (MemoryStore or SSTConnection).
=#

# ──────────────────────────────────────────────────────────────────
# Compile result
# ──────────────────────────────────────────────────────────────────

"""
    N4LCompileResult

Summary of a compile operation.
"""
struct N4LCompileResult
    nodes_created::Int
    edges_created::Int
    chapters::Vector{String}
    errors::Vector{String}
    warnings::Vector{String}
end

function Base.show(io::IO, r::N4LCompileResult)
    print(io, "N4LCompileResult(nodes=$(r.nodes_created), edges=$(r.edges_created), ",
          "chapters=$(length(r.chapters)), errors=$(length(r.errors)))")
end

# ──────────────────────────────────────────────────────────────────
# Core compiler
# ──────────────────────────────────────────────────────────────────

"""
    compile_n4l!(store::MemoryStore, result::N4LResult) -> N4LCompileResult

Transfer parsed N4L nodes and edges from the parse result's NodeDirectory
into the given store. Returns a summary of what was created.
"""
function compile_n4l!(store::MemoryStore, result::N4LResult)
    nd = result.nd
    errors = copy(result.errors)
    warnings = copy(result.warnings)

    node_map = Dict{NodePtr, Node}()  # parser NodePtr → store Node
    nodes_created = 0
    edges_created = 0
    chapters = Set{String}()

    # Walk all size classes and copy nodes into the store
    for class in [N1GRAM, N2GRAM, N3GRAM, LT128, LT1024, GT1024]
        dir, _ = _get_directory(nd, class)
        for (idx, src_node) in enumerate(dir)
            isempty(src_node.s) && continue
            src_ptr = NodePtr(class, idx)
            chap = isempty(src_node.chap) ? "default" : src_node.chap
            dst_node = mem_vertex!(store, src_node.s, chap)
            node_map[src_ptr] = dst_node
            nodes_created += 1
            if !isempty(chap)
                push!(chapters, chap)
            end
        end
    end

    # Walk all nodes again and copy their incidence (links) into the store
    for class in [N1GRAM, N2GRAM, N3GRAM, LT128, LT1024, GT1024]
        dir, _ = _get_directory(nd, class)
        for (idx, src_node) in enumerate(dir)
            isempty(src_node.s) && continue
            src_ptr = NodePtr(class, idx)
            from_node = get(node_map, src_ptr, nothing)
            from_node === nothing && continue

            for stindex in 1:ST_TOP
                for link in src_node.incidence[stindex]
                    link.arr == 0 && continue  # context-only link, skip
                    to_node = get(node_map, link.dst, nothing)
                    to_node === nothing && continue
                    # Avoid re-creating inverse links (the store does that)
                    inv_ptr = get_inverse_arrow(link.arr)
                    if inv_ptr !== nothing
                        entry = get_arrow_by_ptr(link.arr)
                        inv_entry = get_arrow_by_ptr(inv_ptr)
                        # Skip if this is the inverse direction
                        if entry.stindex > inv_entry.stindex ||
                           (entry.stindex == inv_entry.stindex && link.arr > inv_ptr)
                            continue
                        end
                    end
                    entry = get_arrow_by_ptr(link.arr)
                    ctx_strs = _context_ptr_to_strings(link.ctx)
                    try
                        mem_edge!(store, from_node, entry.short, to_node, ctx_strs, link.wgt)
                        edges_created += 1
                    catch e
                        push!(warnings, "Edge creation failed: $(sprint(showerror, e))")
                    end
                end
            end
        end
    end

    return N4LCompileResult(nodes_created, edges_created, sort!(collect(chapters)),
                            errors, warnings)
end

"""
    _context_ptr_to_strings(ctx_ptr::ContextPtr) -> Vector{String}

Convert a context pointer back to a vector of context label strings.
Returns an empty vector if the context pointer is 0 or not found.
"""
function _context_ptr_to_strings(ctx_ptr::ContextPtr)
    ctx_ptr == 0 && return String[]
    ctx_str = get_context(ctx_ptr)
    isempty(ctx_str) && return String[]
    return [String(strip(s)) for s in split(ctx_str, ',') if !isempty(strip(s))]
end

# ──────────────────────────────────────────────────────────────────
# Convenience wrappers
# ──────────────────────────────────────────────────────────────────

"""
    compile_n4l_file!(store::MemoryStore, filepath::String;
                      config_dir=nothing, verbose=false) -> N4LCompileResult

Parse an N4L file and compile the result into the store.
"""
function compile_n4l_file!(store::MemoryStore, filepath::String;
                           config_dir::Union{String, Nothing}=nothing,
                           verbose::Bool=false)
    result = parse_n4l_file(filepath; config_dir=config_dir, verbose=verbose)
    return compile_n4l!(store, result)
end

"""
    compile_n4l_string!(store::MemoryStore, text::String;
                        config_dir=nothing, verbose=false) -> N4LCompileResult

Parse an N4L string and compile the result into the store.
"""
function compile_n4l_string!(store::MemoryStore, text::String;
                             config_dir::Union{String, Nothing}=nothing,
                             verbose::Bool=false)
    result = parse_n4l(text; config_dir=config_dir, verbose=verbose)
    return compile_n4l!(store, result)
end
