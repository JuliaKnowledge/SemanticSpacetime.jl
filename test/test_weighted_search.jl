@testset "WeightedSearch" begin
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()

    fwd = insert_arrow!("LEADSTO", "then", "leads to next", "+")
    bwd = insert_arrow!("LEADSTO", "prev", "preceded by", "-")
    insert_inverse_arrow!(fwd, bwd)

    @testset "dijkstra_path finds shortest weighted path" begin
        store = MemoryStore()
        # A --1.0--> B --1.0--> D  (total weight 2.0, distance 2.0)
        # A --0.5--> C --2.0--> D  (total weight 2.5, distance 2.5)
        # But Dijkstra uses distance = 1/wgt, so:
        # A->B->D distance = 1/1.0 + 1/1.0 = 2.0
        # A->C->D distance = 1/0.5 + 1/2.0 = 2.5
        # So A->B->D is shorter
        a = mem_vertex!(store, "A", "ch1")
        b = mem_vertex!(store, "B", "ch1")
        c = mem_vertex!(store, "C", "ch1")
        d = mem_vertex!(store, "D", "ch1")

        mem_edge!(store, a, "then", b, String[], 1.0f0)
        mem_edge!(store, b, "then", d, String[], 1.0f0)
        mem_edge!(store, a, "then", c, String[], 0.5f0)
        mem_edge!(store, c, "then", d, String[], 2.0f0)

        path = dijkstra_path(store, a.nptr, d.nptr)
        @test path !== nothing
        @test length(path.nodes) == 3
        @test path.nodes[1] == a.nptr
        @test path.nodes[end] == d.nptr
        # Shortest path is A->B->D (distance 1/1+1/1=2) vs A->C->D (distance 1/0.5+1/2=2.5)
        @test path.nodes[2] == b.nptr
    end

    @testset "dijkstra_path returns nothing for unreachable" begin
        store = MemoryStore()
        a = mem_vertex!(store, "A2", "ch1")
        b = mem_vertex!(store, "B2", "ch1")
        # No edges between them (only inverse links from b->a don't help forward search)
        path = dijkstra_path(store, a.nptr, b.nptr)
        @test path === nothing
    end

    @testset "dijkstra_path same node" begin
        store = MemoryStore()
        a = mem_vertex!(store, "A3", "ch1")
        path = dijkstra_path(store, a.nptr, a.nptr)
        @test path !== nothing
        @test length(path.nodes) == 1
        @test path.total_weight == 0.0
    end

    @testset "rank_by_weight sorts correctly" begin
        p1 = WeightedPath([NodePtr(1,1)], Link[], 3.0)
        p2 = WeightedPath([NodePtr(1,2)], Link[], 1.0)
        p3 = WeightedPath([NodePtr(1,3)], Link[], 5.0)

        # Default: descending (heaviest first)
        ranked = rank_by_weight([p1, p2, p3])
        @test ranked[1].total_weight == 5.0
        @test ranked[2].total_weight == 3.0
        @test ranked[3].total_weight == 1.0

        # Ascending
        ranked_asc = rank_by_weight([p1, p2, p3]; ascending=true)
        @test ranked_asc[1].total_weight == 1.0
        @test ranked_asc[2].total_weight == 3.0
        @test ranked_asc[3].total_weight == 5.0
    end

    @testset "weighted_search respects min_weight" begin
        store = MemoryStore()
        a = mem_vertex!(store, "WA", "ch1")
        b = mem_vertex!(store, "WB", "ch1")
        c = mem_vertex!(store, "WC", "ch1")

        mem_edge!(store, a, "then", b, String[], 0.5f0)
        mem_edge!(store, a, "then", c, String[], 2.0f0)

        # min_weight=0 should find paths to both b and c
        paths_all = weighted_search(store, a.nptr; max_depth=1, min_weight=0.0f0)
        dst_nodes = Set([last(p.nodes) for p in paths_all])
        @test b.nptr ∈ dst_nodes
        @test c.nptr ∈ dst_nodes

        # min_weight=1.0 should only find path to c
        paths_heavy = weighted_search(store, a.nptr; max_depth=1, min_weight=1.0f0)
        dst_heavy = Set([last(p.nodes) for p in paths_heavy])
        @test c.nptr ∈ dst_heavy
        @test b.nptr ∉ dst_heavy
    end

    @testset "weighted_search with max_depth" begin
        store = MemoryStore()
        a = mem_vertex!(store, "DA", "ch1")
        b = mem_vertex!(store, "DB", "ch1")
        c = mem_vertex!(store, "DC", "ch1")

        mem_edge!(store, a, "then", b, String[], 1.0f0)
        mem_edge!(store, b, "then", c, String[], 1.0f0)

        # max_depth=1 should not reach c from a
        paths_shallow = weighted_search(store, a.nptr; max_depth=1, min_weight=0.0f0)
        dst_shallow = Set([last(p.nodes) for p in paths_shallow])
        @test b.nptr ∈ dst_shallow
        @test c.nptr ∉ dst_shallow

        # max_depth=2 should reach c
        paths_deep = weighted_search(store, a.nptr; max_depth=2, min_weight=0.0f0)
        dst_deep = Set([last(p.nodes) for p in paths_deep])
        @test c.nptr ∈ dst_deep
    end

    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()
end
