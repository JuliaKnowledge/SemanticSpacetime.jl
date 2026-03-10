using Test

@testset "N4L Parser" begin
    SST_CONFIG_DIR = joinpath(@__DIR__, "..", "..", "SSTorytime", "SSTconfig")
    SST_TESTS_DIR = joinpath(@__DIR__, "..", "..", "SSTorytime", "tests")

    config_available = isdir(SST_CONFIG_DIR)
    tests_available = isdir(SST_TESTS_DIR)

    if !config_available
        @warn "SSTconfig directory not found at $SST_CONFIG_DIR, skipping config-dependent tests"
    end
    if !tests_available
        @warn "SSTorytime tests directory not found at $SST_TESTS_DIR, skipping fixture tests"
    end

    @testset "Basic parsing functions" begin
        @testset "extract_context_expression" begin
            @test SemanticSpacetime.extract_context_expression(":: food ::") == "food"
            @test SemanticSpacetime.extract_context_expression(":: food, drink ::") == "food, drink"
            @test SemanticSpacetime.extract_context_expression("+:: more ::") == "more"
            @test SemanticSpacetime.extract_context_expression("-:: less :") == "less"
        end

        @testset "clean_expression" begin
            @test SemanticSpacetime.clean_expression("a,b,c") == "a|b|c"
            @test SemanticSpacetime.clean_expression("a|b|c") == "a|b|c"
            @test SemanticSpacetime.clean_expression("a&&b") == "a.b"
        end

        @testset "trim_paren" begin
            @test SemanticSpacetime.trim_paren("(abc)") == "abc"
            @test SemanticSpacetime.trim_paren("abc") == "abc"
            @test SemanticSpacetime.trim_paren("") == ""
            @test SemanticSpacetime.trim_paren("(a)(b)") == "(a)(b)"
        end

        @testset "split_with_parens_intact" begin
            result = SemanticSpacetime.split_with_parens_intact("a|b|c", '|')
            @test result == ["a", "b", "c"]
            result = SemanticSpacetime.split_with_parens_intact("a|(b.c)|d", '|')
            @test result == ["a", "(b.c)", "d"]
        end

        @testset "is_quote" begin
            @test SemanticSpacetime.is_quote('"')
            @test SemanticSpacetime.is_quote('\'')
            @test !SemanticSpacetime.is_quote('a')
        end

        @testset "note_to_self detection" begin
            st = SemanticSpacetime.N4LState()
            @test SemanticSpacetime.note_to_self(st, "TODO FIX THIS") == true
            @test SemanticSpacetime.note_to_self(st, "normal text") == false
            @test SemanticSpacetime.note_to_self(st, "AB") == false  # too short
        end
    end

    @testset "N4LState construction" begin
        st = N4LState()
        @test st.line_num == 1
        @test st.line_item_state == ROLE_BLANK_LINE
        @test st.section_state == ""
        @test st.sequence_mode == false
        @test isempty(st.errors)
    end

    @testset "Mandatory arrows" begin
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.reset_contexts!()
        add_mandatory_arrows!()

        @test get_arrow_by_name("empty") !== nothing
        @test get_arrow_by_name("void") !== nothing
        @test get_arrow_by_name("then") !== nothing
        @test get_arrow_by_name("from") !== nothing
        @test get_arrow_by_name("url") !== nothing
        @test get_arrow_by_name("img") !== nothing
    end

    @testset "Config file parsing" begin
        if config_available
            SemanticSpacetime.reset_arrows!()
            SemanticSpacetime.reset_contexts!()
            add_mandatory_arrows!()
            st = N4LState()
            for cf in read_config_files(SST_CONFIG_DIR)
                parse_config_file(cf; st=st)
            end

            # Check that standard arrows are registered
            @test get_arrow_by_name("note") !== nothing
            @test get_arrow_by_name("eh") !== nothing
            @test get_arrow_by_name("ph") !== nothing
            @test get_arrow_by_name("he") !== nothing
            @test get_arrow_by_name("cause") !== nothing
            @test get_arrow_by_name("nr") !== nothing
            @test get_arrow_by_name("eq") !== nothing
        end
    end

    @testset "Simple N4L parsing" begin
        if config_available
            @testset "Section and item" begin
                result = parse_n4l("-test section\n\n one\n two\n"; config_dir=SST_CONFIG_DIR)
                @test !has_errors(result)
            end

            @testset "Context declaration" begin
                result = parse_n4l("-section\n\n:: food, drink ::\n\n item1\n"; config_dir=SST_CONFIG_DIR)
                @test !has_errors(result)
            end

            @testset "Relation" begin
                result = parse_n4l("-section\n\n one (note) two\n"; config_dir=SST_CONFIG_DIR)
                @test !has_errors(result)
            end

            @testset "Ditto mark" begin
                result = parse_n4l("-section\n\n one (note) two\n \" (note) three\n"; config_dir=SST_CONFIG_DIR)
                @test !has_errors(result)
            end

            @testset "Context add/subtract" begin
                result = parse_n4l("-section\n\n:: ctx1 ::\n+:: ctx2 ::\n item1\n-:: ctx2 ::\n item2\n"; config_dir=SST_CONFIG_DIR)
                @test !has_errors(result)
            end

            @testset "Comments ignored" begin
                result = parse_n4l("-section\n# comment\n one\n// also comment\n two\n"; config_dir=SST_CONFIG_DIR)
                @test !has_errors(result)
            end

            @testset "Alias and reference" begin
                result = parse_n4l("-section\n\n@myalias one (note) two\n\n \$myalias.1 (note) three\n"; config_dir=SST_CONFIG_DIR)
                @test !has_errors(result)
            end

            @testset "Missing section produces error" begin
                local had_error = false
                try
                    result = parse_n4l("one\n two\n"; config_dir=SST_CONFIG_DIR)
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

    @testset "Pass test fixtures" begin
        if config_available && tests_available
            pass_files = filter(f -> startswith(basename(f), "pass_") && endswith(f, ".in"),
                               readdir(SST_TESTS_DIR; join=true))
            for pf in sort(pass_files)
                bn = basename(pf)
                @testset "$bn" begin
                    result = parse_n4l_file(pf; config_dir=SST_CONFIG_DIR)
                    if has_errors(result)
                        @warn "Unexpected errors in $bn" errors=result.errors
                    end
                    @test !has_errors(result)
                end
            end
        end
    end

    @testset "Fail test fixtures" begin
        if config_available && tests_available
            fail_files = filter(f -> startswith(basename(f), "fail_") && endswith(f, ".in"),
                               readdir(SST_TESTS_DIR; join=true))
            for ff in sort(fail_files)
                bn = basename(ff)
                @testset "$bn" begin
                    local had_error = false
                    try
                        result = parse_n4l_file(ff; config_dir=SST_CONFIG_DIR)
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
    end
end
