@testset "Inhibition" begin
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()

    fwd = insert_arrow!("LEADSTO", "then", "leads to next", "+")
    bwd = insert_arrow!("LEADSTO", "prev", "preceded by", "-")
    insert_inverse_arrow!(fwd, bwd)

    @testset "parse_inhibition_context basic" begin
        ic = parse_inhibition_context("science,physics NOT biology")
        @test ic.include == ["science", "physics"]
        @test ic.exclude == ["biology"]
    end

    @testset "parse_inhibition_context no exclude" begin
        ic = parse_inhibition_context("math,algebra")
        @test ic.include == ["math", "algebra"]
        @test isempty(ic.exclude)
    end

    @testset "parse_inhibition_context empty" begin
        ic = parse_inhibition_context("")
        @test isempty(ic.include)
        @test isempty(ic.exclude)
    end

    @testset "parse_inhibition_context only exclude" begin
        ic = parse_inhibition_context("NOT junk,spam")
        @test isempty(ic.include)
        @test ic.exclude == ["junk", "spam"]
    end

    @testset "parse_inhibition_context case insensitive NOT" begin
        ic = parse_inhibition_context("A,B not C")
        @test ic.include == ["A", "B"]
        @test ic.exclude == ["C"]
    end

    @testset "matches_inhibition with include/exclude" begin
        ic = InhibitionContext(["science", "physics"], ["biology"])

        @test matches_inhibition("physics,science", ic) == true
        @test matches_inhibition("science,physics,math", ic) == true
        @test matches_inhibition("science,physics,biology", ic) == false
        @test matches_inhibition("science", ic) == false  # missing physics
        @test matches_inhibition("biology", ic) == false
    end

    @testset "matches_inhibition empty include" begin
        ic = InhibitionContext(String[], ["spam"])

        @test matches_inhibition("science", ic) == true
        @test matches_inhibition("spam", ic) == false
        @test matches_inhibition("science,spam", ic) == false
    end

    @testset "matches_inhibition empty both" begin
        ic = InhibitionContext(String[], String[])
        @test matches_inhibition("anything", ic) == true
        @test matches_inhibition("", ic) == true
    end

    @testset "search_with_inhibition filters correctly" begin
        store = MemoryStore()
        a = mem_vertex!(store, "Science lesson", "ch1")
        b = mem_vertex!(store, "Science experiment", "ch1")
        c = mem_vertex!(store, "Science fiction", "ch1")
        target = mem_vertex!(store, "Target", "ch1")

        # Give them different contexts
        mem_edge!(store, a, "then", target, ["science", "physics"])
        mem_edge!(store, b, "then", target, ["science", "biology"])
        mem_edge!(store, c, "then", target, ["fiction"])

        # Search for "Science" with include=science, exclude=biology
        ic = InhibitionContext(["science"], ["biology"])
        results = search_with_inhibition(store, "Science", ic)

        texts = sort([r.s for r in results])
        @test "Science lesson" ∈ texts
        @test "Science experiment" ∉ texts   # has biology context
        @test "Science fiction" ∉ texts       # doesn't have science context
    end

    @testset "search_with_inhibition uncontextualized nodes" begin
        store = MemoryStore()
        a = mem_vertex!(store, "Unlinked node", "ch1")

        # No links, empty include -> should pass
        ic = InhibitionContext(String[], String[])
        results = search_with_inhibition(store, "Unlinked", ic)
        @test length(results) == 1

        # No links, non-empty include -> should not pass
        ic2 = InhibitionContext(["science"], String[])
        results2 = search_with_inhibition(store, "Unlinked", ic2)
        @test isempty(results2)
    end

    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()
end
