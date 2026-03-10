@testset "GraphTraversal" begin
    # Reset global state
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()

    # Register arrows
    fwd = insert_arrow!("LEADSTO", "then", "leads to next", "+")
    bwd = insert_arrow!("LEADSTO", "prev", "preceded by", "-")
    insert_inverse_arrow!(fwd, bwd)

    contains_fwd = insert_arrow!("CONTAINS", "has", "contains element", "+")
    contains_bwd = insert_arrow!("CONTAINS", "in", "element of", "-")
    insert_inverse_arrow!(contains_fwd, contains_bwd)

    # ── Adjoint operations ────────────────────────────────────────

    @testset "adjoint_arrows" begin
        result = adjoint_arrows([fwd])
        @test length(result) == 1
        @test result[1] == bwd

        result2 = adjoint_arrows([fwd, contains_fwd])
        @test length(result2) == 2
        @test bwd in result2
        @test contains_bwd in result2

        # Deduplication
        result3 = adjoint_arrows([fwd, fwd])
        @test length(result3) == 1
    end

    @testset "adjoint_sttype" begin
        @test adjoint_sttype([1, 2]) == [-2, -1]
        @test adjoint_sttype([0]) == [0]
        @test adjoint_sttype([-3, -2, -1]) == [1, 2, 3]
        @test adjoint_sttype(Int[]) == Int[]
    end

    @testset "adjoint_link_path" begin
        l1 = Link(fwd, 1.0f0, 0, NodePtr(1, 1))
        l2 = Link(fwd, 1.0f0, 0, NodePtr(1, 2))
        path = [l1, l2]
        adj = adjoint_link_path(path)
        @test length(adj) == 2
        @test adj[1].dst == NodePtr(1, 2)
        @test adj[2].dst == NodePtr(1, 1)
        @test adj[1].arr == bwd
        @test adj[2].arr == bwd

        # Empty path
        @test isempty(adjoint_link_path(Link[]))
    end

    # ── Wave front operations ─────────────────────────────────────

    @testset "wave_front" begin
        l1 = Link(fwd, 1.0f0, 0, NodePtr(1, 1))
        l2 = Link(fwd, 1.0f0, 0, NodePtr(1, 2))
        paths = [[l1], [l2]]
        front = wave_front(paths, 1)
        @test length(front) == 2
        @test NodePtr(1, 1) in front
        @test NodePtr(1, 2) in front

        # Empty paths
        @test isempty(wave_front(Vector{Link}[], 0))
    end

    @testset "nodes_overlap" begin
        left = [NodePtr(1, 1), NodePtr(1, 2), NodePtr(1, 3)]
        right = [NodePtr(1, 2), NodePtr(1, 4), NodePtr(1, 3)]
        result = nodes_overlap(left, right)
        @test haskey(result, 2)  # left[2] == right[1]
        @test 1 in result[2]
        @test haskey(result, 3)  # left[3] == right[3]
        @test 3 in result[3]
        @test !haskey(result, 1)  # NodePtr(1,1) not in right

        # No overlap
        @test isempty(nodes_overlap([NodePtr(1, 1)], [NodePtr(1, 2)]))
    end

    @testset "wave_fronts_overlap" begin
        store = MemoryStore()
        a = mem_vertex!(store, "wa", "ch1")
        b = mem_vertex!(store, "wb", "ch1")
        c = mem_vertex!(store, "wc", "ch1")
        mem_edge!(store, a, "then", b)
        mem_edge!(store, b, "then", c)

        # Left paths: a->b
        l1 = Link(fwd, 1.0f0, 0, b.nptr)
        left_paths = [[l1]]

        # Right paths: c->b (backward, but we express as links with dst=b)
        l2 = Link(bwd, 1.0f0, 0, b.nptr)
        right_paths = [[l2]]

        solutions, loops = wave_fronts_overlap(store, left_paths, right_paths, 1, 1)
        # Both end at b.nptr, so there should be overlap
        @test !isempty(solutions) || !isempty(loops)
    end

    # ── is_dag ────────────────────────────────────────────────────

    @testset "is_dag" begin
        l1 = Link(fwd, 1.0f0, 0, NodePtr(1, 1))
        l2 = Link(fwd, 1.0f0, 0, NodePtr(1, 2))
        l3 = Link(fwd, 1.0f0, 0, NodePtr(1, 1))
        @test is_dag([l1, l2])
        @test !is_dag([l1, l2, l3])
        @test is_dag(Link[])
    end

    # ── left_join / right_complement_join ─────────────────────────

    @testset "left_join" begin
        l1 = Link(fwd, 1.0f0, 0, NodePtr(1, 1))
        l2 = Link(fwd, 1.0f0, 0, NodePtr(1, 2))
        @test length(left_join([l1], [l2])) == 2
        @test left_join(Link[], [l1]) == [l1]
    end

    @testset "right_complement_join" begin
        l1 = Link(fwd, 1.0f0, 0, NodePtr(1, 1))
        l2 = Link(fwd, 1.0f0, 0, NodePtr(1, 2))
        l3 = Link(fwd, 1.0f0, 0, NodePtr(1, 3))
        # Skip first element of adjoint
        result = right_complement_join([l1], [l2, l3])
        @test length(result) == 2
        @test result[1] == l1
        @test result[2] == l3

        # Single element adjoint — nothing appended
        result2 = right_complement_join([l1], [l2])
        @test length(result2) == 1
        @test result2[1] == l1
    end

    # ── Matroid / supernode grouping ──────────────────────────────

    @testset "together! matroid" begin
        matroid = Vector{NodePtr}[]
        n1 = NodePtr(1, 1)
        n2 = NodePtr(1, 2)
        n3 = NodePtr(1, 3)
        n4 = NodePtr(1, 4)

        together!(matroid, n1, n2)
        @test length(matroid) == 1
        @test in_node_set(matroid[1], n1)
        @test in_node_set(matroid[1], n2)

        together!(matroid, n3, n4)
        @test length(matroid) == 2

        # Merge groups
        together!(matroid, n1, n3)
        @test length(matroid) == 1
        @test in_node_set(matroid[1], n1)
        @test in_node_set(matroid[1], n4)
    end

    @testset "idemp_add_nodeptr!" begin
        set = NodePtr[]
        idemp_add_nodeptr!(set, NodePtr(1, 1))
        @test length(set) == 1
        idemp_add_nodeptr!(set, NodePtr(1, 1))
        @test length(set) == 1
        idemp_add_nodeptr!(set, NodePtr(1, 2))
        @test length(set) == 2
    end

    @testset "in_node_set" begin
        list = [NodePtr(1, 1), NodePtr(1, 2)]
        @test in_node_set(list, NodePtr(1, 1))
        @test !in_node_set(list, NodePtr(1, 3))
        @test !in_node_set(NodePtr[], NodePtr(1, 1))
    end

    # ── Constrained cone paths ────────────────────────────────────

    @testset "get_constrained_cone_paths" begin
        store = MemoryStore()
        a = mem_vertex!(store, "ca", "ch1")
        b = mem_vertex!(store, "cb", "ch1")
        c = mem_vertex!(store, "cc", "ch1")
        mem_edge!(store, a, "then", b)
        mem_edge!(store, b, "then", c)
        mem_edge!(store, a, "has", c)

        # All paths from a
        paths, count = get_constrained_cone_paths(store, [a.nptr], 3)
        @test count > 0
        @test !isempty(paths)

        # Filter by arrow
        paths2, count2 = get_constrained_cone_paths(store, [a.nptr], 3;
                                                     arrows=[fwd])
        # Should only have "then" links
        for path in paths2
            for lnk in path
                @test lnk.arr == fwd
            end
        end
    end

    @testset "get_constrained_fwd_links" begin
        store = MemoryStore()
        a = mem_vertex!(store, "fa", "ch1")
        b = mem_vertex!(store, "fb", "ch1")
        c = mem_vertex!(store, "fc", "ch1")
        mem_edge!(store, a, "then", b)
        mem_edge!(store, a, "has", c)

        links = get_constrained_fwd_links(store, [a.nptr])
        @test length(links) == 2

        links2 = get_constrained_fwd_links(store, [a.nptr]; arrows=[fwd])
        @test length(links2) == 1
        @test links2[1].dst == b.nptr
    end

    # ── get_paths_and_symmetries ──────────────────────────────────

    @testset "get_paths_and_symmetries" begin
        store = MemoryStore()
        a = mem_vertex!(store, "pa", "ch1")
        b = mem_vertex!(store, "pb", "ch1")
        c = mem_vertex!(store, "pc", "ch1")
        mem_edge!(store, a, "then", b)
        mem_edge!(store, b, "then", c)

        solutions, loops = get_paths_and_symmetries(store, [a.nptr], [c.nptr];
                                                     maxdepth=5)
        # Should find at least one path from a to c
        @test !isempty(solutions) || !isempty(loops)
    end

    # ── Longest axial path ────────────────────────────────────────

    @testset "get_longest_axial_path" begin
        store = MemoryStore()
        a = mem_vertex!(store, "la", "ch1")
        b = mem_vertex!(store, "lb", "ch1")
        c = mem_vertex!(store, "lc", "ch1")
        d = mem_vertex!(store, "ld", "ch1")
        mem_edge!(store, a, "then", b)
        mem_edge!(store, b, "then", c)
        mem_edge!(store, c, "then", d)
        mem_edge!(store, c, "has", d)

        path = get_longest_axial_path(store, a.nptr, fwd)
        @test length(path) == 3
        @test path[1].dst == b.nptr
        @test path[2].dst == c.nptr
        @test path[3].dst == d.nptr
    end

    @testset "truncate_paths_by_arrow" begin
        l1 = Link(fwd, 1.0f0, 0, NodePtr(1, 1))
        l2 = Link(fwd, 1.0f0, 0, NodePtr(1, 2))
        l3 = Link(contains_fwd, 1.0f0, 0, NodePtr(1, 3))
        l4 = Link(fwd, 1.0f0, 0, NodePtr(1, 4))

        result = truncate_paths_by_arrow([l1, l2, l3, l4], fwd)
        @test length(result) == 2
        @test result[1] == l1
        @test result[2] == l2

        # All match
        @test length(truncate_paths_by_arrow([l1, l2], fwd)) == 2

        # None match
        @test isempty(truncate_paths_by_arrow([l3], fwd))
    end

    # ── Cone paths as links ───────────────────────────────────────

    @testset "get_fwd_paths_as_links" begin
        store = MemoryStore()
        a = mem_vertex!(store, "fp1", "ch1")
        b = mem_vertex!(store, "fp2", "ch1")
        c = mem_vertex!(store, "fp3", "ch1")
        mem_edge!(store, a, "then", b)
        mem_edge!(store, b, "then", c)

        paths, count = get_fwd_paths_as_links(store, a.nptr, 0, 3)
        @test count > 0
        # Should have paths of length 1 (a->b) and 2 (a->b->c)
        lengths = sort([length(p) for p in paths])
        @test 1 in lengths
        @test 2 in lengths
    end

    @testset "get_entire_cone_paths_as_links" begin
        store = MemoryStore()
        a = mem_vertex!(store, "ec1", "ch1")
        b = mem_vertex!(store, "ec2", "ch1")
        c = mem_vertex!(store, "ec3", "ch1")
        mem_edge!(store, a, "then", b)
        mem_edge!(store, b, "then", c)

        fwd_paths, fc = get_entire_cone_paths_as_links(store, "fwd", a.nptr, 3)
        @test fc > 0

        bwd_paths, bc = get_entire_cone_paths_as_links(store, "bwd", c.nptr, 3)
        @test bc > 0

        any_paths, ac = get_entire_cone_paths_as_links(store, "any", b.nptr, 3)
        @test ac > 0
    end

    # Clean up global state
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()
end
