@testset "PathSolve" begin
    # Reset global state
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()

    # Register arrows
    fwd = insert_arrow!("LEADSTO", "then", "leads to next", "+")
    bwd = insert_arrow!("LEADSTO", "prev", "preceded by", "-")
    insert_inverse_arrow!(fwd, bwd)

    @testset "PathResult construction" begin
        pr = SemanticSpacetime.PathResult()
        @test isempty(pr.paths)
        @test isempty(pr.loops)
    end

    @testset "find_paths - linear chain" begin
        store = MemoryStore()
        a = mem_vertex!(store, "P1", "ch1")
        b = mem_vertex!(store, "P2", "ch1")
        c = mem_vertex!(store, "P3", "ch1")
        mem_edge!(store, a, "then", b)
        mem_edge!(store, b, "then", c)

        result = find_paths(store, a.nptr, c.nptr; max_depth=5)
        @test length(result.paths) == 1
        @test isempty(result.loops)
        # Path should be [a, b, c]
        @test result.paths[1] == [a.nptr, b.nptr, c.nptr]
    end

    @testset "find_paths - no path" begin
        store = MemoryStore()
        a = mem_vertex!(store, "island1", "ch1")
        b = mem_vertex!(store, "island2", "ch1")
        # No edge between them

        result = find_paths(store, a.nptr, b.nptr; max_depth=5)
        @test isempty(result.paths)
        @test isempty(result.loops)
    end

    @testset "find_paths - direct edge" begin
        store = MemoryStore()
        a = mem_vertex!(store, "start", "ch1")
        b = mem_vertex!(store, "end", "ch1")
        mem_edge!(store, a, "then", b)

        result = find_paths(store, a.nptr, b.nptr; max_depth=5)
        @test length(result.paths) == 1
        @test result.paths[1] == [a.nptr, b.nptr]
    end

    @testset "find_paths - multiple paths (diamond)" begin
        store = MemoryStore()
        a = mem_vertex!(store, "d_top", "ch1")
        b = mem_vertex!(store, "d_left", "ch1")
        c = mem_vertex!(store, "d_right", "ch1")
        d = mem_vertex!(store, "d_bottom", "ch1")
        mem_edge!(store, a, "then", b)
        mem_edge!(store, a, "then", c)
        mem_edge!(store, b, "then", d)
        mem_edge!(store, c, "then", d)

        result = find_paths(store, a.nptr, d.nptr; max_depth=5)
        @test length(result.paths) == 2
        @test isempty(result.loops)

        # Both paths should start with a and end with d
        for path in result.paths
            @test first(path) == a.nptr
            @test last(path) == d.nptr
            @test length(path) == 3  # a -> (b or c) -> d
        end

        # One through b, one through c
        midpoints = Set([path[2] for path in result.paths])
        @test b.nptr in midpoints
        @test c.nptr in midpoints
    end

    @testset "find_paths - depth limit" begin
        store = MemoryStore()
        nodes = [mem_vertex!(store, "chain$i", "ch1") for i in 1:10]
        for i in 1:9
            mem_edge!(store, nodes[i], "then", nodes[i+1])
        end

        # With depth 3, should not find path from node 1 to node 10
        result = find_paths(store, nodes[1].nptr, nodes[10].nptr; max_depth=3)
        @test isempty(result.paths)

        # With depth 9, should find it
        result2 = find_paths(store, nodes[1].nptr, nodes[10].nptr; max_depth=9)
        @test length(result2.paths) == 1
        @test length(result2.paths[1]) == 10
    end

    @testset "detect_path_loops - no loops" begin
        paths = [
            [NodePtr(1, 1), NodePtr(1, 2), NodePtr(1, 3)],
            [NodePtr(1, 4), NodePtr(1, 5), NodePtr(1, 6)],
        ]
        loops = detect_path_loops(paths)
        @test isempty(loops)
    end

    @testset "detect_path_loops - with cycle" begin
        paths = [
            [NodePtr(1, 1), NodePtr(1, 2), NodePtr(1, 3), NodePtr(1, 1)],
        ]
        loops = detect_path_loops(paths)
        @test length(loops) == 1
        @test first(loops[1]) == NodePtr(1, 1)
        @test last(loops[1]) == NodePtr(1, 1)
    end

    @testset "detect_path_loops - multiple loops" begin
        paths = [
            [NodePtr(1, 1), NodePtr(1, 2), NodePtr(1, 1), NodePtr(1, 3), NodePtr(1, 2)],
        ]
        loops = detect_path_loops(paths)
        @test length(loops) >= 1
    end

    @testset "_is_dag_path" begin
        @test SemanticSpacetime._is_dag_path([NodePtr(1,1), NodePtr(1,2), NodePtr(1,3)])
        @test !SemanticSpacetime._is_dag_path([NodePtr(1,1), NodePtr(1,2), NodePtr(1,1)])
        @test SemanticSpacetime._is_dag_path(NodePtr[])
    end

    @testset "find_paths - self loop" begin
        store = MemoryStore()
        a = mem_vertex!(store, "self", "ch1")
        # No edge to self
        result = find_paths(store, a.nptr, a.nptr; max_depth=5)
        @test isempty(result.paths)
    end

    # Clean up global state
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()
end
