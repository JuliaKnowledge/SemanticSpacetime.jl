using Test

@testset "Cross-Language Validation (Go ↔ Julia)" begin
    @test isdir(TEST_SST_CONFIG_DIR)
    @test isdir(TEST_SST_TESTS_DIR)

    @testset "Pass fixtures (pass_*.in)" begin
        pass_files = sort(filter(
            f -> startswith(basename(f), "pass_") && endswith(f, ".in"),
            readdir(TEST_SST_TESTS_DIR; join=true),
        ))

        @test !isempty(pass_files)

        for pf in pass_files
            bn = basename(pf)
            @testset "$bn should parse without errors" begin
                result = parse_n4l_file(pf; config_dir=TEST_SST_CONFIG_DIR)
                @test !has_errors(result)
            end
        end
    end

    @testset "Fail fixtures (fail_*.in)" begin
        fail_files = sort(filter(
            f -> startswith(basename(f), "fail_") && endswith(f, ".in"),
            readdir(TEST_SST_TESTS_DIR; join=true),
        ))

        @test !isempty(fail_files)

        for ff in fail_files
            bn = basename(ff)
            @testset "$bn should produce errors" begin
                local had_error = false
                try
                    result = parse_n4l_file(ff; config_dir=TEST_SST_CONFIG_DIR)
                    had_error = has_errors(result)
                catch e
                    if e isa N4LParseError
                        had_error = true
                    else
                        rethrow(e)
                    end
                end
                @test had_error
            end
        end
    end

    @testset "Warn fixtures (warn_*.in)" begin
        warn_files = sort(filter(
            f -> startswith(basename(f), "warn_") && endswith(f, ".in"),
            readdir(TEST_SST_TESTS_DIR; join=true),
        ))

        @test !isempty(warn_files)

        for wf in warn_files
            bn = basename(wf)
            @testset "$bn should produce warnings" begin
                result = parse_n4l_file(wf; config_dir=TEST_SST_CONFIG_DIR)
                @test !has_errors(result)
                @test has_warnings(result)
            end
        end
    end

    @testset "Type system matches Go" begin
        @test Int(NEAR) == 0
        @test Int(LEADSTO) == 1
        @test Int(CONTAINS) == 2
        @test Int(EXPRESS) == 3

        @test ST_ZERO == Int(EXPRESS)
        @test ST_ZERO == 3
        @test ST_TOP == 7

        @test SemanticSpacetime.sttype_to_index(-3) == 1
        @test SemanticSpacetime.sttype_to_index(-2) == 2
        @test SemanticSpacetime.sttype_to_index(-1) == 3
        @test SemanticSpacetime.sttype_to_index(0) == 4
        @test SemanticSpacetime.sttype_to_index(1) == 5
        @test SemanticSpacetime.sttype_to_index(2) == 6
        @test SemanticSpacetime.sttype_to_index(3) == 7

        @test SemanticSpacetime.index_to_sttype(1) == -3
        @test SemanticSpacetime.index_to_sttype(4) == 0
        @test SemanticSpacetime.index_to_sttype(7) == 3

        @test SemanticSpacetime.ST_COLUMN_NAMES == ["Im3", "Im2", "Im1", "In0", "Il1", "Ic2", "Ie3"]

        @test N1GRAM == 1
        @test N2GRAM == 2
        @test N3GRAM == 3
        @test LT128 == 4
        @test LT1024 == 5
        @test GT1024 == 6

        @test SCREENWIDTH == 120
        @test RIGHTMARGIN == 5
        @test LEFTMARGIN == 5
        @test CAUSAL_CONE_MAXLIMIT == 100
    end

    @testset "Arrow system matches Go config" begin
        result = parse_n4l("-arrowtest\n one\n"; config_dir=TEST_SST_CONFIG_DIR)
        @test !has_errors(result)

        @testset "Mandatory arrows present" begin
            for name in ["empty", "void", "then", "from", "url", "img",
                         "has-extract", "extract-fr", "has-frag", "charct-in",
                         "has_theme", "theme_of", "has_highlight", "highlight_of"]
                @test get_arrow_by_name(name) !== nothing
            end
        end

        @testset "Similarity arrows (NEAR, sttype=0)" begin
            for name in ["ll", "sl", "syn", "compare", "sfor"]
                a = get_arrow_by_name(name)
                @test a !== nothing
                @test SemanticSpacetime.index_to_sttype(a.stindex) == Int(NEAR)
            end
        end

        @testset "LeadsTo arrows (LEADSTO, sttype=±1)" begin
            for name in ["next", "brings", "fwd", "cause"]
                a = get_arrow_by_name(name)
                @test a !== nothing
                @test abs(SemanticSpacetime.index_to_sttype(a.stindex)) == Int(LEADSTO)
            end
        end

        @testset "Contains arrows (CONTAINS, sttype=±2)" begin
            for name in ["contain", "consists", "has-pt", "setof"]
                a = get_arrow_by_name(name)
                @test a !== nothing
                @test abs(SemanticSpacetime.index_to_sttype(a.stindex)) == Int(CONTAINS)
            end
        end

        @testset "Express arrows (EXPRESS, sttype=±3)" begin
            for name in ["note", "remark", "e.g.", "abbrev"]
                a = get_arrow_by_name(name)
                @test a !== nothing
                @test abs(SemanticSpacetime.index_to_sttype(a.stindex)) == Int(EXPRESS)
            end
        end

        @testset "Forward/inverse arrow pairs" begin
            pairs = [
                ("then", "from"),
                ("next", "prev"),
                ("contain", "belong"),
                ("note", "isnotefor"),
                ("url", "isurl"),
            ]
            for (fwd_name, bwd_name) in pairs
                fwd = get_arrow_by_name(fwd_name)
                bwd = get_arrow_by_name(bwd_name)
                @test fwd !== nothing
                @test bwd !== nothing
                @test SemanticSpacetime.index_to_sttype(fwd.stindex) == -SemanticSpacetime.index_to_sttype(bwd.stindex)
            end
        end

        @testset "Config file sections map to correct STTypes" begin
            config_files = read_config_files(TEST_SST_CONFIG_DIR)
            @test length(config_files) == 6

            expected_sections = Dict(
                "NR-0" => 0,
                "LT-1" => 1,
                "CN-2" => 2,
                "EP-3" => 3,
            )
            for cf in config_files
                bn = basename(cf)
                for (tag, _) in expected_sections
                    occursin(tag, bn) && @test true
                end
            end
        end
    end

    @testset "Graph construction via MemoryStore" begin
        n4l_text = """
        -vocabulary

        :: language, learning ::

         apple
         fruit (contain) apple
         apple (note) a common fruit
         apple (ll) äppel
         banana
         fruit (contain) banana
         banana (note) a tropical fruit
         apple (fwd) banana
        """

        store = MemoryStore()
        cr = compile_n4l_string!(store, n4l_text; config_dir=TEST_SST_CONFIG_DIR)

        @testset "Compilation succeeds" begin
            @test isempty(cr.errors)
            @test cr.nodes_created > 0
            @test cr.edges_created > 0
        end

        @testset "Node count" begin
            @test node_count(store) == 6
            @test cr.nodes_created == 6
        end

        @testset "Edge count" begin
            @test cr.edges_created == 7
            @test link_count(store) >= cr.edges_created
        end

        @testset "Chapter tracking" begin
            @test cr.chapters == ["vocabulary"]
            chapters = mem_get_chapters(store)
            @test "vocabulary" in chapters
        end

        @testset "Node retrieval" begin
            @test length(mem_get_nodes_by_name(store, "apple")) == 1
            @test length(mem_get_nodes_by_name(store, "banana")) == 1
        end

        @testset "Link types" begin
            apple = first(mem_get_nodes_by_name(store, "apple"))
            total_links = sum(length(apple.incidence[i]) for i in 1:ST_TOP)
            @test total_links > 0
        end

        @testset "Search works" begin
            results = mem_search_text(store, "apple")
            @test !isempty(results)
            @test any(n -> n.s == "apple", results)
        end
    end

    @testset "Text size classification (n_channel)" begin
        @test n_channel("hello") == N1GRAM
        @test n_channel("x") == N1GRAM
        @test n_channel("hello world") == N2GRAM
        @test n_channel("one two three") == N3GRAM
        @test n_channel("one two three four") == LT128

        long_str = join(["word$i" for i in 1:30], " ")
        @test length(long_str) >= 128
        @test n_channel(long_str) == LT1024

        very_long = join(["word$i" for i in 1:250], " ")
        @test length(very_long) >= 1024
        @test n_channel(very_long) == GT1024
    end

    @testset "validate_n4l / validate_n4l_file API" begin
        @testset "Valid input" begin
            vr = validate_n4l("-section\n\n one (note) two\n"; config_dir=TEST_SST_CONFIG_DIR)
            @test vr.valid
            @test isempty(vr.errors)
            @test vr.node_count > 0
        end

        @testset "Invalid input" begin
            try
                vr = validate_n4l("one\n two\n"; config_dir=TEST_SST_CONFIG_DIR)
                @test !vr.valid
            catch e
                @test e isa N4LParseError
            end
        end

        @testset "validate_n4l_file on pass_1.in" begin
            pf = joinpath(TEST_SST_TESTS_DIR, "pass_1.in")
            vr = validate_n4l_file(pf; config_dir=TEST_SST_CONFIG_DIR)
            @test vr.valid
            @test isempty(vr.errors)
        end

        @testset "n4l_summary runs without error" begin
            result = parse_n4l("-section\n\n one (note) two\n"; config_dir=TEST_SST_CONFIG_DIR)
            buf = IOBuffer()
            n4l_summary(result; io=buf)
            output = String(take!(buf))
            @test occursin("N4L Summary", output)
            @test occursin("nodes", output)
        end
    end

    @testset "Parser role constants match Go" begin
        @test ROLE_EVENT == 1
        @test ROLE_RELATION == 2
        @test ROLE_SECTION == 3
        @test ROLE_CONTEXT == 4
        @test ROLE_CONTEXT_ADD == 5
        @test ROLE_CONTEXT_SUBTRACT == 6
        @test ROLE_BLANK_LINE == 7
        @test ROLE_LINE_ALIAS == 8
        @test ROLE_LOOKUP == 9
        @test ROLE_COMPOSITION == 11
        @test ROLE_RESULT == 12
    end
end
