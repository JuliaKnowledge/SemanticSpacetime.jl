#=
HTTP server for Semantic Spacetime.

Provides a JSON API for querying the SST graph, inspired by the
Go HTTP server in SSTorytime/src/server/http_server.go.

Uses Genie.jl for request handling and JSON3.jl for serialization.
Works with both MemoryStore and SSTConnection backends.

Endpoints mirror the Go /searchN4L handler dispatch plus REST-style
API routes for individual operations.
=#

import HTTP
import Sockets
import JSON3
using Genie, Genie.Router, Genie.Renderer.Json, Genie.Requests

# ──────────────────────────────────────────────────────────────────
# Server state
# ──────────────────────────────────────────────────────────────────

"""
    SSTServer

Module-level server state, holding a reference to the backing store
and configuration used by all route handlers.
"""
mutable struct SSTServer
    store::AbstractSSTStore
    verbose::Bool
    resources_dir::String
end

const SERVER_STATE = Ref{Union{Nothing,SSTServer}}(nothing)

# ──────────────────────────────────────────────────────────────────
# JSON serialization helpers (used by both old compat and new routes)
# ──────────────────────────────────────────────────────────────────

function _node_to_dict(node::Node)
    Dict{String,Any}(
        "text"    => node.s,
        "length"  => node.l,
        "chapter" => node.chap,
        "nptr"    => _nptr_to_dict(node.nptr),
        "seq"     => node.seq,
    )
end

function _nptr_to_dict(nptr::NodePtr)
    Dict{String,Any}("class" => nptr.class, "cptr" => nptr.cptr)
end

function _link_to_dict(lnk::Link)
    Dict{String,Any}(
        "arrow"   => lnk.arr,
        "weight"  => lnk.wgt,
        "context" => lnk.ctx,
        "dst"     => _nptr_to_dict(lnk.dst),
    )
end

function _cone_to_dict(cr::ConeResult)
    Dict{String,Any}(
        "root"       => _nptr_to_dict(cr.root),
        "paths"      => [[_link_to_dict(l) for l in p] for p in cr.paths],
        "supernodes" => [_nptr_to_dict(n) for n in cr.supernodes],
    )
end

# ──────────────────────────────────────────────────────────────────
# Store-agnostic query helpers
# ──────────────────────────────────────────────────────────────────

function _search(store::MemoryStore, query::String)
    results = mem_search_text(store, query)
    return [_node_to_dict(n) for n in results]
end

function _search(store::SSTConnection, query::String)
    results = search_text(store, query)
    return [_node_to_dict(n) for n in results]
end

function _get_node(store::MemoryStore, nptr::NodePtr)
    node = mem_get_node(store, nptr)
    isnothing(node) && return nothing
    return _node_to_dict(node)
end

function _get_node(store::SSTConnection, nptr::NodePtr)
    node = get_db_node_by_nodeptr(store, nptr)
    isempty(node.s) && return nothing
    return _node_to_dict(node)
end

function _get_links(store::MemoryStore, nptr::NodePtr)
    node = mem_get_node(store, nptr)
    isnothing(node) && return nothing
    channels = Dict{String,Any}()
    for stidx in 1:ST_TOP
        links = node.incidence[stidx]
        isempty(links) && continue
        channels[ST_COLUMN_NAMES[stidx]] = [_link_to_dict(l) for l in links]
    end
    return channels
end

function _get_links(store::SSTConnection, nptr::NodePtr)
    node = get_db_node_by_nodeptr(store, nptr)
    isempty(node.s) && return nothing
    channels = Dict{String,Any}()
    for stidx in 1:ST_TOP
        links = node.incidence[stidx]
        isempty(links) && continue
        channels[ST_COLUMN_NAMES[stidx]] = [_link_to_dict(l) for l in links]
    end
    return channels
end

function _graph_report(store::MemoryStore)
    adj = AdjacencyMatrix()
    for (nptr, node) in store.nodes
        push!(adj.nodes, nptr)
        for stidx in 1:ST_TOP
            for lnk in node.incidence[stidx]
                add_edge!(adj, nptr, lnk.dst, Float64(lnk.wgt))
            end
        end
    end
    n_links = sum(length(nbrs) for (_, nbrs) in adj.outgoing; init=0)
    sources = find_sources(adj)
    sinks = find_sinks(adj)
    evc = eigenvector_centrality(adj)
    top_evc = if !isempty(evc)
        sorted = sort(collect(evc); by=last, rev=true)
        [Dict("node" => _nptr_to_dict(n), "centrality" => v)
         for (n, v) in sorted[1:min(5, length(sorted))]]
    else
        []
    end
    Dict{String,Any}(
        "nodes"     => length(adj.nodes),
        "links"     => n_links,
        "sources"   => length(sources),
        "sinks"     => length(sinks),
        "top_centrality" => top_evc,
    )
end

function _graph_report(store::SSTConnection)
    adj = build_adjacency(store)
    n_links = sum(length(nbrs) for (_, nbrs) in adj.outgoing; init=0)
    sources = find_sources(adj)
    sinks = find_sinks(adj)
    evc = eigenvector_centrality(adj)
    top_evc = if !isempty(evc)
        sorted = sort(collect(evc); by=last, rev=true)
        [Dict("node" => _nptr_to_dict(n), "centrality" => v)
         for (n, v) in sorted[1:min(5, length(sorted))]]
    else
        []
    end
    Dict{String,Any}(
        "nodes"     => length(adj.nodes),
        "links"     => n_links,
        "sources"   => length(sources),
        "sinks"     => length(sinks),
        "top_centrality" => top_evc,
    )
end

function _guess_content_type(path::String)
    ext = lowercase(splitext(path)[2])
    ext == ".html" && return "text/html"
    ext == ".css"  && return "text/css"
    ext == ".js"   && return "application/javascript"
    ext == ".json" && return "application/json"
    ext == ".png"  && return "image/png"
    ext == ".svg"  && return "image/svg+xml"
    return "application/octet-stream"
end

# ──────────────────────────────────────────────────────────────────
# Genie error-response helper
# ──────────────────────────────────────────────────────────────────

"""Return an HTTP error response with JSON body from a Genie handler."""
function _genie_error(msg::String; status::Int=400)
    return HTTP.Response(status,
        ["Content-Type" => "application/json",
         "Access-Control-Allow-Origin" => "*"],
        body=JSON3.write(Dict("error" => msg)))
end

"""Return an HTTP JSON success response with CORS headers."""
function _genie_json(data; status::Int=200)
    return HTTP.Response(status,
        ["Content-Type" => "application/json",
         "Access-Control-Allow-Origin" => "*"],
        body=JSON3.write(data))
end

# ──────────────────────────────────────────────────────────────────
# Search dispatch (mirrors Go HandleSearch)
# ──────────────────────────────────────────────────────────────────

"""
    handle_search_dispatch(store, search, line) -> Dict

Dispatch a parsed SearchParameters to the appropriate handler,
mirroring the Go HandleSearch logic.
"""
function handle_search_dispatch(store::AbstractSSTStore, search::SearchParameters, line::String)
    # 1. Stats (empty search)
    if isempty(search.names) && isempty(search.chapter) && isempty(search.context) &&
       search.from_node == NO_NODE_PTR && search.to_node == NO_NODE_PTR && !search.seq_only
        return _graph_report(store)
    end

    # 2. Context + Chapter only → chapters
    if isempty(search.names) && !isempty(search.chapter) && search.from_node == NO_NODE_PTR
        return _handle_chapters(store, search)
    end

    # 3. From + To → path solving
    if search.from_node != NO_NODE_PTR && search.to_node != NO_NODE_PTR
        return _handle_path_solve(store, search)
    end

    # 4. Sequence/story mode
    if search.seq_only && !isempty(search.names)
        return _handle_stories(store, search)
    end

    # 5. Name with orientation → causal cone
    if !isempty(search.names) && !isempty(search.orientation)
        return _handle_causal_cone(store, search)
    end

    # 6. Arrow-based filtering
    if !isempty(search.arrows)
        return _handle_matching_arrows(store, search)
    end

    # 7. Name only → orbit / node search
    if !isempty(search.names)
        return _handle_orbit(store, search)
    end

    return Dict{String,Any}("error" => "No matching handler for search")
end

function _handle_chapters(store::MemoryStore, search::SearchParameters)
    chapters = mem_get_chapters(store)
    if !isempty(search.chapter) && search.chapter != "%%"
        chapters = filter(c -> occursin(lowercase(search.chapter), lowercase(c)), chapters)
    end
    Dict{String,Any}("chapters" => chapters)
end

function _handle_orbit(store::MemoryStore, search::SearchParameters)
    results = Dict{String,Any}[]
    for name in search.names
        nodes = name == "%%" ? collect(values(store.nodes)) : mem_search_text(store, name)
        for node in nodes
            orbits = get_node_orbit(store, node.nptr; limit=search.limit)
            orbits = set_orbit_coords(Coords(), orbits)
            ne = json_node_event(store, node.nptr, Coords(), orbits)
            push!(results, node_event_to_dict(ne))
        end
    end
    Dict{String,Any}("type" => "orbit", "results" => results)
end

function _handle_causal_cone(store::MemoryStore, search::SearchParameters)
    all_results = Dict{String,Any}[]
    for name in search.names
        nodes = mem_search_text(store, name)
        for node in nodes
            depth = search.depth > 0 ? search.depth : 5
            cr = if search.orientation == "backward"
                backward_cone(store, node.nptr; depth, limit=search.limit)
            else
                forward_cone(store, node.nptr; depth, limit=search.limit)
            end
            web_paths = link_web_paths(store, cr.paths; limit=search.limit)
            wcp = Dict{String,Any}(
                "origin" => _nptr_to_dict(cr.root),
                "sttype" => 0,
                "paths"  => [[webpath_to_dict(wp) for wp in p] for p in web_paths],
            )
            push!(all_results, wcp)
        end
    end
    Dict{String,Any}("type" => "cone", "results" => all_results)
end

function _handle_path_solve(store::MemoryStore, search::SearchParameters)
    depth = search.depth > 0 ? search.depth : 10
    pr = find_paths(store, search.from_node, search.to_node; max_depth=depth)
    Dict{String,Any}(
        "type"  => "paths",
        "paths" => [[_nptr_to_dict(n) for n in p] for p in pr.paths],
        "loops" => [[_nptr_to_dict(n) for n in p] for p in pr.loops],
    )
end

function _handle_stories(store::MemoryStore, search::SearchParameters)
    results = Dict{String,Any}[]
    for name in search.names
        nodes = mem_search_text(store, name)
        for node in nodes
            if node.seq
                depth = search.depth > 0 ? search.depth : 5
                cr = forward_cone(store, node.nptr; depth, limit=search.limit)
                web_paths = link_web_paths(store, cr.paths; limit=search.limit)
                push!(results, Dict{String,Any}(
                    "start" => _node_to_dict(node),
                    "paths" => [[webpath_to_dict(wp) for wp in p] for p in web_paths],
                ))
            end
        end
    end
    Dict{String,Any}("type" => "stories", "results" => results)
end

function _handle_matching_arrows(store::MemoryStore, search::SearchParameters)
    sttypes = get_sttype_from_arrows(search.arrows)
    # Find nodes matching name criteria, then filter by arrow
    all_nodes = if isempty(search.names)
        collect(values(store.nodes))
    else
        vcat([mem_search_text(store, n) for n in search.names]...)
    end
    matched = select_stories_by_arrow(store, [n.nptr for n in all_nodes],
                                      search.arrows, sttypes, search.limit)
    results = [_nptr_to_dict(n) for n in matched]
    Dict{String,Any}("type" => "arrows", "results" => results)
end

# Fallback dispatch methods for SSTConnection (delegate to existing DB functions)
function _handle_chapters(store::SSTConnection, search::SearchParameters)
    Dict{String,Any}("chapters" => String[])
end

function _handle_orbit(store::SSTConnection, search::SearchParameters)
    results = Dict{String,Any}[]
    for name in search.names
        nodes = search_text(store, name)
        for node in nodes
            push!(results, _node_to_dict(node))
        end
    end
    Dict{String,Any}("type" => "orbit", "results" => results)
end

function _handle_causal_cone(store::SSTConnection, search::SearchParameters)
    all_results = Dict{String,Any}[]
    for name in search.names
        nodes = search_text(store, name)
        for node in nodes
            depth = search.depth > 0 ? search.depth : 5
            cr = if search.orientation == "backward"
                backward_cone(store, node.nptr; depth, limit=search.limit)
            else
                forward_cone(store, node.nptr; depth, limit=search.limit)
            end
            push!(all_results, _cone_to_dict(cr))
        end
    end
    Dict{String,Any}("type" => "cone", "results" => all_results)
end

function _handle_path_solve(store::SSTConnection, search::SearchParameters)
    depth = search.depth > 0 ? search.depth : 10
    pr = find_paths(store, search.from_node, search.to_node; max_depth=depth)
    Dict{String,Any}(
        "type"  => "paths",
        "paths" => [[_nptr_to_dict(n) for n in p] for p in pr.paths],
        "loops" => [[_nptr_to_dict(n) for n in p] for p in pr.loops],
    )
end

function _handle_stories(store::SSTConnection, search::SearchParameters)
    Dict{String,Any}("type" => "stories", "results" => Dict{String,Any}[])
end

function _handle_matching_arrows(store::SSTConnection, search::SearchParameters)
    Dict{String,Any}("type" => "arrows", "results" => Dict{String,Any}[])
end

# ──────────────────────────────────────────────────────────────────
# Route registration
# ──────────────────────────────────────────────────────────────────

"""
    register_routes!()

Register all Genie routes for the SST web server. Requires
SERVER_STATE[] to be set before any request is handled.
"""
function register_routes!()
    # Health check
    route("/health") do
        _genie_json(Dict("status" => "ok"))
    end

    # Main search endpoint (matching Go /searchN4L)
    route("/searchN4L", method=GET) do
        _handle_searchN4L()
    end

    route("/searchN4L", method=POST, named=:searchN4L_post) do
        _handle_searchN4L()
    end

    # REST API endpoints

    # GET /api/search?q=...
    route("/api/search") do
        srv = SERVER_STATE[]
        isnothing(srv) && return _genie_error("Server not initialized"; status=500)
        q = getpayload(:q, "")
        isempty(q) && return _genie_error("Missing query parameter 'q'")
        results = _search(srv.store, q)
        _genie_json(Dict("query" => q, "results" => results))
    end

    # GET /search?q=...  (backward compatible with old HTTP.jl server)
    route("/search") do
        srv = SERVER_STATE[]
        isnothing(srv) && return _genie_error("Server not initialized"; status=500)
        q = getpayload(:q, "")
        isempty(q) && return _genie_error("Missing query parameter 'q'")
        results = _search(srv.store, q)
        _genie_json(Dict("query" => q, "results" => results))
    end

    # GET /node/:class/:cptr
    route("/node/:class/:cptr") do
        srv = SERVER_STATE[]
        isnothing(srv) && return _genie_error("Server not initialized"; status=500)
        cls = tryparse(Int, Genie.Router.params(:class))
        cptr = tryparse(Int, Genie.Router.params(:cptr))
        (isnothing(cls) || isnothing(cptr)) &&
            return _genie_error("Invalid node pointer parameters")
        nptr = NodePtr(cls, cptr)
        result = _get_node(srv.store, nptr)
        isnothing(result) && return _genie_error("Node not found"; status=404)
        _genie_json(result)
    end

    # GET /links/:class/:cptr
    route("/links/:class/:cptr") do
        srv = SERVER_STATE[]
        isnothing(srv) && return _genie_error("Server not initialized"; status=500)
        cls = tryparse(Int, Genie.Router.params(:class))
        cptr = tryparse(Int, Genie.Router.params(:cptr))
        (isnothing(cls) || isnothing(cptr)) &&
            return _genie_error("Invalid node pointer parameters")
        nptr = NodePtr(cls, cptr)
        result = _get_links(srv.store, nptr)
        isnothing(result) && return _genie_error("Node not found"; status=404)
        _genie_json(result)
    end

    # GET /api/orbit/:class/:cptr
    route("/api/orbit/:class/:cptr") do
        srv = SERVER_STATE[]
        isnothing(srv) && return _genie_error("Server not initialized"; status=500)
        cls = tryparse(Int, Genie.Router.params(:class))
        cptr = tryparse(Int, Genie.Router.params(:cptr))
        (isnothing(cls) || isnothing(cptr)) &&
            return _genie_error("Invalid node pointer parameters")
        nptr = NodePtr(cls, cptr)
        lim = something(tryparse(Int, getpayload(:limit, "100")), 100)
        orbits = get_node_orbit(srv.store, nptr; limit=lim)
        orbits = set_orbit_coords(Coords(), orbits)
        ne = json_node_event(srv.store, nptr, Coords(), orbits)
        _genie_json(node_event_to_dict(ne))
    end

    # GET /api/cone/:class/:cptr?direction=forward&depth=5&limit=100
    route("/api/cone/:class/:cptr") do
        srv = SERVER_STATE[]
        isnothing(srv) && return _genie_error("Server not initialized"; status=500)
        cls = tryparse(Int, Genie.Router.params(:class))
        cptr = tryparse(Int, Genie.Router.params(:cptr))
        (isnothing(cls) || isnothing(cptr)) &&
            return _genie_error("Invalid node pointer parameters")
        nptr = NodePtr(cls, cptr)
        direction = getpayload(:direction, "forward")
        depth = something(tryparse(Int, getpayload(:depth, "5")), 5)
        lim = something(tryparse(Int, getpayload(:limit, "100")), 100)
        cr = if direction == "backward"
            backward_cone(srv.store, nptr; depth, limit=lim)
        else
            forward_cone(srv.store, nptr; depth, limit=lim)
        end
        web_paths = link_web_paths(srv.store, cr.paths; limit=lim)
        _genie_json(Dict{String,Any}(
            "origin" => _nptr_to_dict(cr.root),
            "sttype" => 0,
            "paths"  => [[webpath_to_dict(wp) for wp in p] for p in web_paths],
            "supernodes" => [_nptr_to_dict(n) for n in cr.supernodes],
        ))
    end

    # GET /cone/:class/:cptr  (backward compatible)
    route("/cone/:class/:cptr") do
        srv = SERVER_STATE[]
        isnothing(srv) && return _genie_error("Server not initialized"; status=500)
        cls = tryparse(Int, Genie.Router.params(:class))
        cptr = tryparse(Int, Genie.Router.params(:cptr))
        (isnothing(cls) || isnothing(cptr)) &&
            return _genie_error("Invalid node pointer parameters")
        nptr = NodePtr(cls, cptr)
        direction = getpayload(:direction, "forward")
        depth = something(tryparse(Int, getpayload(:depth, "5")), 5)
        lim = something(tryparse(Int, getpayload(:limit, "100")), 100)
        cr = if direction == "backward"
            backward_cone(srv.store, nptr; depth, limit=lim)
        else
            forward_cone(srv.store, nptr; depth, limit=lim)
        end
        _genie_json(_cone_to_dict(cr))
    end

    # GET /api/paths?from_class=X&from_cptr=Y&to_class=X&to_cptr=Y
    route("/api/paths") do
        srv = SERVER_STATE[]
        isnothing(srv) && return _genie_error("Server not initialized"; status=500)
        fc = tryparse(Int, getpayload(:from_class, ""))
        fp = tryparse(Int, getpayload(:from_cptr, ""))
        tc = tryparse(Int, getpayload(:to_class, ""))
        tp = tryparse(Int, getpayload(:to_cptr, ""))
        (isnothing(fc) || isnothing(fp) || isnothing(tc) || isnothing(tp)) &&
            return _genie_error("Missing or invalid from/to parameters")
        from_nptr = NodePtr(fc, fp)
        to_nptr = NodePtr(tc, tp)
        depth = something(tryparse(Int, getpayload(:depth, "10")), 10)
        pr = find_paths(srv.store, from_nptr, to_nptr; max_depth=depth)
        _genie_json(Dict{String,Any}(
            "paths" => [[_nptr_to_dict(n) for n in p] for p in pr.paths],
            "loops" => [[_nptr_to_dict(n) for n in p] for p in pr.loops],
        ))
    end

    # GET /api/chapters
    route("/api/chapters") do
        srv = SERVER_STATE[]
        isnothing(srv) && return _genie_error("Server not initialized"; status=500)
        store = srv.store
        chapters = if store isa MemoryStore
            mem_get_chapters(store)
        else
            String[]
        end
        _genie_json(Dict("chapters" => chapters))
    end

    # GET /api/contexts
    route("/api/contexts") do
        _genie_json(Dict("contexts" => [
            Dict("ptr" => e.ptr, "context" => e.context) for e in context_directory()
        ]))
    end

    # GET /api/stats (alias for /graph)
    route("/api/stats") do
        srv = SERVER_STATE[]
        isnothing(srv) && return _genie_error("Server not initialized"; status=500)
        _genie_json(_graph_report(srv.store))
    end

    # GET /graph (backward compatible)
    route("/graph") do
        srv = SERVER_STATE[]
        isnothing(srv) && return _genie_error("Server not initialized"; status=500)
        _genie_json(_graph_report(srv.store))
    end

    # GET /api/pagemap?chapter=X&page=1
    route("/api/pagemap") do
        srv = SERVER_STATE[]
        isnothing(srv) && return _genie_error("Server not initialized"; status=500)
        store = srv.store
        chapter = getpayload(:chapter, "")
        if store isa MemoryStore
            maplines = filter(pm -> isempty(chapter) ||
                occursin(lowercase(chapter), lowercase(pm.chapter)),
                store.page_map)
            _genie_json(json_page(store, maplines))
        else
            _genie_json(Dict("title" => "", "context" => "", "notes" => []))
        end
    end

    # GET /api/stories?name=X
    route("/api/stories") do
        srv = SERVER_STATE[]
        isnothing(srv) && return _genie_error("Server not initialized"; status=500)
        name = getpayload(:name, "")
        search = SearchParameters()
        !isempty(name) && push!(search.names, name)
        search.seq_only = true
        if !isempty(search.names)
            result = _handle_stories(srv.store, search)
        else
            result = Dict{String,Any}("type" => "stories", "results" => [])
        end
        _genie_json(result)
    end

    nothing
end

# ──────────────────────────────────────────────────────────────────
# /searchN4L handler
# ──────────────────────────────────────────────────────────────────

function _handle_searchN4L()
    srv = SERVER_STATE[]
    isnothing(srv) && return _genie_error("Server not initialized"; status=500)
    store = srv.store

    # Accept query from either GET params or POST body
    name = getpayload(:name, "")
    if isempty(name)
        name = getpayload(:q, "")
    end
    isempty(name) && return _genie_json(Dict{String,Any}(
        "type" => "stats", "results" => _graph_report(store)))

    search = decode_search_field(name)
    result = handle_search_dispatch(store, search, name)
    _genie_json(result)
end

# ──────────────────────────────────────────────────────────────────
# Server entry point
# ──────────────────────────────────────────────────────────────────

"""
    serve(store::AbstractSSTStore; port::Int=8080, host::String="127.0.0.1",
          verbose::Bool=true, resources::String="/tmp") -> Any

Start a Genie-based HTTP server exposing the SST graph via a JSON API.

# Endpoints (backward compatible)
- `GET /health` — health check (`{"status":"ok"}`)
- `GET /search?q=<query>` — text search across nodes
- `GET /node/:class/:cptr` — get node details by NodePtr
- `GET /links/:class/:cptr` — get links for a node
- `GET /cone/:class/:cptr?direction=forward&depth=5&limit=100` — cone search
- `GET /graph` — graph summary (node/link counts, centrality)

# New endpoints (Go parity)
- `GET|POST /searchN4L?name=<query>` — unified search dispatch
- `GET /api/search?q=<query>` — text search
- `GET /api/orbit/:class/:cptr` — node orbit with neighbour rings
- `GET /api/cone/:class/:cptr` — causal cone as WebPath traces
- `GET /api/paths?from_class=&from_cptr=&to_class=&to_cptr=` — path solving
- `GET /api/chapters` — list chapters
- `GET /api/contexts` — list contexts
- `GET /api/stats` — graph statistics
- `GET /api/pagemap?chapter=X` — page-map view
- `GET /api/stories?name=X` — story/sequence following

# Arguments
- `store`: any `AbstractSSTStore` (MemoryStore or SSTConnection)
- `port`: TCP port to listen on (default 8080)
- `host`: host address (default "127.0.0.1")
- `verbose`: print startup message
- `resources`: directory for resources (default "/tmp")

# Returns
A server handle. Call `stop_server()` to shut down.

# Example
```julia
store = MemoryStore()
serve(store; port=9090)
# ... server is running ...
stop_server()
```
"""
function serve(store::AbstractSSTStore; port::Int=8080, host::String="127.0.0.1",
               verbose::Bool=true, resources::String="/tmp")
    SERVER_STATE[] = SSTServer(store, verbose, resources)

    Genie.config.run_as_server = true

    # Clear any previously registered routes
    empty!(Genie.Router.routes())

    register_routes!()
    register_ui_routes!()

    try
        server = Genie.up(port, host; open_browser=false, async=true,
                          verbose=verbose)
        verbose && @info "SST Genie server listening" port host
        return server
    catch e
        @error "Failed to start SST server" exception=e
        SERVER_STATE[] = nothing
        rethrow(e)
    end
end

"""
    stop_server()

Shut down the running Genie server and clear the server state.
"""
function stop_server()
    try
        Genie.down()
    catch e
        @warn "Error stopping Genie server" exception=e
    end
    SERVER_STATE[] = nothing
    nothing
end

# ──────────────────────────────────────────────────────────────────
# Web UI routes — serve static files and enhanced API for the frontend
# ──────────────────────────────────────────────────────────────────

const _PUBLIC_DIR = joinpath(@__DIR__, "public")

function _serve_static(filename::String; content_type::String="text/html")
    filepath = joinpath(_PUBLIC_DIR, filename)
    if isfile(filepath)
        content = read(filepath, String)
        return HTTP.Response(200,
            ["Content-Type" => content_type,
             "Cache-Control" => "no-cache"],
            body=content)
    end
    HTTP.Response(404, ["Content-Type" => "text/plain"], body="Not found")
end

"""
    register_ui_routes!()

Register routes for the web UI: static file serving and enhanced API
endpoints that return rich node/link data for the frontend.
"""
function register_ui_routes!()
    # Serve the main UI page
    route("/") do
        _serve_static("index.html"; content_type="text/html")
    end

    route("/style.css") do
        _serve_static("style.css"; content_type="text/css")
    end

    # Enhanced /api/chapters — include node counts per chapter
    route("/api/chapters/detailed") do
        srv = SERVER_STATE[]
        isnothing(srv) && return _genie_error("Server not initialized"; status=500)
        store = srv.store
        if store isa MemoryStore
            chap_counts = Dict{String,Int}()
            for (_, node) in store.nodes
                chap_counts[node.chap] = get(chap_counts, node.chap, 0) + 1
            end
            chapters = [Dict("name" => ch, "count" => cnt) for (ch, cnt) in
                        sort(collect(chap_counts), by=x -> -x.second)]
            _genie_json(chapters)
        else
            _genie_json([])
        end
    end

    # GET /api/chapter/nodes?name=... — list nodes in a specific chapter
    route("/api/chapter/nodes") do
        srv = SERVER_STATE[]
        isnothing(srv) && return _genie_error("Server not initialized"; status=500)
        name = getpayload(:name, "")
        isempty(name) && return _genie_error("Missing chapter name")
        store = srv.store
        if store isa MemoryStore
            results = [_node_to_dict(node) for (_, node) in store.nodes
                       if node.chap == name]
            _genie_json(Dict("query" => name, "results" => results))
        else
            _genie_json(Dict("query" => name, "results" => []))
        end
    end

    # Enhanced /links — returns rich link data with destination node text
    route("/api/links/:class/:cptr") do
        srv = SERVER_STATE[]
        isnothing(srv) && return _genie_error("Server not initialized"; status=500)
        cls = tryparse(Int, Genie.Router.params(:class))
        cptr = tryparse(Int, Genie.Router.params(:cptr))
        (isnothing(cls) || isnothing(cptr)) &&
            return _genie_error("Invalid node pointer parameters")
        nptr = NodePtr(cls, cptr)
        store = srv.store
        if store isa MemoryStore
            node = mem_get_node(store, nptr)
            isnothing(node) && return _genie_error("Node not found"; status=404)
            links = Dict{String,Any}[]
            for (stidx, bucket) in enumerate(node.incidence)
                st = index_to_sttype(stidx)
                for lnk in bucket
                    dst_node = mem_get_node(store, lnk.dst)
                    dst_text = dst_node !== nothing ? dst_node.s : ""
                    dst_chap = dst_node !== nothing ? dst_node.chap : ""
                    arrow_entry = get_arrow_by_ptr(lnk.arr)
                    arrow_name = arrow_entry !== nothing ? arrow_entry.short : "?"
                    push!(links, Dict{String,Any}(
                        "arrow" => lnk.arr,
                        "arrow_name" => arrow_name,
                        "sttype" => Int(st),
                        "weight" => lnk.wgt,
                        "context" => lnk.ctx,
                        "dst" => _nptr_to_dict(lnk.dst),
                        "dst_text" => first(split(dst_text, '\n')),
                        "dst_chapter" => dst_chap,
                    ))
                end
            end
            _genie_json(Dict("links" => links, "count" => length(links)))
        else
            _genie_json(Dict("links" => [], "count" => 0))
        end
    end

    # Enhanced orbit — returns satellite data structured for the UI canvas
    route("/api/orbit/ui/:class/:cptr") do
        srv = SERVER_STATE[]
        isnothing(srv) && return _genie_error("Server not initialized"; status=500)
        cls = tryparse(Int, Genie.Router.params(:class))
        cptr = tryparse(Int, Genie.Router.params(:cptr))
        (isnothing(cls) || isnothing(cptr)) &&
            return _genie_error("Invalid node pointer parameters")
        nptr = NodePtr(cls, cptr)
        store = srv.store
        if store isa MemoryStore
            node = mem_get_node(store, nptr)
            isnothing(node) && return _genie_error("Node not found"; status=404)
            center_text = first(split(node.s, '\n'))

            satellites = Dict{String,Any}()
            st_names = ["near", "leadsto", "contains", "express"]
            # NEAR=index 4, -LEADSTO=3, LEADSTO=5, -CONTAINS=2, CONTAINS=6, -EXPRESS=1, EXPRESS=7
            st_pairs = [(4,), (3, 5), (2, 6), (1, 7)]  # near, leadsto±, contains±, express±

            for (i, indices) in enumerate(st_pairs)
                sat_nodes = Dict{String,Any}[]
                seen = Set{NodePtr}()
                for idx in indices
                    idx < 1 || idx > length(node.incidence) && continue
                    for lnk in node.incidence[idx]
                        lnk.dst in seen && continue
                        push!(seen, lnk.dst)
                        dst = mem_get_node(store, lnk.dst)
                        dst === nothing && continue
                        push!(sat_nodes, Dict{String,Any}(
                            "text" => first(split(dst.s, '\n')),
                            "chapter" => dst.chap,
                            "nptr" => _nptr_to_dict(lnk.dst),
                        ))
                    end
                end
                satellites[st_names[i]] = sat_nodes
            end

            _genie_json(Dict{String,Any}(
                "center_text" => center_text,
                "center_chapter" => node.chap,
                "center_nptr" => _nptr_to_dict(nptr),
                "satellites" => satellites,
            ))
        else
            _genie_json(Dict{String,Any}("satellites" => Dict()))
        end
    end

    nothing
end
