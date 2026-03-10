#=
PageMap operations for Semantic Spacetime.

Provides in-memory page map storage, retrieval, and chapter
organization utilities.

Ported from SSTorytime/pkg/SSTorytime/SSTorytime.go.
=#

# ──────────────────────────────────────────────────────────────────
# Upload page map event
# ──────────────────────────────────────────────────────────────────

"""
    upload_page_map_event!(store::MemoryStore, pm::PageMap)

Store a page map entry in the in-memory store.
"""
function upload_page_map_event!(store::MemoryStore, pm::PageMap)
    push!(store.page_map, pm)
    nothing
end

# ──────────────────────────────────────────────────────────────────
# Get page map
# ──────────────────────────────────────────────────────────────────

"""
    get_page_map(store::MemoryStore; chapter::String="", context::Vector{String}=String[], page::Int=0) -> Vector{PageMap}

Retrieve page map entries matching filters. If `chapter` is non-empty,
filter by case-insensitive substring match. If `context` is non-empty,
filter by context pointer match. `page` enables pagination (60 per page).
"""
function get_page_map(store::MemoryStore; chapter::String="", context::Vector{String}=String[], page::Int=0)::Vector{PageMap}
    results = PageMap[]
    ctx_ptr = isempty(context) ? 0 : try_context(context)
    hits_per_page = 60

    for pm in store.page_map
        if !isempty(chapter)
            if !occursin(lowercase(chapter), lowercase(pm.chapter))
                continue
            end
        end
        if !isempty(context) && ctx_ptr != 0
            if pm.ctx != ctx_ptr
                continue
            end
        end
        push!(results, pm)
    end

    # Sort by chapter, then line
    sort!(results; by = pm -> (pm.chapter, pm.line))

    # Paginate
    if page > 0
        offset = (page - 1) * hits_per_page
        if offset >= length(results)
            return PageMap[]
        end
        return results[offset+1:min(offset + hits_per_page, length(results))]
    end

    return results
end

# ──────────────────────────────────────────────────────────────────
# Chapters by chapter/context
# ──────────────────────────────────────────────────────────────────

"""
    get_chapters_by_chap_context(store::MemoryStore; chapter::String="any",
                                  context::Vector{String}=String[], limit::Int=100) -> Dict{String,Vector{String}}

Table of contents: chapters grouped with their contexts.
"""
function get_chapters_by_chap_context(store::MemoryStore; chapter::String="any",
                                      context::Vector{String}=String[],
                                      limit::Int=100)::Dict{String,Vector{String}}
    toc = Dict{String,Vector{String}}()
    ctx_ptr = isempty(context) ? 0 : try_context(context)

    for pm in store.page_map
        # Chapter filter
        if chapter != "any" && !isempty(chapter) && chapter != "TableOfContents"
            if !occursin(lowercase(chapter), lowercase(pm.chapter))
                continue
            end
        end

        # Context filter
        if !isempty(context) && ctx_ptr != 0
            if pm.ctx != ctx_ptr
                continue
            end
        end

        chps = split_chapters(pm.chapter)
        for chp in chps
            length(toc) >= limit && return toc

            ctx_str = pm.ctx > 0 ? get_context(pm.ctx) : ""
            if !isempty(ctx_str)
                if !haskey(toc, chp)
                    toc[chp] = String[]
                end
                push!(toc[chp], ctx_str)
            end
        end
    end

    return toc
end

# ──────────────────────────────────────────────────────────────────
# Split chapters
# ──────────────────────────────────────────────────────────────────

"""
    split_chapters(str::AbstractString) -> Vector{String}

Split a chapter string by commas, but only where the comma is not
followed by a space (Go convention: `","` splits, `", "` does not).
"""
function split_chapters(str::AbstractString)::Vector{String}
    runes = collect(str)
    parts = String[]
    current = Char[]

    for i in 1:length(runes)
        if runes[i] == ',' && (i + 1 <= length(runes) && runes[i + 1] != ' ')
            push!(parts, String(current))
            current = Char[]
        else
            push!(current, runes[i])
        end
    end

    push!(parts, String(current))
    return parts
end
