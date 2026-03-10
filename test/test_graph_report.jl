@testset "Graph Report" begin

    @testset "AdjacencyMatrix construction" begin
        adj = SemanticSpacetime.AdjacencyMatrix()
        @test isempty(adj.nodes)
        @test isempty(adj.outgoing)
        @test isempty(adj.incoming)
    end

    @testset "add_edge!" begin
        adj = SemanticSpacetime.AdjacencyMatrix()
        a = NodePtr(1, 1)
        b = NodePtr(1, 2)
        SemanticSpacetime.add_edge!(adj, a, b, 1.0)

        @test length(adj.nodes) == 2
        @test a in adj.nodes
        @test b in adj.nodes
        @test adj.outgoing[a][b] == 1.0
        @test adj.incoming[b][a] == 1.0
    end

    # Build a known graph:
    #   A -> B -> C -> D
    #        B -> E
    # A is a source, D and E are sinks
    function make_linear_graph()
        adj = SemanticSpacetime.AdjacencyMatrix()
        a = NodePtr(1, 1)
        b = NodePtr(1, 2)
        c = NodePtr(1, 3)
        d = NodePtr(1, 4)
        e = NodePtr(1, 5)
        SemanticSpacetime.add_edge!(adj, a, b, 1.0)
        SemanticSpacetime.add_edge!(adj, b, c, 1.0)
        SemanticSpacetime.add_edge!(adj, c, d, 1.0)
        SemanticSpacetime.add_edge!(adj, b, e, 1.0)
        return adj, a, b, c, d, e
    end

    @testset "find_sources" begin
        adj, a, b, c, d, e = make_linear_graph()
        sources = find_sources(adj)
        @test length(sources) == 1
        @test a in sources
        # b, c, d, e should not be sources
        @test !(b in sources)
        @test !(d in sources)
    end

    @testset "find_sinks" begin
        adj, a, b, c, d, e = make_linear_graph()
        sinks = find_sinks(adj)
        @test length(sinks) == 2
        @test d in sinks
        @test e in sinks
        @test !(a in sinks)
        @test !(b in sinks)
    end

    @testset "detect_loops - acyclic" begin
        adj, _, _, _, _, _ = make_linear_graph()
        cycles = detect_loops(adj)
        @test isempty(cycles)
    end

    @testset "detect_loops - with cycle" begin
        # Build A -> B -> C -> A (a 3-cycle)
        adj = SemanticSpacetime.AdjacencyMatrix()
        a = NodePtr(1, 1)
        b = NodePtr(1, 2)
        c = NodePtr(1, 3)
        SemanticSpacetime.add_edge!(adj, a, b, 1.0)
        SemanticSpacetime.add_edge!(adj, b, c, 1.0)
        SemanticSpacetime.add_edge!(adj, c, a, 1.0)

        cycles = detect_loops(adj)
        @test length(cycles) == 1
        @test length(cycles[1]) == 3
        # All three nodes should be in the cycle
        @test Set(cycles[1]) == Set([a, b, c])
    end

    @testset "detect_loops - self loop" begin
        adj = SemanticSpacetime.AdjacencyMatrix()
        a = NodePtr(1, 1)
        SemanticSpacetime.add_edge!(adj, a, a, 1.0)

        cycles = detect_loops(adj)
        @test length(cycles) == 1
        @test cycles[1] == [a]
    end

    @testset "eigenvector_centrality" begin
        # Star graph: center B connected to A, C, D, E
        adj = SemanticSpacetime.AdjacencyMatrix()
        a = NodePtr(1, 1)
        b = NodePtr(1, 2)
        c = NodePtr(1, 3)
        d = NodePtr(1, 4)
        e = NodePtr(1, 5)
        # Symmetric star around b
        for x in [a, c, d, e]
            SemanticSpacetime.add_edge!(adj, b, x, 1.0)
            SemanticSpacetime.add_edge!(adj, x, b, 1.0)
        end

        evc = eigenvector_centrality(adj)
        @test length(evc) == 5
        # Center node should have highest centrality
        @test evc[b] >= evc[a]
        @test evc[b] >= evc[c]
        # The maximum should be 1.0 (normalized)
        @test maximum(values(evc)) ≈ 1.0
        # Peripheral nodes should have equal centrality
        @test evc[a] ≈ evc[c] atol=1e-4
        @test evc[a] ≈ evc[d] atol=1e-4
        @test evc[a] ≈ evc[e] atol=1e-4
    end

    @testset "eigenvector_centrality - empty graph" begin
        adj = SemanticSpacetime.AdjacencyMatrix()
        evc = eigenvector_centrality(adj)
        @test isempty(evc)
    end

    @testset "symmetrize" begin
        # Directed: A -> B -> C
        adj = SemanticSpacetime.AdjacencyMatrix()
        a = NodePtr(1, 1)
        b = NodePtr(1, 2)
        c = NodePtr(1, 3)
        SemanticSpacetime.add_edge!(adj, a, b, 1.0)
        SemanticSpacetime.add_edge!(adj, b, c, 1.0)

        sym = symmetrize(adj)

        # Should have same nodes
        @test length(sym.nodes) == 3

        # Original had 2 directed links; symmetric should have edges in both directions
        # A->B, B->A, B->C, C->B = 4 directed edges
        n_links = sum(length(nbrs) for (_, nbrs) in sym.outgoing; init=0)
        @test n_links == 4

        # Both directions should exist
        @test haskey(sym.outgoing, a) && haskey(sym.outgoing[a], b)
        @test haskey(sym.outgoing, b) && haskey(sym.outgoing[b], a)
        @test haskey(sym.outgoing, b) && haskey(sym.outgoing[b], c)
        @test haskey(sym.outgoing, c) && haskey(sym.outgoing[c], b)

        # A and C should not be directly connected
        @test !haskey(get(sym.outgoing, a, Dict{NodePtr,Float64}()), c)
    end

    @testset "graph_summary" begin
        adj, _, _, _, _, _ = make_linear_graph()
        summary = graph_summary(adj)
        @test occursin("Nodes:   5", summary)
        @test occursin("Links:   4", summary)
        @test occursin("Sources: 1", summary)
        @test occursin("Sinks:   2", summary)
        @test occursin("Top centrality:", summary)
    end
end
