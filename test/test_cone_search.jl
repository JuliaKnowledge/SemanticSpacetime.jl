@testset "ConeSearch" begin
    # Reset global state
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()

    # Register arrows
    fwd = insert_arrow!("LEADSTO", "then", "leads to next", "+")
    bwd = insert_arrow!("LEADSTO", "prev", "preceded by", "-")
    insert_inverse_arrow!(fwd, bwd)

    @testset "ConeResult construction" begin
        cr = SemanticSpacetime.ConeResult(NO_NODE_PTR)
        @test cr.root == NO_NODE_PTR
        @test isempty(cr.paths)
        @test isempty(cr.supernodes)
    end

    @testset "forward_cone - linear chain" begin
        store = MemoryStore()
        a = mem_vertex!(store, "A", "ch1")
        b = mem_vertex!(store, "B", "ch1")
        c = mem_vertex!(store, "C", "ch1")
        d = mem_vertex!(store, "D", "ch1")
        mem_edge!(store, a, "then", b)
        mem_edge!(store, b, "then", c)
        mem_edge!(store, c, "then", d)

        result = forward_cone(store, a.nptr; depth=5)
        @test result.root == a.nptr
        @test !isempty(result.paths)

        # Should reach all downstream nodes
        all_dsts = Set{NodePtr}()
        for path in result.paths
            for lnk in path
                push!(all_dsts, lnk.dst)
            end
        end
        @test b.nptr in all_dsts
        @test c.nptr in all_dsts
        @test d.nptr in all_dsts
    end

    @testset "forward_cone - branching tree" begin
        store = MemoryStore()
        root = mem_vertex!(store, "root", "ch1")
        l1 = mem_vertex!(store, "left1", "ch1")
        r1 = mem_vertex!(store, "right1", "ch1")
        l2 = mem_vertex!(store, "left2", "ch1")
        r2 = mem_vertex!(store, "right2", "ch1")
        mem_edge!(store, root, "then", l1)
        mem_edge!(store, root, "then", r1)
        mem_edge!(store, l1, "then", l2)
        mem_edge!(store, r1, "then", r2)

        result = forward_cone(store, root.nptr; depth=3)
        @test result.root == root.nptr

        all_dsts = Set{NodePtr}()
        for path in result.paths
            for lnk in path
                push!(all_dsts, lnk.dst)
            end
        end
        @test l1.nptr in all_dsts
        @test r1.nptr in all_dsts
        @test l2.nptr in all_dsts
        @test r2.nptr in all_dsts
    end

    @testset "forward_cone - depth limit" begin
        store = MemoryStore()
        nodes = [mem_vertex!(store, "n$i", "ch1") for i in 1:10]
        for i in 1:9
            mem_edge!(store, nodes[i], "then", nodes[i+1])
        end

        result = forward_cone(store, nodes[1].nptr; depth=3)
        # Should not reach nodes beyond depth 3
        all_dsts = Set{NodePtr}()
        for path in result.paths
            for lnk in path
                push!(all_dsts, lnk.dst)
            end
        end
        @test nodes[2].nptr in all_dsts
        @test nodes[3].nptr in all_dsts
        @test nodes[4].nptr in all_dsts
        @test !(nodes[5].nptr in all_dsts)
    end

    @testset "forward_cone - limit paths" begin
        store = MemoryStore()
        root = mem_vertex!(store, "hub", "ch1")
        for i in 1:20
            n = mem_vertex!(store, "spoke$i", "ch1")
            mem_edge!(store, root, "then", n)
        end

        result = forward_cone(store, root.nptr; depth=1, limit=5)
        @test length(result.paths) <= 5
    end

    @testset "backward_cone - linear chain" begin
        store = MemoryStore()
        a = mem_vertex!(store, "X", "ch1")
        b = mem_vertex!(store, "Y", "ch1")
        c = mem_vertex!(store, "Z", "ch1")
        mem_edge!(store, a, "then", b)
        mem_edge!(store, b, "then", c)

        # Backward from c should find path back to a via inverse links
        result = backward_cone(store, c.nptr; depth=5)
        @test result.root == c.nptr

        all_dsts = Set{NodePtr}()
        for path in result.paths
            for lnk in path
                push!(all_dsts, lnk.dst)
            end
        end
        @test b.nptr in all_dsts
        @test a.nptr in all_dsts
    end

    @testset "backward_cone - from leaf" begin
        store = MemoryStore()
        a = mem_vertex!(store, "start", "ch1")
        b = mem_vertex!(store, "mid", "ch1")
        c = mem_vertex!(store, "end", "ch1")
        mem_edge!(store, a, "then", b)
        mem_edge!(store, b, "then", c)

        result = backward_cone(store, a.nptr; depth=5)
        # a has no predecessors, so no backward paths
        @test isempty(result.paths)
    end

    @testset "forward_cone - empty graph" begin
        store = MemoryStore()
        result = forward_cone(store, NodePtr(1, 999); depth=5)
        @test isempty(result.paths)
    end

    @testset "supernodes - diamond graph" begin
        store = MemoryStore()
        a = mem_vertex!(store, "top", "ch1")
        b = mem_vertex!(store, "left", "ch1")
        c = mem_vertex!(store, "right", "ch1")
        d = mem_vertex!(store, "bottom", "ch1")
        mem_edge!(store, a, "then", b)
        mem_edge!(store, a, "then", c)
        mem_edge!(store, b, "then", d)
        mem_edge!(store, c, "then", d)

        result = forward_cone(store, a.nptr; depth=3)
        # d should appear as a supernode (reachable via both b and c)
        @test d.nptr in result.supernodes
    end

    @testset "select_stories_by_arrow - in-memory" begin
        store = MemoryStore()
        a = mem_vertex!(store, "s1", "ch1")
        b = mem_vertex!(store, "s2", "ch1")
        mem_edge!(store, a, "then", b)

        matches = select_stories_by_arrow(store, [a.nptr, b.nptr],
                                          ArrowPtr[], Int[], 10)
        @test length(matches) == 2
        @test a.nptr in matches
        @test b.nptr in matches

        # Limit
        matches2 = select_stories_by_arrow(store, [a.nptr, b.nptr],
                                           ArrowPtr[], Int[], 1)
        @test length(matches2) == 1
    end

    # Clean up global state
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()
end
