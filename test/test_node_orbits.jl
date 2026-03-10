@testset "NodeOrbits" begin
    # Reset global state
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()

    # Register arrows
    fwd = insert_arrow!("LEADSTO", "then", "leads to next", "+")
    bwd = insert_arrow!("LEADSTO", "prev", "preceded by", "-")
    insert_inverse_arrow!(fwd, bwd)

    expr_fwd = insert_arrow!("EXPRESS", "expresses", "has property", "+")
    expr_bwd = insert_arrow!("EXPRESS", "property_of", "is property of", "-")
    insert_inverse_arrow!(expr_fwd, expr_bwd)

    contains_fwd = insert_arrow!("CONTAINS", "has", "contains element", "+")
    contains_bwd = insert_arrow!("CONTAINS", "in", "element of", "-")
    insert_inverse_arrow!(contains_fwd, contains_bwd)

    # ── Node orbits ───────────────────────────────────────────────

    @testset "get_node_orbit basic" begin
        store = MemoryStore()
        a = mem_vertex!(store, "center", "ch1")
        b = mem_vertex!(store, "near1", "ch1")
        c = mem_vertex!(store, "near2", "ch1")
        d = mem_vertex!(store, "prop1", "ch1")

        mem_edge!(store, a, "then", b)
        mem_edge!(store, a, "then", c)
        mem_edge!(store, a, "expresses", d)

        orbits = get_node_orbit(store, a.nptr)
        @test length(orbits) == ST_TOP

        # There should be satellites in some ST channels
        total_satellites = sum(length(o) for o in orbits)
        @test total_satellites > 0
    end

    @testset "get_node_orbit empty" begin
        store = MemoryStore()
        orbits = get_node_orbit(store, NodePtr(1, 999))
        @test length(orbits) == ST_TOP
        @test all(isempty, orbits)
    end

    @testset "get_node_orbit with exclude_vector" begin
        store = MemoryStore()
        a = mem_vertex!(store, "hub", "ch1")
        b = mem_vertex!(store, "spoke1", "ch1")
        c = mem_vertex!(store, "spoke2", "ch1")
        mem_edge!(store, a, "then", b)
        mem_edge!(store, a, "then", c)

        orbits_excl = get_node_orbit(store, a.nptr; exclude_vector="spoke1")
        all_texts = String[]
        for orb_group in orbits_excl
            for orb in orb_group
                push!(all_texts, orb.text)
            end
        end
        @test !("spoke1" in all_texts)
    end

    # ── idemp_add_satellite! ──────────────────────────────────────

    @testset "idemp_add_satellite!" begin
        list = Orbit[]
        already = Set{String}()
        orb1 = Orbit(1, "then", 5, NodePtr(1, 1), "", "test1", Coords(), Coords())
        orb2 = Orbit(1, "then", 5, NodePtr(1, 2), "", "test2", Coords(), Coords())
        orb3 = Orbit(2, "then", 5, NodePtr(1, 3), "", "test1", Coords(), Coords())

        idemp_add_satellite!(list, orb1, already)
        @test length(list) == 1
        # Duplicate text
        idemp_add_satellite!(list, orb3, already)
        @test length(list) == 1
        idemp_add_satellite!(list, orb2, already)
        @test length(list) == 2
    end

    # ── Betweenness centrality (path-based) ───────────────────────

    @testset "tally_path" begin
        store = MemoryStore()
        a = mem_vertex!(store, "ta", "ch1")
        b = mem_vertex!(store, "tb", "ch1")
        c = mem_vertex!(store, "tc", "ch1")

        path = [
            Link(fwd, 1.0f0, 0, a.nptr),
            Link(fwd, 1.0f0, 0, b.nptr),
            Link(fwd, 1.0f0, 0, c.nptr),
        ]

        between = Dict{String,Int}()
        result = tally_path(store, path, between)
        @test result["ta"] == 1
        @test result["tb"] == 1
        @test result["tc"] == 1

        # Tally again — counts should double
        result2 = tally_path(store, path, result)
        @test result2["ta"] == 2
    end

    @testset "betweenness_centrality - path based" begin
        store = MemoryStore()
        a = mem_vertex!(store, "ba", "ch1")
        b = mem_vertex!(store, "bb", "ch1")
        c = mem_vertex!(store, "bc", "ch1")

        # Two solutions, both pass through b
        solutions = [
            [Link(fwd, 1.0f0, 0, a.nptr), Link(fwd, 1.0f0, 0, b.nptr)],
            [Link(fwd, 1.0f0, 0, b.nptr), Link(fwd, 1.0f0, 0, c.nptr)],
        ]

        ranking = betweenness_centrality(store, solutions)
        @test !isempty(ranking)
        # "bb" appears in both paths, so should rank first
        @test ranking[1] == "bb"
    end

    # ── Betweenness centrality (adjacency-based) ──────────────────

    @testset "betweenness_centrality - adjacency" begin
        adj = AdjacencyMatrix()
        n1 = NodePtr(1, 1)
        n2 = NodePtr(1, 2)
        n3 = NodePtr(1, 3)
        n4 = NodePtr(1, 4)

        # Linear: n1 -> n2 -> n3 -> n4
        add_edge!(adj, n1, n2)
        add_edge!(adj, n2, n3)
        add_edge!(adj, n3, n4)

        bc = SemanticSpacetime.betweenness_centrality(adj)
        @test haskey(bc, n2)
        @test haskey(bc, n3)
        # n2 and n3 are intermediate and should have positive centrality
        @test bc[n2] > 0
        @test bc[n3] > 0
        # Endpoints should have zero centrality
        @test bc[n1] == 0.0
        @test bc[n4] == 0.0
    end

    # ── SuperNodes ────────────────────────────────────────────────

    @testset "super_nodes_by_conic_path" begin
        # Two solutions with common depth structure
        l1a = Link(fwd, 1.0f0, 0, NodePtr(1, 1))
        l1b = Link(fwd, 1.0f0, 0, NodePtr(1, 3))

        l2a = Link(fwd, 1.0f0, 0, NodePtr(1, 2))
        l2b = Link(fwd, 1.0f0, 0, NodePtr(1, 3))

        solutions = [[l1a, l1b], [l2a, l2b]]
        matroid = super_nodes_by_conic_path(solutions, 2)

        # At depth 1: NodePtr(1,1) and NodePtr(1,2) are different — grouped
        @test !isempty(matroid)
        # Check that (1,1) and (1,2) are in the same group
        found = false
        for group in matroid
            if in_node_set(group, NodePtr(1, 1)) && in_node_set(group, NodePtr(1, 2))
                found = true
                break
            end
        end
        @test found
    end

    @testset "super_nodes" begin
        store = MemoryStore()
        a = mem_vertex!(store, "sn_a", "ch1")
        b = mem_vertex!(store, "sn_b", "ch1")
        c = mem_vertex!(store, "sn_c", "ch1")

        solutions = [
            [Link(fwd, 1.0f0, 0, a.nptr), Link(fwd, 1.0f0, 0, c.nptr)],
            [Link(fwd, 1.0f0, 0, b.nptr), Link(fwd, 1.0f0, 0, c.nptr)],
        ]

        names = super_nodes(store, solutions, 2)
        @test !isempty(names)
        # Should group sn_a and sn_b (depth 1, different nodes)
        @test any(n -> occursin("sn_a", n) && occursin("sn_b", n), names)
    end

    @testset "get_path_transverse_super_nodes" begin
        store = MemoryStore()
        a = mem_vertex!(store, "ts_a", "ch1")
        b = mem_vertex!(store, "ts_b", "ch1")
        shared = mem_vertex!(store, "ts_shared", "ch1")

        solutions = [
            [Link(fwd, 1.0f0, 0, a.nptr), Link(fwd, 1.0f0, 0, shared.nptr)],
            [Link(fwd, 1.0f0, 0, b.nptr), Link(fwd, 1.0f0, 0, shared.nptr)],
        ]

        transverse = get_path_transverse_super_nodes(store, solutions, 3)
        # shared appears in both paths — should be in transverse
        found_shared = false
        for group in transverse
            if in_node_set(group, shared.nptr)
                found_shared = true
                break
            end
        end
        @test found_shared
    end

    # ── build_adjacency from MemoryStore ──────────────────────────

    @testset "build_adjacency from MemoryStore" begin
        store = MemoryStore()
        a = mem_vertex!(store, "adj_a", "ch1")
        b = mem_vertex!(store, "adj_b", "ch1")
        c = mem_vertex!(store, "adj_c", "ch1")
        mem_edge!(store, a, "then", b)
        mem_edge!(store, b, "then", c)

        adj = build_adjacency(store)
        @test length(adj.nodes) >= 3
        @test haskey(adj.outgoing, a.nptr)
    end

    # Clean up global state
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()
end
