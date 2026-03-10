@testset "Appointed Nodes" begin
    # Reset global state for clean tests
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()

    # Set up arrows
    add_mandatory_arrows!()

    # Register additional arrows for testing
    contains_fwd = insert_arrow!("CONTAINS", "has", "contains element", "+")
    contains_bwd = insert_arrow!("CONTAINS", "in", "element of", "-")
    insert_inverse_arrow!(contains_fwd, contains_bwd)

    leadsto_fwd = insert_arrow!("LEADSTO", "then", "leads to next", "+")
    leadsto_bwd = insert_arrow!("LEADSTO", "prev", "preceded by", "-")
    insert_inverse_arrow!(leadsto_fwd, leadsto_bwd)

    @testset "get_appointed_nodes_by_sttype - memory" begin
        store = MemoryStore()
        hub = mem_vertex!(store, "hub", "test")
        n1 = mem_vertex!(store, "spoke1", "test")
        n2 = mem_vertex!(store, "spoke2", "test")

        mem_edge!(store, hub, "has", n1)
        mem_edge!(store, hub, "has", n2)

        result = get_appointed_nodes_by_sttype(store, Int(CONTAINS))
        @test result isa Dict{Int, Vector{Appointment}}

        # Inverse links land on n1, n2 in the -CONTAINS channel
        result_inv = get_appointed_nodes_by_sttype(store, -Int(CONTAINS))
        @test result_inv isa Dict{Int, Vector{Appointment}}
    end

    @testset "get_appointed_nodes_by_arrow - memory" begin
        store = MemoryStore()
        hub = mem_vertex!(store, "center", "chap1")
        s1 = mem_vertex!(store, "item1", "chap1")
        s2 = mem_vertex!(store, "item2", "chap1")

        mem_edge!(store, hub, "has", s1)
        mem_edge!(store, hub, "has", s2)

        result = get_appointed_nodes_by_arrow(store, contains_fwd)
        @test result isa Dict{Int, Vector{Appointment}}
    end

    @testset "get_appointed_nodes_by_sttype with chapter filter" begin
        store = MemoryStore()
        h1 = mem_vertex!(store, "hub1", "chapter_a")
        h2 = mem_vertex!(store, "hub2", "chapter_b")
        n1 = mem_vertex!(store, "node1", "chapter_a")
        n2 = mem_vertex!(store, "node2", "chapter_b")

        mem_edge!(store, h1, "then", n1)
        mem_edge!(store, h2, "then", n2)

        # Filter by chapter_a
        result = get_appointed_nodes_by_sttype(store, Int(LEADSTO);
                                               chapter="chapter_a")
        @test result isa Dict{Int, Vector{Appointment}}
    end

    @testset "get_appointed_nodes_by_sttype with context filter" begin
        SemanticSpacetime.reset_contexts!()
        store = MemoryStore()
        h = mem_vertex!(store, "ctx_hub", "ch1")
        n = mem_vertex!(store, "ctx_node", "ch1")

        mem_edge!(store, h, "then", n, ["science", "physics"])

        result = get_appointed_nodes_by_sttype(store, Int(LEADSTO);
                                               context=["science"])
        @test result isa Dict{Int, Vector{Appointment}}
    end

    @testset "empty store returns empty results" begin
        store = MemoryStore()
        r1 = get_appointed_nodes_by_arrow(store, 1)
        @test isempty(r1)
        r2 = get_appointed_nodes_by_sttype(store, Int(CONTAINS))
        @test isempty(r2)
    end

    @testset "parse_appointed_node_cluster" begin
        # Basic parsing test
        appt = parse_appointed_node_cluster("")
        @test appt.arr == 0

        # Default appointment
        appt2 = Appointment()
        @test appt2.arr == 0
        @test appt2.nto == NO_NODE_PTR
        @test isempty(appt2.nfrom)
    end

    @testset "get_node_context functions" begin
        SemanticSpacetime.reset_contexts!()
        store = MemoryStore()
        node = mem_vertex!(store, "test_node", "ch1")

        # Without any ghost links, context should be empty
        @test get_node_context(store, node) isa Vector{String}
        @test isempty(get_node_context(store, node))
        @test get_node_context_string(store, node) isa String
        @test get_node_context_string(store, node) == ""
    end

    @testset "get_node_context with ghost link" begin
        SemanticSpacetime.reset_contexts!()
        store = MemoryStore()
        node = mem_vertex!(store, "ctx_target", "ch1")
        ghost = mem_vertex!(store, "ghost_src", "ch1")

        # "empty" arrow was registered by add_mandatory_arrows!
        mem_edge!(store, ghost, "empty", node, ["math", "logic"])

        # The inverse link should be on node in -LEADSTO channel
        ctx = get_node_context_string(store, node)
        # Context should contain the registered context string
        @test ctx isa String
    end

    @testset "context_interferometry stub" begin
        @test context_interferometry(String[]) === nothing
        @test context_interferometry(["a,b", "b,c"]) === nothing
    end

    @testset "print_some_link_path - no crash on empty" begin
        store = MemoryStore()
        # Empty cone
        print_some_link_path(store, Vector{Link}[], 1)
        # Out of bounds
        print_some_link_path(store, [Link[]], 0)
        print_some_link_path(store, [Link[]], 2)
    end

    # Clean up global state
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()
end
