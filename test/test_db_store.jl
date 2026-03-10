@testset "DBStore" begin
    using SQLite
    import DBInterface

    @testset "Schema creation" begin
        db = SQLite.DB(":memory:")
        store = DBStore(db)
        @test store.configured == true
        # Verify tables exist
        result = DBInterface.execute(db, "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
        tables = [String(row[1]) for row in result]
        @test "sst_nodes" in tables
        @test "sst_links" in tables
        @test "sst_arrows" in tables
    end

    @testset "Node operations" begin
        db = SQLite.DB(":memory:")
        store = DBStore(db)
        SemanticSpacetime.reset_arrows!()
        add_mandatory_arrows!()

        n1 = db_vertex!(store, "hello world", "ch1")
        @test n1.s == "hello world"
        @test n1.nptr.class == N2GRAM
        @test n1.nptr.cptr == 1

        # Idempotent
        n1b = db_vertex!(store, "hello world", "ch1")
        @test n1b.nptr == n1.nptr

        n2 = db_vertex!(store, "goodbye", "ch1")
        @test n2.nptr.class == N1GRAM
        @test n2.nptr.cptr == 1
    end

    @testset "Edge operations" begin
        db = SQLite.DB(":memory:")
        store = DBStore(db)
        SemanticSpacetime.reset_arrows!()
        add_mandatory_arrows!()

        n1 = db_vertex!(store, "event A", "ch1")
        n2 = db_vertex!(store, "event B", "ch1")

        arr, st = db_edge!(store, n1, "then", n2)
        @test Int(arr) > 0

        # Check links
        links = db_get_links(store, n1.nptr)
        @test !isempty(links)
        @test any(l -> l.dst == n2.nptr, links)

        # Check inverse
        inv_links = db_get_links(store, n2.nptr)
        @test !isempty(inv_links)
        @test any(l -> l.dst == n1.nptr, inv_links)

        # Idempotent
        db_edge!(store, n1, "then", n2)
        links2 = db_get_links(store, n1.nptr)
        @test length(links2) == length(links)
    end

    @testset "Query operations" begin
        db = SQLite.DB(":memory:")
        store = DBStore(db)
        SemanticSpacetime.reset_arrows!()
        add_mandatory_arrows!()

        db_vertex!(store, "alpha", "chapter1")
        db_vertex!(store, "beta", "chapter1")
        db_vertex!(store, "gamma", "chapter2")

        # Search by name
        nodes = db_get_nodes_by_name(store, "alpha")
        @test length(nodes) == 1
        @test nodes[1].s == "alpha"

        # Pattern search
        ptrs = db_search_nodes(store, "a")
        @test length(ptrs) >= 2

        # Chapter search
        ptrs2 = db_search_nodes(store, "a"; chapter="chapter1")
        @test length(ptrs2) >= 1

        # Chapters list
        chapters = db_get_chapters(store)
        @test "chapter1" in chapters
        @test "chapter2" in chapters

        # Stats
        stats = db_stats(store)
        @test stats["nodes"] == 3
    end

    @testset "Arrow sync" begin
        db = SQLite.DB(":memory:")
        store = DBStore(db)
        SemanticSpacetime.reset_arrows!()
        add_mandatory_arrows!()

        db_upload_arrows!(store)

        count = 0
        for row in DBInterface.execute(db, "SELECT COUNT(*) FROM sst_arrows")
            count = Int(row[1])
        end
        @test count > 0

        # Load back
        SemanticSpacetime.reset_arrows!()
        db_load_arrows!(store)
        entry = get_arrow_by_name("then")
        @test !isnothing(entry)
    end

    @testset "mem_* interface compatibility" begin
        db = SQLite.DB(":memory:")
        store = DBStore(db)
        SemanticSpacetime.reset_arrows!()
        add_mandatory_arrows!()

        n1 = mem_vertex!(store, "test node", "ch1")
        @test n1.s == "test node"

        node = mem_get_node(store, n1.nptr)
        @test node.s == "test node"

        n2 = mem_vertex!(store, "other node", "ch1")
        mem_edge!(store, n1, "then", n2)

        links = db_get_links(store, n1.nptr)
        @test !isempty(links)
    end

    @testset "open_sqlite convenience" begin
        SemanticSpacetime.reset_arrows!()
        add_mandatory_arrows!()

        store = open_sqlite()
        @test store isa DBStore
        @test store.configured

        n = db_vertex!(store, "quick test", "ch")
        @test n.s == "quick test"

        close_db(store)
    end

    @testset "Cone search with DBStore" begin
        SemanticSpacetime.reset_arrows!()
        add_mandatory_arrows!()

        store = open_sqlite()

        n1 = db_vertex!(store, "start", "ch1")
        n2 = db_vertex!(store, "middle", "ch1")
        n3 = db_vertex!(store, "end", "ch1")
        db_edge!(store, n1, "then", n2)
        db_edge!(store, n2, "then", n3)

        cone = forward_cone(store, n1.nptr; depth=3, limit=10)
        @test !isempty(cone.paths)

        close_db(store)
    end

    @testset "DuckDB backend" begin
        try
            using DuckDB
            SemanticSpacetime.reset_arrows!()
            add_mandatory_arrows!()

            store = open_duckdb()
            @test store isa DBStore

            n = db_vertex!(store, "duckdb test", "ch1")
            @test n.s == "duckdb test"

            retrieved = db_get_node(store, n.nptr)
            @test retrieved.s == "duckdb test"

            close_db(store)
        catch e
            if isa(e, ArgumentError) || isa(e, LoadError)
                @test_skip "DuckDB not available"
            else
                rethrow()
            end
        end
    end
end
