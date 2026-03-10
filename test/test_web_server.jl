import JSON3

@testset "Web Types" begin
    # Reset global state
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()

    fwd = insert_arrow!("LEADSTO", "then", "leads to next", "+")
    bwd = insert_arrow!("LEADSTO", "prev", "preceded by", "-")
    insert_inverse_arrow!(fwd, bwd)

    contains_fwd = insert_arrow!("CONTAINS", "has", "contains element", "+")
    contains_bwd = insert_arrow!("CONTAINS", "in", "element of", "-")
    insert_inverse_arrow!(contains_fwd, contains_bwd)

    store = MemoryStore()
    n1 = mem_vertex!(store, "Alpha", "ch1")
    n2 = mem_vertex!(store, "Beta", "ch1")
    n3 = mem_vertex!(store, "Gamma", "ch2")
    mem_edge!(store, n1, "then", n2)
    mem_edge!(store, n2, "then", n3)
    mem_edge!(store, n1, "has", n3)

    @testset "Coords construction" begin
        c = Coords()
        @test c.x == 0.0
        @test c.y == 0.0
        d = coords_to_dict(c)
        @test d["x"] == 0.0
        @test d["r"] == 0.0
    end

    @testset "WebPath construction and serialization" begin
        wp = WebPath(n1.nptr, fwd, 5, 1, "Alpha", "ch1", "", Coords())
        @test wp.name == "Alpha"
        @test wp.nptr == n1.nptr
        d = webpath_to_dict(wp)
        @test d["name"] == "Alpha"
        @test d["nptr"]["class"] == n1.nptr.class
    end

    @testset "NodeEvent construction and serialization" begin
        orbits = get_node_orbit(store, n1.nptr; limit=10)
        ne = json_node_event(store, n1.nptr, Coords(), orbits)
        @test ne.text == "Alpha"
        @test ne.l == length("Alpha")
        @test ne.nptr == n1.nptr
        d = node_event_to_dict(ne)
        @test d["text"] == "Alpha"
        @test haskey(d, "orbits")
    end

    @testset "link_web_paths" begin
        cr = forward_cone(store, n1.nptr; depth=3, limit=10)
        web_paths = link_web_paths(store, cr.paths; limit=10)
        @test !isempty(web_paths)
        for wp_path in web_paths
            for wp in wp_path
                @test wp.nptr != NO_NODE_PTR
            end
        end
    end

    @testset "json_page with empty pagemap" begin
        result = json_page(store, PageMap[])
        @test result["title"] == ""
        @test isempty(result["notes"])
    end

    @testset "WebConePaths construction" begin
        wcp = WebConePaths(n1.nptr, 0, Vector{WebPath}[])
        @test wcp.origin == n1.nptr
        @test wcp.sttype == 0
    end

    @testset "PageView construction" begin
        pv = PageView("Title", "ctx", Vector{WebPath}[])
        @test pv.title == "Title"
        @test pv.context == "ctx"
    end

    @testset "SearchResponse construction" begin
        sr = SearchResponse("orbit", "content", "ambient", "intent", "key")
        @test sr.response == "orbit"
    end

    @testset "package_response" begin
        search = SearchParameters()
        push!(search.names, "test")
        search.chapter = "ch1"
        result = package_response(store, search, "orbit", "some content")
        @test result["response"] == "orbit"
        @test result["content"] == "some content"
        @test result["intent"] == "ch1"
        @test result["key"] == "test"
    end

    @testset "handle_search_dispatch" begin
        # Empty search → stats
        search = SearchParameters()
        result = handle_search_dispatch(store, search, "")
        @test haskey(result, "nodes")

        # Name search → orbit
        search2 = SearchParameters()
        push!(search2.names, "Alpha")
        result2 = handle_search_dispatch(store, search2, "Alpha")
        @test result2["type"] == "orbit"

        # Chapter search
        search3 = SearchParameters()
        search3.chapter = "ch1"
        result3 = handle_search_dispatch(store, search3, "chapter ch1")
        @test haskey(result3, "chapters")

        # Forward cone
        search4 = SearchParameters()
        push!(search4.names, "Alpha")
        search4.orientation = "forward"
        result4 = handle_search_dispatch(store, search4, "forward Alpha")
        @test result4["type"] == "cone"
    end

    # Clean up
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()
end
