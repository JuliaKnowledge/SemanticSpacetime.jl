@testset "visualization" begin
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()
    add_mandatory_arrows!()

    store = MemoryStore()
    a = mem_vertex!(store, "alpha", "ch1")
    b = mem_vertex!(store, "beta", "ch1")
    c = mem_vertex!(store, "gamma", "ch1")
    mem_edge!(store, a, "then", b)
    mem_edge!(store, b, "then", c)

    @testset "to_dot / save_dot" begin
        dot = to_dot(store; title="T")
        @test occursin("digraph", dot)
        @test occursin("->", dot)
        @test occursin("alpha", dot)

        mktempdir() do dir
            f = joinpath(dir, "g.dot")
            save_dot(store, f)
            @test isfile(f)
            @test occursin("digraph", read(f, String))
        end
    end

    @testset "plots render" begin
        fig = plot_graph_summary(store)
        @test fig !== nothing

        heat = plot_adjacency_heatmap(Float32[0 1 0; 0 0 1; 0 0 0];
                                      labels=["a", "b", "c"])
        @test heat !== nothing

        mktempdir() do dir
            p = joinpath(dir, "p.png")
            save_plot(fig, p)
            @test isfile(p)
        end
    end

    @testset "ST_COLORS palette" begin
        @test ST_COLORS isa AbstractDict
        @test !isempty(ST_COLORS)
    end
end
