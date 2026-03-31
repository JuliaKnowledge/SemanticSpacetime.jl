using Dates

@testset "Todo Features" begin
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()
    load_test_config!()

    @testset "Focal View" begin
        contain_arrow = get_arrow_by_name("contain") !== nothing ? "contain" : "has-pt"
        @test get_arrow_by_name(contain_arrow) !== nothing

        @testset "focal_view builds children list" begin
            store = MemoryStore()
            root = mem_vertex!(store, "Library", "ch1")
            book1 = mem_vertex!(store, "Book A", "ch1")
            book2 = mem_vertex!(store, "Book B", "ch1")
            mem_edge!(store, root, contain_arrow, book1)
            mem_edge!(store, root, contain_arrow, book2)

            fv = focal_view(store, root.nptr)
            @test fv.root == root.nptr
            @test length(fv.children) == 2
            @test book1.nptr in fv.children
            @test book2.nptr in fv.children
            @test fv.parent === nothing
            @test fv.depth == 1
        end

        @testset "drill_down and drill_up" begin
            store = MemoryStore()
            root = mem_vertex!(store, "Root", "ch1")
            child = mem_vertex!(store, "Child", "ch1")
            grandchild = mem_vertex!(store, "Grandchild", "ch1")
            mem_edge!(store, root, contain_arrow, child)
            mem_edge!(store, child, contain_arrow, grandchild)

            fv = focal_view(store, root.nptr)
            @test child.nptr in fv.children

            fv2 = drill_down(store, fv, child.nptr)
            @test fv2.root == child.nptr
            @test grandchild.nptr in fv2.children
            @test fv2.parent == root.nptr
            @test length(fv2.breadcrumb) == 2

            fv3 = drill_up(store, fv2)
            @test fv3.root == root.nptr
            @test child.nptr in fv3.children
        end

        @testset "drill_up at top throws" begin
            store = MemoryStore()
            root = mem_vertex!(store, "Alone", "ch1")
            fv = focal_view(store, root.nptr)
            @test_throws ErrorException drill_up(store, fv)
        end

        @testset "drill_down invalid child throws" begin
            store = MemoryStore()
            root = mem_vertex!(store, "Root2", "ch1")
            other = mem_vertex!(store, "Other2", "ch1")
            fv = focal_view(store, root.nptr)
            @test_throws ErrorException drill_down(store, fv, other.nptr)
        end

        @testset "tree_view renders text" begin
            store = MemoryStore()
            root = mem_vertex!(store, "Music", "ch1")
            jazz = mem_vertex!(store, "Jazz", "ch1")
            rock = mem_vertex!(store, "Rock", "ch1")
            bebop = mem_vertex!(store, "Bebop", "ch1")
            mem_edge!(store, root, contain_arrow, jazz)
            mem_edge!(store, root, contain_arrow, rock)
            mem_edge!(store, jazz, contain_arrow, bebop)

            tv = tree_view(store, root.nptr; max_depth=3)
            @test occursin("Music", tv)
            @test occursin("Jazz", tv)
            @test occursin("Rock", tv)
            @test occursin("Bebop", tv)
            @test occursin("└", tv) || occursin("├", tv)
        end

        @testset "hierarchy_roots finds top-level nodes" begin
            store = MemoryStore()
            top = mem_vertex!(store, "TopNode", "ch1")
            mid = mem_vertex!(store, "MidNode", "ch1")
            leaf = mem_vertex!(store, "LeafNode", "ch1")
            mem_edge!(store, top, contain_arrow, mid)
            mem_edge!(store, mid, contain_arrow, leaf)

            roots = hierarchy_roots(store)
            @test top.nptr in roots
            @test !(mid.nptr in roots)
            @test !(leaf.nptr in roots)
        end

        @testset "focal_view with no children" begin
            store = MemoryStore()
            leaf = mem_vertex!(store, "Leaf", "ch1")
            fv = focal_view(store, leaf.nptr)
            @test isempty(fv.children)
        end
    end

    @testset "ETC Validation Integration" begin
        @testset "validate_compiled_graph! infers and validates" begin
            store = MemoryStore()
            a = mem_vertex!(store, "EventA", "ch1")
            b = mem_vertex!(store, "EventB", "ch1")
            mem_edge!(store, a, "then", b)

            warnings = validate_compiled_graph!(store)
            @test a.psi.e == true
            @test isa(warnings, Vector{String})
        end

        @testset "validate_compiled_graph! verbose mode" begin
            store = MemoryStore()
            a = mem_vertex!(store, "VerboseNode", "ch1")
            b = mem_vertex!(store, "VerboseTarget", "ch1")
            mem_edge!(store, a, "then", b)

            warnings = validate_compiled_graph!(store; verbose=true)
            @test any(w -> occursin("INFO:", w), warnings)
        end

        @testset "validate_compiled_graph! detects mismatches" begin
            store = MemoryStore()
            a = mem_vertex!(store, "BadNode", "ch1")
            b = mem_vertex!(store, "Target", "ch1")
            mem_edge!(store, a, "then", b)
            a.psi = Etc(false, true, false)

            warnings = validate_etc(a)
            @test !isempty(warnings)
        end

        @testset "validate after N4L compilation" begin
            SemanticSpacetime.reset_arrows!()
            SemanticSpacetime.reset_contexts!()
            store = MemoryStore()
            text = """
            -validation test

            alpha
            beta
            gamma
            """
            cr = compile_n4l_string!(store, text; config_dir=TEST_SST_CONFIG_DIR)
            @test cr isa N4LCompileResult
            warnings = validate_compiled_graph!(store)
            @test isa(warnings, Vector{String})
        end
    end

    @testset "Provenance" begin
        load_test_config!()
        @test get_arrow_by_name("note") !== nothing

        @testset "set and get provenance" begin
            store = MemoryStore()
            n = mem_vertex!(store, "tracked node", "ch1")
            ts = DateTime(2024, 6, 15, 12, 0, 0)
            prov = Provenance("test.n4l", 42, ts, "tester")

            set_provenance!(store, n.nptr, prov)
            got = get_provenance(store, n.nptr)

            @test got !== nothing
            @test got.source == "test.n4l"
            @test got.line == 42
            @test got.timestamp == ts
            @test got.author == "tester"
        end

        @testset "get_provenance returns nothing when absent" begin
            store = MemoryStore()
            n = mem_vertex!(store, "no prov", "ch1")
            @test get_provenance(store, n.nptr) === nothing
        end

        @testset "Provenance struct fields" begin
            ts = DateTime(2024, 1, 1)
            p = Provenance("src.jl", 10, ts, "alice")
            @test p.source == "src.jl"
            @test p.line == 10
            @test p.timestamp == ts
            @test p.author == "alice"
        end

        @testset "set_provenance! with no line" begin
            store = MemoryStore()
            n = mem_vertex!(store, "no line node", "ch1")
            ts = DateTime(2024, 3, 1)
            prov = Provenance("file.n4l", 0, ts, "")

            set_provenance!(store, n.nptr, prov)
            got = get_provenance(store, n.nptr)
            @test got !== nothing
            @test got.source == "file.n4l"
            @test got.line == 0
            @test got.author == ""
        end

        @testset "compile_n4l_with_provenance!" begin
            SemanticSpacetime.reset_arrows!()
            SemanticSpacetime.reset_contexts!()
            store = MemoryStore()
            text = """
            -prov chapter

            apple
            banana
            """
            cr = compile_n4l_with_provenance!(store, text;
                source="test_input.n4l", author="testbot", config_dir=TEST_SST_CONFIG_DIR)

            @test cr isa N4LCompileResult
            @test cr.nodes_created >= 2

            apple_nodes = mem_get_nodes_by_name(store, "apple")
            if !isempty(apple_nodes)
                prov = get_provenance(store, apple_nodes[1].nptr)
                @test prov !== nothing
                @test prov.source == "test_input.n4l"
                @test prov.author == "testbot"
            end
        end
    end

    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()
end
