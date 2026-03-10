@testset "ETCValidation" begin
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()

    fwd = insert_arrow!("LEADSTO", "then", "leads to next", "+")
    bwd = insert_arrow!("LEADSTO", "prev", "preceded by", "-")
    insert_inverse_arrow!(fwd, bwd)

    contains_fwd = insert_arrow!("CONTAINS", "has", "contains element", "+")
    contains_bwd = insert_arrow!("CONTAINS", "in", "element of", "-")
    insert_inverse_arrow!(contains_fwd, contains_bwd)

    expr_fwd = insert_arrow!("EXPRESS", "expresses", "expresses property", "+")
    expr_bwd = insert_arrow!("EXPRESS", "expressed_by", "expressed by", "-")
    insert_inverse_arrow!(expr_fwd, expr_bwd)

    near_arr = insert_arrow!("NEAR", "like", "is similar to", "+")

    @testset "infer_etc classifies Events" begin
        store = MemoryStore()
        a = mem_vertex!(store, "EventNode", "ch1")
        b = mem_vertex!(store, "NextNode", "ch1")
        mem_edge!(store, a, "then", b)

        etc = infer_etc(a)
        @test etc.e == true
        @test etc.t == false
        @test etc.c == false
    end

    @testset "infer_etc classifies Things via CONTAINS" begin
        store = MemoryStore()
        container = mem_vertex!(store, "Container", "ch1")
        element = mem_vertex!(store, "Element", "ch1")
        mem_edge!(store, container, "has", element)

        etc = infer_etc(container)
        @test etc.t == true
    end

    @testset "infer_etc classifies Concepts via EXPRESS" begin
        store = MemoryStore()
        concept = mem_vertex!(store, "Concept", "ch1")
        prop = mem_vertex!(store, "Property", "ch1")
        mem_edge!(store, concept, "expresses", prop)

        etc = infer_etc(concept)
        @test etc.c == true
        @test etc.t == true
    end

    @testset "show_psi formatting" begin
        @test show_psi(Etc(true, false, false)) == "event,"
        @test show_psi(Etc(false, true, false)) == "thing,"
        @test show_psi(Etc(false, false, true)) == "concept,"
        @test show_psi(Etc(true, true, false)) == "event,thing,"
        @test show_psi(Etc(true, true, true)) == "event,thing,concept,"
        @test show_psi(Etc(false, false, false)) == ""
    end

    @testset "collapse_psi returns message" begin
        store = MemoryStore()
        a = mem_vertex!(store, "TestCollapse", "ch1")
        b = mem_vertex!(store, "TestTarget", "ch1")
        mem_edge!(store, a, "then", b)

        # Find the LEADSTO stindex
        entry = get_arrow_by_name("then")
        etc, msg = collapse_psi(a, entry.stindex)
        @test etc.e == true
        @test occursin("TestCollapse", msg)
        @test occursin("event", msg)
    end

    @testset "validate_etc warns on suspicious patterns" begin
        # Create a node manually classified as Thing but with only LEADSTO links
        store = MemoryStore()
        a = mem_vertex!(store, "SuspiciousThing", "ch1")
        b = mem_vertex!(store, "Target", "ch1")
        mem_edge!(store, a, "then", b)
        a.psi = Etc(false, true, false)  # Manually mark as Thing

        warns = validate_etc(a)
        @test !isempty(warns)
        @test any(w -> occursin("LEADSTO", w), warns)
    end

    @testset "validate_etc no warnings for correct classification" begin
        store = MemoryStore()
        container = mem_vertex!(store, "GoodContainer", "ch1")
        element = mem_vertex!(store, "GoodElement", "ch1")
        mem_edge!(store, container, "has", element)
        container.psi = Etc(false, true, false)  # Correctly a Thing

        warns = validate_etc(container)
        @test isempty(warns)
    end

    @testset "validate_etc warns on Event without LEADSTO" begin
        store = MemoryStore()
        a = mem_vertex!(store, "BadEvent", "ch1")
        b = mem_vertex!(store, "BadTarget", "ch1")
        mem_edge!(store, a, "has", b)  # CONTAINS, not LEADSTO
        a.psi = Etc(true, false, false)  # Marked as Event

        warns = validate_etc(a)
        @test !isempty(warns)
        @test any(w -> occursin("Event", w) && occursin("no LEADSTO", w), warns)
    end

    @testset "validate_graph_types checks all nodes" begin
        store = MemoryStore()
        a = mem_vertex!(store, "GraphNode1", "ch1")
        b = mem_vertex!(store, "GraphNode2", "ch1")
        mem_edge!(store, a, "then", b)
        a.psi = Etc(false, true, false)  # Suspicious: Thing with LEADSTO

        results = validate_graph_types(store)
        @test haskey(results, a.nptr)
        @test !isempty(results[a.nptr])
    end

    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()
end
