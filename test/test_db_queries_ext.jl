@testset "Extended DB Queries" begin
    @testset "get_arrows_matching_name" begin
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.add_mandatory_arrows!()
        ptrs = get_arrows_matching_name("then")
        @test !isempty(ptrs)
    end

    @testset "get_arrows_matching_name exact" begin
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.add_mandatory_arrows!()
        ptrs = get_arrows_matching_name("!then!")
        @test !isempty(ptrs)
    end

    @testset "get_arrows_matching_name empty" begin
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.add_mandatory_arrows!()
        ptrs = get_arrows_matching_name("")
        @test isempty(ptrs)
    end

    @testset "get_arrows_by_sttype" begin
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.add_mandatory_arrows!()
        # LEADSTO is sttype 1
        result = get_arrows_by_sttype(1)
        @test isa(result, Vector)
    end

    @testset "get_arrow_with_name" begin
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.add_mandatory_arrows!()
        ptr, st = get_arrow_with_name("then")
        @test Int(ptr) > 0
    end

    @testset "get_arrow_with_name empty" begin
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.add_mandatory_arrows!()
        ptr, st = get_arrow_with_name("")
        @test Int(ptr) == 0
    end

    @testset "next_link_arrow" begin
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.add_mandatory_arrows!()
        entry = get_arrow_by_name("then")
        if !isnothing(entry)
            link = Link(entry.ptr, Float32(1.0), ContextPtr(0), NodePtr(1,1))
            result = next_link_arrow(MemoryStore(), [link], [entry.ptr])
            @test !isempty(result)
        end
    end

    @testset "next_link_arrow no match" begin
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.add_mandatory_arrows!()
        entry = get_arrow_by_name("then")
        if !isnothing(entry)
            link = Link(entry.ptr, Float32(1.0), ContextPtr(0), NodePtr(1,1))
            result = next_link_arrow(MemoryStore(), [link], ArrowPtr[])
            @test result == ""
        end
    end

    @testset "get_singleton_by_sttype" begin
        store = MemoryStore()
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.add_mandatory_arrows!()
        n1 = mem_vertex!(store, "source", "ch1")
        n2 = mem_vertex!(store, "middle", "ch1")
        n3 = mem_vertex!(store, "sink", "ch1")
        mem_edge!(store, n1, "then", n2)
        mem_edge!(store, n2, "then", n3)

        srcs, snks = get_singleton_by_sttype(store, [1])
        @test length(srcs) >= 1 || length(snks) >= 1
    end

    @testset "inc_constraint_cone_links" begin
        store = MemoryStore()
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.add_mandatory_arrows!()
        n1 = mem_vertex!(store, "A", "ch1")
        n2 = mem_vertex!(store, "B", "ch1")
        mem_edge!(store, n1, "then", n2)

        entry = get_arrow_by_name("then")
        if !isnothing(entry)
            init_link = Link(entry.ptr, Float32(1.0), ContextPtr(0), n1.nptr)
            cone = [[init_link]]
            result = inc_constraint_cone_links(store, cone; maxdepth=5)
            @test isa(result, Vector{Vector{Link}})
        end
    end

    @testset "already_seen" begin
        cone = Dict(1 => ["hello", "world"], 2 => ["foo"])
        @test already_seen("hello", cone) == true
        @test already_seen("bar", cone) == false
    end

    @testset "get_sequence_containers empty" begin
        store = MemoryStore()
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.add_mandatory_arrows!()
        result = get_sequence_containers(store, NodePtr[], ArrowPtr[])
        @test isempty(result)
    end
end
