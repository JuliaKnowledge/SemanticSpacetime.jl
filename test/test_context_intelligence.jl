@testset "Context Intelligence" begin
    # Initialize STM state
    SemanticSpacetime.reset_stm!()

    @testset "context_intent_analysis" begin
        spectrum = Dict("foo" => 1, "bar" => 2, "baz" => 5, "qux" => 10)
        clusters = ["foo, bar, baz", "bar, baz, qux", "foo, qux"]

        intentional, ambient = context_intent_analysis(spectrum, clusters)
        # foo (1) and bar (2) should be intentional (< 3)
        @test "foo" in intentional
        @test "bar" in intentional
    end

    @testset "diff_clusters" begin
        shared, different = diff_clusters("alpha, beta, gamma", "beta, gamma, delta")
        @test occursin("beta", shared)
        @test occursin("gamma", shared)
        @test occursin("alpha", different) || occursin("delta", different)
    end

    @testset "overlap_matrix" begin
        m1 = Dict("a" => 1, "b" => 1, "c" => 1)
        m2 = Dict("b" => 1, "c" => 1, "d" => 1)
        shared, different = overlap_matrix(m1, m2)
        @test occursin("b", shared)
        @test occursin("c", shared)
        @test occursin("a", different) || occursin("d", different)
    end

    @testset "get_context_token_frequencies" begin
        fraglist = ["alpha, beta, gamma", "beta, gamma, delta", "alpha, delta"]
        freqs = get_context_token_frequencies(fraglist)
        @test freqs["beta"] == 2
        @test freqs["alpha"] == 2
        @test freqs["gamma"] == 2
        @test freqs["delta"] == 2
    end

    @testset "STM token tracking" begin
        SemanticSpacetime.reset_stm!()
        now = round(Int64, time())

        # First time seeing token → goes to intentional
        commit_context_token!("hello", now, "key1")
        @test haskey(SemanticSpacetime.STM_INT_FRAG[], "hello")
        @test !haskey(SemanticSpacetime.STM_AMB_FRAG[], "hello")

        # Second time → moves to ambient
        commit_context_token!("hello", now + 10, "key2")
        @test !haskey(SemanticSpacetime.STM_INT_FRAG[], "hello")
        @test haskey(SemanticSpacetime.STM_AMB_FRAG[], "hello")
        @test SemanticSpacetime.STM_AMB_FRAG[]["hello"].freq == 2.0
    end

    @testset "intersect_context_parts" begin
        clusters = ["a, b, c", "b, c, d", "a, b, c"]
        count, unique_list, adj = intersect_context_parts(clusters)
        @test count >= 1
        @test length(unique_list) >= 1
    end

    @testset "add_context" begin
        SemanticSpacetime.reset_stm!()
        store = MemoryStore()
        now = round(Int64, time())

        ctx = add_context(store, "ambient", "key1", now, ["token1", "token2"])
        @test occursin("token1", ctx)
        @test occursin("token2", ctx)
    end
end
