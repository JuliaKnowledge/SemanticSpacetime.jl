#=
Web interface types and JSON serialization for Semantic Spacetime.

Provides types and conversion functions for rendering SST graph data
as JSON for the web UI. Mirrors the Go web types from
SSTorytime/src/server/http_server.go.

The core visual types (Coords, WebPath, Orbit, NodeEvent, Story,
LastSeen) are defined in types.jl. This file provides:
  - WebConePaths, PageView, SearchResponse structs
  - JSON serialization helpers for building web API responses
=#

# ──────────────────────────────────────────────────────────────────
# Additional web response types
# ──────────────────────────────────────────────────────────────────

"""
    WebConePaths

JSON-serializable response for causal cone queries, containing the
origin node, its ST type, and a nested vector of WebPath traces.
"""
struct WebConePaths
    origin::NodePtr
    sttype::Int
    paths::Vector{Vector{WebPath}}
end

"""
    PageView

JSON-serializable response for page-map / notes display, containing
a title, context string, and note lines as WebPath vectors.
"""
struct PageView
    title::String
    context::String
    notes::Vector{Vector{WebPath}}
end

"""
    SearchResponse

JSON-serializable wrapper for search results, carrying the response
type, content, ambient context, intent, and search key.
"""
struct SearchResponse
    response::String
    content::String
    ambient::String
    intent::String
    key::String
end

# ──────────────────────────────────────────────────────────────────
# JSON serialization helpers
# ──────────────────────────────────────────────────────────────────

"""
    coords_to_dict(c::Coords) -> Dict

Convert a Coords struct to a JSON-serializable dictionary.
"""
function coords_to_dict(c::Coords)
    Dict{String,Any}("x" => c.x, "y" => c.y, "z" => c.z,
                      "r" => c.r, "lat" => c.lat, "lon" => c.lon)
end

"""
    webpath_to_dict(wp::WebPath) -> Dict

Convert a WebPath struct to a JSON-serializable dictionary.
"""
function webpath_to_dict(wp::WebPath)
    Dict{String,Any}(
        "name"    => wp.name,
        "nptr"    => Dict("class" => wp.nptr.class, "cptr" => wp.nptr.cptr),
        "arr"     => wp.arr,
        "stindex" => wp.stindex,
        "chp"     => wp.chp,
        "line"    => wp.line,
        "ctx"     => wp.ctx,
        "xyz"     => coords_to_dict(wp.xyz),
    )
end

"""
    orbit_to_dict(o::Orbit) -> Dict

Convert an Orbit struct to a JSON-serializable dictionary.
"""
function orbit_to_dict(o::Orbit)
    Dict{String,Any}(
        "radius"  => o.radius,
        "arrow"   => o.arrow,
        "stindex" => o.stindex,
        "dst"     => Dict("class" => o.dst.class, "cptr" => o.dst.cptr),
        "ctx"     => o.ctx,
        "text"    => o.text,
        "xyz"     => coords_to_dict(o.xyz),
        "ooo"     => coords_to_dict(o.ooo),
    )
end

"""
    node_event_to_dict(ne::NodeEvent) -> Dict

Convert a NodeEvent struct to a JSON-serializable dictionary.
"""
function node_event_to_dict(ne::NodeEvent)
    Dict{String,Any}(
        "text"    => ne.text,
        "l"       => ne.l,
        "chap"    => ne.chap,
        "context" => ne.context,
        "nptr"    => Dict("class" => ne.nptr.class, "cptr" => ne.nptr.cptr),
        "xyz"     => coords_to_dict(ne.xyz),
        "orbits"  => [[orbit_to_dict(o) for o in ring] for ring in ne.orbits],
    )
end

"""
    json_node_event(store::AbstractSSTStore, nptr::NodePtr, xyz::Coords,
                    orbits::Vector{Vector{Orbit}}) -> NodeEvent

Build a NodeEvent from a node pointer by looking up the node data
in the store and combining it with the supplied coordinates and orbits.
"""
function json_node_event(store::MemoryStore, nptr::NodePtr, xyz::Coords,
                         orbits::Vector{Vector{Orbit}})
    node = mem_get_node(store, nptr)
    if isnothing(node)
        return NodeEvent("", 0, "", "", nptr, xyz, orbits)
    end
    return NodeEvent(node.s, node.l, node.chap, "", nptr, xyz, orbits)
end

"""
    link_web_paths(store::MemoryStore, cone::Vector{Vector{Link}};
                   chapter::String="", context::Vector{String}=String[],
                   limit::Int=100) -> Vector{Vector{WebPath}}

Convert a vector of cone link-paths to WebPath format, resolving
node names, arrow types, and context strings from the store.
"""
function link_web_paths(store::MemoryStore, cone::Vector{Vector{Link}};
                        chapter::String="", context::Vector{String}=String[],
                        limit::Int=100)
    result = Vector{WebPath}[]
    count = 0

    for path in cone
        count >= limit && break
        wp_path = WebPath[]
        for (i, lnk) in enumerate(path)
            dst_node = mem_get_node(store, lnk.dst)
            name = isnothing(dst_node) ? "" : dst_node.s
            chp = isnothing(dst_node) ? "" : dst_node.chap
            ctx_str = get_context(lnk.ctx)
            stidx = try
                entry = get_arrow_by_ptr(lnk.arr)
                entry.stindex
            catch
                0
            end
            wp = WebPath(lnk.dst, lnk.arr, stidx, i, name, chp, ctx_str, Coords())
            push!(wp_path, wp)
        end
        push!(result, wp_path)
        count += 1
    end

    return result
end

"""
    json_page(store::MemoryStore, maplines::Vector{PageMap}) -> Dict

Build a PageView-like dictionary from page map lines for JSON rendering.
"""
function json_page(store::MemoryStore, maplines::Vector{PageMap})
    title = isempty(maplines) ? "" : maplines[1].chapter
    ctx_str = ""
    notes = Vector{WebPath}[]

    for pm in maplines
        wp_line = WebPath[]
        for (i, lnk) in enumerate(pm.path)
            dst_node = mem_get_node(store, lnk.dst)
            name = isnothing(dst_node) ? "" : dst_node.s
            chp = isnothing(dst_node) ? "" : dst_node.chap
            ctx_s = get_context(lnk.ctx)
            stidx = try
                entry = get_arrow_by_ptr(lnk.arr)
                entry.stindex
            catch
                0
            end
            wp = WebPath(lnk.dst, lnk.arr, stidx, pm.line, name, chp, ctx_s, Coords())
            push!(wp_line, wp)
        end
        push!(notes, wp_line)
        if isempty(ctx_str) && pm.ctx > 0
            ctx_str = get_context(pm.ctx)
        end
    end

    return Dict{String,Any}(
        "title"   => title,
        "context" => ctx_str,
        "notes"   => [[webpath_to_dict(wp) for wp in line] for line in notes],
    )
end

"""
    package_response(store::AbstractSSTStore, search::SearchParameters,
                     response_type::String, content::String) -> Dict

Wrap a search result with ambient context metadata, mirroring
the Go PackageResponse function.
"""
function package_response(store::AbstractSSTStore, search::SearchParameters,
                          response_type::String, content::String)
    ambient = isempty(search.context) ? "" : join(search.context, ", ")
    key = isempty(search.names) ? "" : join(search.names, " ")
    return Dict{String,Any}(
        "response" => response_type,
        "content"  => content,
        "ambient"  => ambient,
        "intent"   => search.chapter,
        "key"      => key,
    )
end
