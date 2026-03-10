#=
N4L standalone validation and summary tools.

Provides utilities for validating N4L text and printing human-readable
summaries without requiring a database connection.
=#

# ──────────────────────────────────────────────────────────────────
# Validation
# ──────────────────────────────────────────────────────────────────

"""
    N4LValidationResult

Result of validating N4L input without compiling to a store.
"""
struct N4LValidationResult
    valid::Bool
    errors::Vector{String}
    warnings::Vector{String}
    node_count::Int
    link_count::Int
    chapters::Vector{String}
end

function Base.show(io::IO, r::N4LValidationResult)
    status = r.valid ? "VALID" : "INVALID"
    print(io, "N4LValidation($(status), nodes=$(r.node_count), links=$(r.link_count), ",
          "errors=$(length(r.errors)), warnings=$(length(r.warnings)))")
end

"""
    validate_n4l(text::String; config_dir=nothing, verbose=false) -> N4LValidationResult

Parse N4L text and report validation results without creating a store.
"""
function validate_n4l(text::String;
                      config_dir::Union{String, Nothing}=nothing,
                      verbose::Bool=false)
    result = parse_n4l(text; config_dir=config_dir, verbose=verbose)
    return _validation_from_result(result)
end

"""
    validate_n4l_file(filepath::String; config_dir=nothing, verbose=false) -> N4LValidationResult

Parse an N4L file and report validation results without creating a store.
"""
function validate_n4l_file(filepath::String;
                           config_dir::Union{String, Nothing}=nothing,
                           verbose::Bool=false)
    result = parse_n4l_file(filepath; config_dir=config_dir, verbose=verbose)
    return _validation_from_result(result)
end

function _validation_from_result(result::N4LResult)
    nd = result.nd
    n_nodes = 0
    n_links = 0
    chapters = Set{String}()

    for class in [N1GRAM, N2GRAM, N3GRAM, LT128, LT1024, GT1024]
        dir, _ = _get_directory(nd, class)
        for node in dir
            isempty(node.s) && continue
            n_nodes += 1
            if !isempty(node.chap)
                push!(chapters, node.chap)
            end
            for stindex in 1:ST_TOP
                n_links += length(node.incidence[stindex])
            end
        end
    end

    N4LValidationResult(
        !has_errors(result),
        copy(result.errors),
        copy(result.warnings),
        n_nodes,
        n_links,
        sort!(collect(chapters)),
    )
end

# ──────────────────────────────────────────────────────────────────
# Summary output
# ──────────────────────────────────────────────────────────────────

"""
    n4l_summary(result::N4LResult; io::IO=stdout)

Print a human-readable summary of the parsed N4L result.
"""
function n4l_summary(result::N4LResult; io::IO=stdout)
    nd = result.nd

    n_nodes = 0
    link_counts = zeros(Int, 4)  # NEAR, LEADSTO, CONTAINS, EXPRESS
    chapters = Set{String}()
    nodes_by_chapter = Dict{String, Int}()

    for class in [N1GRAM, N2GRAM, N3GRAM, LT128, LT1024, GT1024]
        dir, _ = _get_directory(nd, class)
        for node in dir
            isempty(node.s) && continue
            n_nodes += 1
            chap = isempty(node.chap) ? "(no chapter)" : node.chap
            push!(chapters, chap)
            nodes_by_chapter[chap] = get(nodes_by_chapter, chap, 0) + 1

            for stindex in 1:ST_TOP
                for link in node.incidence[stindex]
                    st = abs(index_to_sttype(stindex))
                    if 0 <= st <= 3
                        link_counts[st + 1] += 1
                    end
                end
            end
        end
    end

    st_names = ["NEAR", "LEADSTO", "CONTAINS", "EXPRESS"]
    total_links = sum(link_counts)

    println(io, "─────────────────────────────────────")
    println(io, "N4L Summary")
    println(io, "─────────────────────────────────────")
    println(io, "Total nodes:    $n_nodes")
    println(io, "Total links:    $total_links")
    for (i, name) in enumerate(st_names)
        link_counts[i] > 0 && println(io, "  $name: $(link_counts[i])")
    end
    println(io, "Chapters:       $(length(chapters))")
    for chap in sort!(collect(chapters))
        cnt = get(nodes_by_chapter, chap, 0)
        println(io, "  \"$chap\": $cnt nodes")
    end
    if has_errors(result)
        println(io, "Errors:         $(length(result.errors))")
        for e in result.errors
            println(io, "  ✗ $e")
        end
    end
    if has_warnings(result)
        println(io, "Warnings:       $(length(result.warnings))")
        for w in result.warnings
            println(io, "  ⚠ $w")
        end
    end
    println(io, "─────────────────────────────────────")
    nothing
end

"""
    n4l_summary(cr::N4LCompileResult; io::IO=stdout)

Print a human-readable summary of a compile result.
"""
function n4l_summary(cr::N4LCompileResult; io::IO=stdout)
    println(io, "─────────────────────────────────────")
    println(io, "N4L Compile Summary")
    println(io, "─────────────────────────────────────")
    println(io, "Nodes created:  $(cr.nodes_created)")
    println(io, "Edges created:  $(cr.edges_created)")
    println(io, "Chapters:       $(length(cr.chapters))")
    for chap in cr.chapters
        println(io, "  \"$chap\"")
    end
    if !isempty(cr.errors)
        println(io, "Errors:         $(length(cr.errors))")
        for e in cr.errors
            println(io, "  ✗ $e")
        end
    end
    if !isempty(cr.warnings)
        println(io, "Warnings:       $(length(cr.warnings))")
        for w in cr.warnings
            println(io, "  ⚠ $w")
        end
    end
    println(io, "─────────────────────────────────────")
    nothing
end
