# PostgreSQL-backed tests. Only included from runtests.jl when SST_TEST_DB is
# set. Requires a live Postgres reachable with the SSTorytime standard
# credentials (user=sstoryline, password=sst_1234, dbname=sstoryline).

@testset "PostgreSQL backend" begin
    local sst
    try
        sst = open_sst()
        configure!(sst)
    catch e
        @warn "Could not connect to PostgreSQL; skipping DB tests" exception=e
        @test_skip false
        return
    end

    # Clean slate
    for t in ("Node", "PageMap", "ArrowDirectory", "ArrowInverses",
              "ContextDirectory", "LastSeen")
        SemanticSpacetime.execute_sql(sst, "TRUNCATE $t")
    end
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()
    add_mandatory_arrows!()

    # Build a small graph in the node directory, then bulk upload.
    p1 = append_text_to_directory!(Node("alpha node here", "chap1"))
    p2 = append_text_to_directory!(Node("beta node here", "chap1"))
    p3 = append_text_to_directory!(Node("gamma node here", "chap2"))
    graph_to_db!(sst)

    @testset "graph_to_db! persists nodes" begin
        res = SemanticSpacetime.execute_sql_strict(sst, "SELECT count(*) FROM Node")
        ct = SemanticSpacetime.LibPQ.columntable(res)
        @test Int(ct[1][1]) == 3
    end

    @testset "get_db_node_by_nodeptr readback" begin
        n1 = SemanticSpacetime.get_db_node_by_nodeptr(sst, p1)
        @test n1.s == "alpha node here"
        @test n1.chap == "chap1"
        @test n1.l == length("alpha node here")
        @test n1.nptr == p1
        # Missing node returns an empty Node
        missing_ptr = NodePtr(N1GRAM, 9999)
        @test isempty(SemanticSpacetime.get_db_node_by_nodeptr(sst, missing_ptr).s)
    end

    @testset "name lookup returns the right pointer" begin
        ptrs = SemanticSpacetime.get_db_node_ptr_matching_name(sst, "beta node here")
        @test ptrs == [p2]
        @test isempty(SemanticSpacetime.get_db_node_ptr_matching_name(sst, "nope"))
    end

    @testset "name lookup returns ALL matches (not just the first)" begin
        # Two distinct nodes sharing chapter text — lookup by chapter must
        # return both rows (regression: LibPQ.Columns misuse returned only one).
        ptrs = SemanticSpacetime.get_db_node_ptr_matching_name(sst, "alpha node here", "chap1")
        @test ptrs == [p1]
        chaps = SemanticSpacetime.get_db_chapters_matching_name(sst, "chap")
        @test Set(chaps) == Set(["chap1", "chap2"])
    end

    @testset "arrow directory round-trips through the DB" begin
        SemanticSpacetime.load_arrows_from_db!(sst)
        e = get_arrow_by_name("incl")
        @test e !== nothing
        @test e.long == "includes"
        # Inverse relationship survives the round-trip
        inv = SemanticSpacetime.get_inverse_arrow(e.ptr)
        @test inv !== nothing
        @test get_arrow_by_ptr(inv).short == "is-incl"
    end

    @testset "structured search returns nodes" begin
        params = SearchParameters()
        params.names = ["gamma node here"]
        results = search_nodes(sst, params)
        @test any(n -> n.s == "gamma node here", results)
    end

    @testset "build_adjacency reads node links" begin
        adj = build_adjacency(sst)
        @test length(adj.nodes) == 3
    end

    close_sst(sst)
end
