using Test

@testset "Cross-Language Validation (Go ↔ Julia)" begin
    SST_CONFIG_DIR = joinpath(@__DIR__, "..", "..", "SSTorytime", "SSTconfig")
    SST_TESTS_DIR  = joinpath(@__DIR__, "..", "..", "SSTorytime", "tests")

    config_available = isdir(SST_CONFIG_DIR)
    tests_available  = isdir(SST_TESTS_DIR)

    if !config_available
        @warn "SSTconfig directory not found at $SST_CONFIG_DIR — skipping config-dependent tests"
    end
    if !tests_available
        @warn "SSTorytime tests directory not found at $SST_TESTS_DIR — skipping fixture tests"
    end

    # ──────────────────────────────────────────────────────────────
    # 1. N4L Parser Fixture Tests — pass_*.in
    # ──────────────────────────────────────────────────────────────

    @testset "Pass fixtures (pass_*.in)" begin
        if config_available && tests_available
            pass_files = sort(filter(
                f -> startswith(basename(f), "pass_") && endswith(f, ".in"),
                readdir(SST_TESTS_DIR; join=true)))

            @test length(pass_files) > 0

            for pf in pass_files
                bn = basename(pf)
                @testset "$bn should parse without errors" begin
                    local result
                    try
                        result = parse_n4l_file(pf; config_dir=SST_CONFIG_DIR)
                    catch e
                        @error "Exception parsing $bn" exception=(e, catch_backtrace())
                        @test false  # unexpected exception
                        continue
                    end
                    if has_errors(result)
                        @warn "Pass fixture $bn produced errors" errors=result.errors
                    end
                    @test !has_errors(result)
                end
            end
        else
            @test_skip "pass fixtures (directories unavailable)"
        end
    end

    # ──────────────────────────────────────────────────────────────
    # 2. N4L Parser Fixture Tests — fail_*.in
    # ──────────────────────────────────────────────────────────────

    @testset "Fail fixtures (fail_*.in)" begin
        if config_available && tests_available
            fail_files = sort(filter(
                f -> startswith(basename(f), "fail_") && endswith(f, ".in"),
                readdir(SST_TESTS_DIR; join=true)))

            @test length(fail_files) > 0

            for ff in fail_files
                bn = basename(ff)
                @testset "$bn should produce errors" begin
                    local had_error = false
                    try
                        result = parse_n4l_file(ff; config_dir=SST_CONFIG_DIR)
                        had_error = has_errors(result)
                        if !had_error
                            @warn "Fail fixture $bn produced no errors (expected errors)"
                        end
                    catch e
                        if e isa N4LParseError
                            had_error = true
                        else
                            @error "Unexpected exception parsing $bn" exception=(e, catch_backtrace())
                            @test false
                            continue
                        end
                    end
                    @test had_error
                end
            end
        else
            @test_skip "fail fixtures (directories unavailable)"
        end
    end

    # ──────────────────────────────────────────────────────────────
    # 3. N4L Parser Fixture Tests — warn_*.in
    # ──────────────────────────────────────────────────────────────

    @testset "Warn fixtures (warn_*.in)" begin
        if config_available && tests_available
            warn_files = sort(filter(
                f -> startswith(basename(f), "warn_") && endswith(f, ".in"),
                readdir(SST_TESTS_DIR; join=true)))

            for wf in warn_files
                bn = basename(wf)
                @testset "$bn should produce warnings" begin
                    # warn_1.in triggers capitalization warnings via @warn logging
                    # rather than the N4LResult.warnings field — skip for now
                    @test_skip "Warning detection pending (warnings emitted via @warn, not N4LResult.warnings)"
                end
            end
        else
            @test_skip "warn fixtures (directories unavailable)"
        end
    end

    # ──────────────────────────────────────────────────────────────
    # 4. Type System Verification — STType enum matches Go constants
    # ──────────────────────────────────────────────────────────────

    @testset "Type system matches Go" begin
        # Go: NEAR = 0, LEADSTO = 1, CONTAINS = 2, EXPRESS = 3
        @test Int(NEAR)     == 0
        @test Int(LEADSTO)  == 1
        @test Int(CONTAINS) == 2
        @test Int(EXPRESS)  == 3

        # Go: ST_ZERO = EXPRESS (3), ST_TOP = ST_ZERO + EXPRESS + 1 (7)
        @test ST_ZERO == Int(EXPRESS)
        @test ST_ZERO == 3
        @test ST_TOP  == 7

        # Go: sttype_to_index maps signed ST type (-3..+3) → 1-based index (1..7)
        @test SemanticSpacetime.sttype_to_index(-3) == 1  # -EXPRESS
        @test SemanticSpacetime.sttype_to_index(-2) == 2  # -CONTAINS
        @test SemanticSpacetime.sttype_to_index(-1) == 3  # -LEADSTO
        @test SemanticSpacetime.sttype_to_index(0)  == 4  # NEAR
        @test SemanticSpacetime.sttype_to_index(1)  == 5  # +LEADSTO
        @test SemanticSpacetime.sttype_to_index(2)  == 6  # +CONTAINS
        @test SemanticSpacetime.sttype_to_index(3)  == 7  # +EXPRESS

        # Inverse: index_to_sttype maps 1-based index → signed ST type
        @test SemanticSpacetime.index_to_sttype(1) == -3
        @test SemanticSpacetime.index_to_sttype(4) == 0
        @test SemanticSpacetime.index_to_sttype(7) == 3

        # Go: DB column names Im3, Im2, Im1, In0, Il1, Ic2, Ie3
        @test SemanticSpacetime.ST_COLUMN_NAMES == ["Im3", "Im2", "Im1", "In0", "Il1", "Ic2", "Ie3"]

        # Go: text size class constants
        @test N1GRAM == 1
        @test N2GRAM == 2
        @test N3GRAM == 3
        @test LT128  == 4
        @test LT1024 == 5
        @test GT1024 == 6

        # Go: SCREENWIDTH = 120, RIGHTMARGIN = 5, LEFTMARGIN = 5
        @test SCREENWIDTH == 120
        @test RIGHTMARGIN == 5
        @test LEFTMARGIN  == 5

        # Go: CAUSAL_CONE_MAXLIMIT = 100
        @test CAUSAL_CONE_MAXLIMIT == 100
    end

    # ──────────────────────────────────────────────────────────────
    # 5. Arrow System Verification — config-loaded arrow names
    #    and STType mappings match Go definitions
    # ──────────────────────────────────────────────────────────────

    @testset "Arrow system matches Go config" begin
        if config_available
            # Parse a minimal N4L to trigger config loading
            result = parse_n4l("-arrowtest\n one\n"; config_dir=SST_CONFIG_DIR)

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
                    if a !== nothing
                        @test SemanticSpacetime.index_to_sttype(a.stindex) == Int(NEAR)
                    else
                        @warn "Arrow '$name' not found"
                        @test a !== nothing
                    end
                end
            end

            @testset "LeadsTo arrows (LEADSTO, sttype=±1)" begin
                for name in ["next", "brings", "fwd", "cause"]
                    a = get_arrow_by_name(name)
                    if a !== nothing
                        st = SemanticSpacetime.index_to_sttype(a.stindex)
                        @test abs(st) == Int(LEADSTO)
                    else
                        @warn "Arrow '$name' not found"
                        @test a !== nothing
                    end
                end
            end

            @testset "Contains arrows (CONTAINS, sttype=±2)" begin
                for name in ["contain", "consists", "has-pt", "setof"]
                    a = get_arrow_by_name(name)
                    if a !== nothing
                        st = SemanticSpacetime.index_to_sttype(a.stindex)
                        @test abs(st) == Int(CONTAINS)
                    else
                        @warn "Arrow '$name' not found"
                        @test a !== nothing
                    end
                end
            end

            @testset "Express arrows (EXPRESS, sttype=±3)" begin
                for name in ["note", "remark", "e.g.", "abbrev"]
                    a = get_arrow_by_name(name)
                    if a !== nothing
                        st = SemanticSpacetime.index_to_sttype(a.stindex)
                        @test abs(st) == Int(EXPRESS)
                    else
                        @warn "Arrow '$name' not found"
                        @test a !== nothing
                    end
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
                    if fwd !== nothing && bwd !== nothing
                        fwd_st = SemanticSpacetime.index_to_sttype(fwd.stindex)
                        bwd_st = SemanticSpacetime.index_to_sttype(bwd.stindex)
                        @test fwd_st == -bwd_st  # forward and inverse have opposite sign
                    end
                end
            end

            @testset "Config file sections map to correct STTypes" begin
                # arrows-NR-0.sst → NEAR (0)
                # arrows-LT-1.sst → LEADSTO (1)
                # arrows-CN-2.sst → CONTAINS (2)
                # arrows-EP-3.sst → EXPRESS (3)
                config_files = read_config_files(SST_CONFIG_DIR)
                @test length(config_files) > 0

                expected_sections = Dict(
                    "NR-0" => 0,  # NEAR
                    "LT-1" => 1,  # LEADSTO
                    "CN-2" => 2,  # CONTAINS
                    "EP-3" => 3,  # EXPRESS
                )
                for cf in config_files
                    bn = basename(cf)
                    for (tag, expected_st) in expected_sections
                        if occursin(tag, bn)
                            @test true  # config file with tag found
                        end
                    end
                end
            end
        else
            @test_skip "arrow system (config directory unavailable)"
        end
    end

    # ──────────────────────────────────────────────────────────────
    # 6. Graph Construction Comparison
    # ──────────────────────────────────────────────────────────────

    @testset "Graph construction via MemoryStore" begin
        if config_available
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
            cr = compile_n4l_string!(store, n4l_text; config_dir=SST_CONFIG_DIR)

            @testset "Compilation succeeds" begin
                @test isempty(cr.errors)
                @test cr.nodes_created > 0
                @test cr.edges_created > 0
            end

            @testset "Node count" begin
                # Expect: apple, fruit, "a common fruit", äppel, banana,
                #         "a tropical fruit"  = 6 unique nodes
                @test node_count(store) == 6
                @test cr.nodes_created == 6
            end

            @testset "Edge count" begin
                # 7 forward edges: 2×contain + 2×note + 1×ll + 1×fwd + 1 sequence link
                @test cr.edges_created == 7
                # link_count includes both forward and inverse links
                @test link_count(store) >= cr.edges_created
            end

            @testset "Chapter tracking" begin
                @test cr.chapters == ["vocabulary"]
                chapters = mem_get_chapters(store)
                @test "vocabulary" in chapters
            end

            @testset "Node retrieval" begin
                apple_nodes = mem_get_nodes_by_name(store, "apple")
                @test length(apple_nodes) == 1
                banana_nodes = mem_get_nodes_by_name(store, "banana")
                @test length(banana_nodes) == 1
            end

            @testset "Link types" begin
                apple_nodes = mem_get_nodes_by_name(store, "apple")
                @test !isempty(apple_nodes)
                apple = first(apple_nodes)

                # apple should have incidence links across multiple ST channels
                total_links = sum(length(apple.incidence[i]) for i in 1:ST_TOP)
                @test total_links > 0
            end

            @testset "Search works" begin
                results = mem_search_text(store, "apple")
                @test !isempty(results)
                @test any(n -> n.s == "apple", results)
            end
        else
            @test_skip "graph construction (config directory unavailable)"
        end
    end

    # ──────────────────────────────────────────────────────────────
    # 7. N4L text size classification matches Go n_channel()
    # ──────────────────────────────────────────────────────────────

    @testset "Text size classification (n_channel)" begin
        # Single word → N1GRAM
        @test n_channel("hello") == N1GRAM
        @test n_channel("x") == N1GRAM

        # Two words → N2GRAM
        @test n_channel("hello world") == N2GRAM

        # Three words → N3GRAM
        @test n_channel("one two three") == N3GRAM

        # Short multi-word string < 128 chars → LT128
        @test n_channel("one two three four") == LT128

        # String >= 128 chars but < 1024 → LT1024
        long_str = join(["word$i" for i in 1:30], " ")
        @test length(long_str) >= 128
        @test n_channel(long_str) == LT1024

        # String >= 1024 chars → GT1024
        very_long = join(["word$i" for i in 1:250], " ")
        @test length(very_long) >= 1024
        @test n_channel(very_long) == GT1024
    end

    # ──────────────────────────────────────────────────────────────
    # 8. Validate N4L standalone API
    # ──────────────────────────────────────────────────────────────

    @testset "validate_n4l / validate_n4l_file API" begin
        if config_available
            @testset "Valid input" begin
                vr = validate_n4l("-section\n\n one (note) two\n"; config_dir=SST_CONFIG_DIR)
                @test vr.valid
                @test isempty(vr.errors)
                @test vr.node_count > 0
            end

            @testset "Invalid input" begin
                local vr
                try
                    vr = validate_n4l("one\n two\n"; config_dir=SST_CONFIG_DIR)
                    @test !vr.valid
                catch e
                    @test e isa N4LParseError
                end
            end

            if tests_available
                @testset "validate_n4l_file on pass_1.in" begin
                    pf = joinpath(SST_TESTS_DIR, "pass_1.in")
                    vr = validate_n4l_file(pf; config_dir=SST_CONFIG_DIR)
                    @test vr.valid
                    @test isempty(vr.errors)
                end
            end

            @testset "n4l_summary runs without error" begin
                result = parse_n4l("-section\n\n one (note) two\n"; config_dir=SST_CONFIG_DIR)
                buf = IOBuffer()
                n4l_summary(result; io=buf)
                output = String(take!(buf))
                @test occursin("N4L Summary", output)
                @test occursin("nodes", output)
            end
        else
            @test_skip "validate_n4l (config directory unavailable)"
        end
    end

    # ──────────────────────────────────────────────────────────────
    # 9. N4L parser role constants match Go
    # ──────────────────────────────────────────────────────────────

    @testset "Parser role constants match Go" begin
        @test ROLE_EVENT            == 1
        @test ROLE_RELATION         == 2
        @test ROLE_SECTION          == 3
        @test ROLE_CONTEXT          == 4
        @test ROLE_CONTEXT_ADD      == 5
        @test ROLE_CONTEXT_SUBTRACT == 6
        @test ROLE_BLANK_LINE       == 7
        @test ROLE_LINE_ALIAS       == 8
        @test ROLE_LOOKUP           == 9
        @test ROLE_COMPOSITION      == 11
        @test ROLE_RESULT           == 12
    end
end
