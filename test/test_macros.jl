@testset "Syntactic Sugar" begin

    config_dir = let d = joinpath(@__DIR__, "..", "..", "SSTorytime", "SSTconfig")
        isdir(d) ? d : nothing
    end

    # Helper: load full config or just mandatory arrows
    function _load_arrows()
        SemanticSpacetime.reset_arrows!()
        add_mandatory_arrows!()
        if config_dir !== nothing
            read_config_files(config_dir)
        end
    end

    @testset "n4l string macro" begin
        _load_arrows()
        result = n4l"""
        -test_section

         apple (then) banana
        """
        @test result isa N4LResult
    end

    @testset "@sst macro — implicit variable" begin
        _load_arrows()
        store = @sst begin
            v1 = mem_vertex!(s, "alpha", "greek")
            v2 = mem_vertex!(s, "beta", "greek")
            mem_edge!(s, v1, "then", v2)
        end
        @test store isa MemoryStore
        @test node_count(store) == 2
        @test link_count(store) >= 1
    end

    @testset "@sst macro — explicit variable" begin
        _load_arrows()
        store = @sst g begin
            a = mem_vertex!(g, "sun", "space")
            b = mem_vertex!(g, "earth", "space")
            mem_edge!(g, a, "then", b)
        end
        @test store isa MemoryStore
        @test node_count(store) == 2
    end

    @testset "@compile macro" begin
        _load_arrows()
        store, result = @compile """
        -section

         cat (then) dog
         dog (then) fish
        """
        @test store isa MemoryStore
        @test result isa N4LCompileResult
        @test result.nodes_created >= 2
    end

    @testset "@compile into existing store" begin
        _load_arrows()
        store = MemoryStore()
        _, r1 = @compile store """
        -part1

         one (then) two
        """
        before = node_count(store)
        @test before >= 2
        _, r2 = @compile store """
        -part2

         three (then) four
        """
        @test node_count(store) >= before + 2
    end

    @testset "connect! convenience" begin
        _load_arrows()
        store = MemoryStore()
        a = mem_vertex!(store, "red", "colors")
        b = mem_vertex!(store, "blue", "colors")
        arr, st = connect!(store, a, "then", b)
        @test arr > 0
        @test abs(st) == Int(LEADSTO)
    end

    @testset "connect! with keyword args" begin
        _load_arrows()
        store = MemoryStore()
        a = mem_vertex!(store, "x", "math")
        b = mem_vertex!(store, "y", "math")
        arr, st = connect!(store, a, "then", b; context=["algebra"], weight=2.0f0)
        @test arr > 0
    end

    @testset "@graph macro" begin
        _load_arrows()
        store = MemoryStore()
        @graph store begin
            a = vertex!("one", "numbers")
            b = vertex!("two", "numbers")
            c = vertex!("three", "numbers")
            edge!(a, "then", b)
            edge!(b, "then", c)
        end
        @test node_count(store) == 3
        @test link_count(store) >= 2
    end

    @testset "links accessor" begin
        _load_arrows()
        store = MemoryStore()
        a = mem_vertex!(store, "hub", "test")
        b = mem_vertex!(store, "spoke1", "test")
        c = mem_vertex!(store, "spoke2", "test")
        mem_edge!(store, a, "then", b)
        mem_edge!(store, a, "then", c)

        all_links = links(a)
        @test length(all_links) >= 2

        leadsto_links = links(a, LEADSTO)
        @test length(leadsto_links) == 2
    end

    @testset "neighbors" begin
        _load_arrows()
        store = MemoryStore()
        a = mem_vertex!(store, "center", "test")
        b = mem_vertex!(store, "leaf1", "test")
        c = mem_vertex!(store, "leaf2", "test")
        mem_edge!(store, a, "then", b)
        mem_edge!(store, a, "then", c)

        nbrs = neighbors(store, a)
        @test length(nbrs) >= 2
        @test any(n -> n.s == "leaf1", nbrs)
        @test any(n -> n.s == "leaf2", nbrs)

        leadsto_nbrs = neighbors(store, a, LEADSTO)
        @test length(leadsto_nbrs) == 2
    end

    @testset "nodes and eachnode" begin
        store = MemoryStore()
        mem_vertex!(store, "a", "ch")
        mem_vertex!(store, "b", "ch")
        mem_vertex!(store, "c", "ch")

        all_nodes = nodes(store)
        @test length(all_nodes) == 3

        count = 0
        for _ in eachnode(store)
            count += 1
        end
        @test count == 3
    end

    @testset "eachlink" begin
        _load_arrows()
        store = MemoryStore()
        a = mem_vertex!(store, "start", "test")
        b = mem_vertex!(store, "end", "test")
        mem_edge!(store, a, "then", b)

        link_count_val = 0
        for _ in eachlink(a)
            link_count_val += 1
        end
        @test link_count_val >= 1

        leadsto_count = 0
        for _ in eachlink(a, LEADSTO)
            leadsto_count += 1
        end
        @test leadsto_count == 1
    end

    @testset "find_nodes with predicate" begin
        store = MemoryStore()
        mem_vertex!(store, "short", "ch")
        mem_vertex!(store, "a longer string here", "ch")
        mem_vertex!(store, "another longer string", "ch")

        long_nodes = find_nodes(store, n -> n.l > 10)
        @test length(long_nodes) == 2
    end

    @testset "find_nodes with regex" begin
        store = MemoryStore()
        mem_vertex!(store, "apple pie", "food")
        mem_vertex!(store, "banana split", "food")
        mem_vertex!(store, "apple sauce", "food")

        apple_nodes = find_nodes(store, r"apple")
        @test length(apple_nodes) == 2
    end

    @testset "map_nodes" begin
        store = MemoryStore()
        mem_vertex!(store, "hello", "test")
        mem_vertex!(store, "world", "test")

        names = map_nodes(n -> n.s, store)
        @test sort(names) == ["hello", "world"]
    end

    @testset "with_store do-block" begin
        _load_arrows()
        store = with_store() do s
            a = mem_vertex!(s, "do-block-1", "test")
            b = mem_vertex!(s, "do-block-2", "test")
            mem_edge!(s, a, "then", b)
        end
        @test store isa MemoryStore
        @test node_count(store) == 2
    end

    @testset "with_store on existing store" begin
        store = MemoryStore()
        mem_vertex!(store, "existing", "test")
        with_store(store) do s
            mem_vertex!(s, "added", "test")
        end
        @test node_count(store) == 2
    end

    @testset "MemoryStore summary" begin
        store = MemoryStore()
        mem_vertex!(store, "a", "ch")
        s = summary(store)
        @test occursin("1 nodes", s)
        @test occursin("MemoryStore", s)
    end

    @testset "MemoryStore text/plain display" begin
        store = MemoryStore()
        mem_vertex!(store, "a", "ch")
        buf = IOBuffer()
        show(buf, MIME("text/plain"), store)
        output = String(take!(buf))
        @test occursin("Nodes:", output)
        @test occursin("Chapters:", output)
    end

    @testset "N4LResult text/plain display" begin
        _load_arrows()
        result = n4l"""
        -section

         x (then) y
        """
        buf = IOBuffer()
        show(buf, MIME("text/plain"), result)
        output = String(take!(buf))
        @test occursin("N4LResult", output)
        @test occursin("Errors:", output)
    end
end
