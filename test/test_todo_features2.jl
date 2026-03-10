using SQLite
using DBInterface

# ──────────────────────────────────────────────────────────────────
# Arrow/context setup
# ──────────────────────────────────────────────────────────────────

config_dir = let d = joinpath(@__DIR__, "..", "..", "SSTorytime", "SSTconfig")
    isdir(d) ? d : nothing
end

SemanticSpacetime.reset_arrows!()
SemanticSpacetime.reset_contexts!()
add_mandatory_arrows!()

if config_dir !== nothing
    st = SemanticSpacetime.N4LState()
    for cf in read_config_files(config_dir)
        SemanticSpacetime.parse_config_file(cf; st=st)
    end
end

# Register arrows needed by tests if not already present
if get_arrow_by_name("then") === nothing
    fwd = insert_arrow!("LEADSTO", "then", "leads to next", "+")
    bwd = insert_arrow!("LEADSTO", "prev", "preceded by", "-")
    insert_inverse_arrow!(fwd, bwd)
end
if get_arrow_by_name("note") === nothing
    insert_arrow!("EXPRESS", "note", "property note", "+")
end

# ──────────────────────────────────────────────────────────────────
# 1. Unified Search Tests
# ──────────────────────────────────────────────────────────────────

@testset "UnifiedSearch" begin
    store = MemoryStore()
    a = mem_vertex!(store, "fever symptom", "patients")
    b = mem_vertex!(store, "cold symptom", "patients")
    c = mem_vertex!(store, "fever treatment", "treatments")
    d = mem_vertex!(store, "headache symptom", "patients")

    mem_edge!(store, a, "then", b, String[], 0.8f0)
    mem_edge!(store, a, "then", c, String[], 1.5f0)
    mem_edge!(store, c, "then", d, String[], 0.3f0)

    @testset "basic text search" begin
        params = UnifiedSearchParams(text="fever")
        results = unified_search(store, params)
        @test length(results) == 2
        @test all(n -> occursin("fever", n.s), results)
    end

    @testset "chapter filter" begin
        params = UnifiedSearchParams(text="fever", chapters=["patients"])
        results = unified_search(store, params)
        @test length(results) == 1
        @test results[1].s == "fever symptom"
    end

    @testset "min_weight filter" begin
        params = UnifiedSearchParams(text="", chapters=String[], min_weight=1.0f0)
        results = unified_search(store, params)
        # Only nodes with at least one link >= 1.0 weight
        names = Set(n.s for n in results)
        @test "fever symptom" in names      # has link w=1.5
        @test "fever treatment" in names    # has link w=1.5 (inverse)
    end

    @testset "sttype filter" begin
        params = UnifiedSearchParams(sttype_filter=LEADSTO)
        results = unified_search(store, params)
        @test length(results) >= 2  # nodes with LEADSTO links
    end

    @testset "max_results limit" begin
        params = UnifiedSearchParams(text="symptom", max_results=1)
        results = unified_search(store, params)
        @test length(results) == 1
    end

    @testset "natural language query" begin
        results = unified_search(store, "fever")
        @test length(results) == 2

        # NOT exclusion
        results2 = unified_search(store, "fever NOT treatment")
        @test length(results2) == 1
        @test results2[1].s == "fever symptom"

        # in:chapter
        results3 = unified_search(store, "symptom in:patients")
        @test all(n -> n.chap == "patients", results3)

        # w>threshold
        results4 = unified_search(store, "w>1.0")
        names4 = Set(n.s for n in results4)
        @test "fever symptom" in names4
    end

    @testset "st: filter in query" begin
        results = unified_search(store, "st:leadsto")
        @test length(results) >= 2
    end
end

# ──────────────────────────────────────────────────────────────────
# 2. Combinatorial Search Tests
# ──────────────────────────────────────────────────────────────────

@testset "CombinatorialSearch" begin
    store = MemoryStore()
    mem_vertex!(store, "alpha beta", "ch1")
    mem_vertex!(store, "alpha gamma", "ch1")
    mem_vertex!(store, "beta delta", "ch2")
    mem_vertex!(store, "gamma delta", "ch2")

    @testset "AND mode" begin
        results = combinatorial_search(store, ["alpha", "beta"]; mode=:and)
        @test length(results) == 1
        @test length(results[1]) == 1
        @test results[1][1].s == "alpha beta"
    end

    @testset "OR mode" begin
        results = combinatorial_search(store, ["alpha", "delta"]; mode=:or)
        @test length(results) == 1
        names = Set(n.s for n in results[1])
        @test "alpha beta" in names
        @test "alpha gamma" in names
        @test "beta delta" in names
        @test "gamma delta" in names
    end

    @testset "product mode" begin
        results = combinatorial_search(store, ["alpha", "delta"]; mode=:product)
        @test length(results) == 2  # one vector per term
        @test length(results[1]) == 2  # alpha matches 2 nodes
        @test length(results[2]) == 2  # delta matches 2 nodes
    end

    @testset "empty terms" begin
        results = combinatorial_search(store, String[]; mode=:and)
        @test isempty(results)
    end
end

@testset "CrossChapterSearch" begin
    store = MemoryStore()
    mem_vertex!(store, "fever info", "patients")
    mem_vertex!(store, "fever meds", "treatments")
    mem_vertex!(store, "cold info", "patients")

    results = cross_chapter_search(store, "fever", ["patients", "treatments"])
    @test haskey(results, "patients")
    @test haskey(results, "treatments")
    @test length(results["patients"]) == 1
    @test results["patients"][1].s == "fever info"
    @test length(results["treatments"]) == 1
    @test results["treatments"][1].s == "fever meds"
end

# ──────────────────────────────────────────────────────────────────
# 3. SQL Database Indexing Tests
# ──────────────────────────────────────────────────────────────────

@testset "SQLIndexing" begin
    @testset "basic table indexing" begin
        db = SQLite.DB()
        DBInterface.execute(db, "CREATE TABLE patients (id INTEGER PRIMARY KEY, name TEXT, age INTEGER)")
        DBInterface.execute(db, "INSERT INTO patients VALUES (1, 'Alice', 30)")
        DBInterface.execute(db, "INSERT INTO patients VALUES (2, 'Bob', 25)")
        DBInterface.execute(db, "INSERT INTO patients VALUES (3, 'Carol', 40)")

        store = MemoryStore()
        config = SQLIndexConfig(label_columns=Dict("patients" => "name"))
        counts = index_sql_database!(store, db; config=config)

        @test haskey(counts, "patients")
        @test counts["patients"] == 3

        # Check nodes were created
        alice_nodes = mem_get_nodes_by_name(store, "Alice")
        @test length(alice_nodes) >= 1
        @test alice_nodes[1].chap == "db.patients"

        # Check property annotation nodes exist
        age_nodes = mem_search_text(store, "age: 30")
        @test length(age_nodes) >= 1
    end

    @testset "foreign key edges" begin
        db = SQLite.DB()
        DBInterface.execute(db, "PRAGMA foreign_keys = ON")
        DBInterface.execute(db, """
            CREATE TABLE departments (
                id INTEGER PRIMARY KEY,
                name TEXT
            )
        """)
        DBInterface.execute(db, """
            CREATE TABLE employees (
                id INTEGER PRIMARY KEY,
                name TEXT,
                dept_id INTEGER REFERENCES departments(id)
            )
        """)
        DBInterface.execute(db, "INSERT INTO departments VALUES (1, 'Engineering')")
        DBInterface.execute(db, "INSERT INTO departments VALUES (2, 'Sales')")
        DBInterface.execute(db, "INSERT INTO employees VALUES (1, 'Alice', 1)")
        DBInterface.execute(db, "INSERT INTO employees VALUES (2, 'Bob', 2)")

        store = MemoryStore()
        config = SQLIndexConfig(
            label_columns=Dict("departments" => "name", "employees" => "name"),
            detect_foreign_keys=true,
        )
        counts = index_sql_database!(store, db; config=config)

        @test counts["departments"] == 2
        @test counts["employees"] == 2

        # Check FK edge: Alice -> Engineering
        alice_nodes = mem_get_nodes_by_name(store, "Alice")
        @test length(alice_nodes) >= 1
        alice = alice_nodes[1]
        # Alice should have outgoing LEADSTO link (from "then" arrow)
        has_fk_link = false
        eng_nodes = mem_get_nodes_by_name(store, "Engineering")
        if !isempty(eng_nodes)
            eng_nptr = eng_nodes[1].nptr
            for st_links in alice.incidence
                for lnk in st_links
                    if lnk.dst == eng_nptr
                        has_fk_link = true
                    end
                end
            end
        end
        @test has_fk_link
    end

    @testset "custom config" begin
        db = SQLite.DB()
        DBInterface.execute(db, "CREATE TABLE items (id INTEGER PRIMARY KEY, title TEXT, internal_code TEXT)")
        DBInterface.execute(db, "INSERT INTO items VALUES (1, 'Widget', 'X123')")

        store = MemoryStore()
        config = SQLIndexConfig(
            tables=["items"],
            label_columns=Dict("items" => "title"),
            skip_columns=["internal_code"],
            chapter_prefix="mydb",
            detect_foreign_keys=false,
        )
        counts = index_sql_database!(store, db; config=config)

        @test counts["items"] == 1
        widget = mem_get_nodes_by_name(store, "Widget")
        @test length(widget) >= 1
        @test widget[1].chap == "mydb.items"

        # internal_code should be skipped — no annotation node for it
        code_nodes = mem_search_text(store, "internal_code")
        @test isempty(code_nodes)
    end

    @testset "auto table discovery" begin
        db = SQLite.DB()
        DBInterface.execute(db, "CREATE TABLE t1 (id INTEGER PRIMARY KEY, val TEXT)")
        DBInterface.execute(db, "CREATE TABLE t2 (id INTEGER PRIMARY KEY, val TEXT)")
        DBInterface.execute(db, "INSERT INTO t1 VALUES (1, 'a')")
        DBInterface.execute(db, "INSERT INTO t2 VALUES (1, 'b')")

        store = MemoryStore()
        counts = index_sql_database!(store, db)
        @test haskey(counts, "t1")
        @test haskey(counts, "t2")
        @test counts["t1"] == 1
        @test counts["t2"] == 1
    end
end
