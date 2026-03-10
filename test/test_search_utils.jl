@testset "Search Utilities" begin
    @testset "split_quotes" begin
        @test split_quotes("hello world") == ["hello", "world"]
        @test split_quotes("\"hello world\"") == ["\"hello world\""]
        @test split_quotes("find (1,2) here") == ["find", "(1,2)", "here"]
        @test split_quotes("") == String[]
    end

    @testset "deq" begin
        @test deq("\"hello\"") == "hello"
        @test deq("hello") == "hello"
    end

    @testset "is_literal_nptr" begin
        @test is_literal_nptr("(1,2)") == true
        @test is_literal_nptr("(10,345)") == true
        @test is_literal_nptr("hello") == false
        @test is_literal_nptr("(a,b)") == false
    end

    @testset "is_nptr_str" begin
        @test is_nptr_str("(1,2)") == true
        @test is_nptr_str("(10,345)") == true
        @test is_nptr_str("hello") == false
        @test is_nptr_str("") == false
    end

    @testset "is_bracketed_search_term" begin
        isb, s = is_bracketed_search_term("(test)")
        @test isb == true
        @test s == "test"
        isb2, s2 = is_bracketed_search_term("test")
        @test isb2 == false
    end

    @testset "is_bracketed_search_list" begin
        found, result = is_bracketed_search_list(["(foo)", "bar"])
        @test found == true
        @test result[1] == "|foo|"
        @test result[2] == "bar"
    end

    @testset "is_exact_match" begin
        is_ex, s = is_exact_match("!hello!")
        @test is_ex == true
        @test s == "hello"
        is_ex2, s2 = is_exact_match("|world|")
        @test is_ex2 == true
        @test s2 == "world"
        is_ex3, s3 = is_exact_match("hello")
        @test is_ex3 == false
    end

    @testset "is_string_fragment" begin
        @test is_string_fragment("hello world") == true
        @test is_string_fragment("hello-world") == true
        @test is_string_fragment("a|b") == false
        @test is_string_fragment("hi") == false
    end

    @testset "is_command" begin
        @test is_command("notes", ["notes", "browse"]) == true
        @test is_command("xyz", ["notes", "browse"]) == false
    end

    @testset "something_like" begin
        @test something_like("notes", ["notes", "browse"]) == "notes"
        @test something_like("xyz", ["notes", "browse"]) == "xyz"
    end

    @testset "parse_literal_node_ptrs" begin
        ptrs, rest = parse_literal_node_ptrs(["(1,2)", "hello", "(3,4)"])
        @test length(ptrs) == 2
        @test ptrs[1] == NodePtr(1, 2)
        @test ptrs[2] == NodePtr(3, 4)
        @test rest == ["hello"]
    end

    @testset "search_term_len" begin
        @test search_term_len(["hi", "hello", "(1,2)"]) == 5
        @test search_term_len(String[]) == 0
    end

    @testset "all_exact" begin
        @test all_exact(["!hello!", "world"]) == true
        @test all_exact(["hello", "world"]) == false
    end

    @testset "check queries" begin
        @test check_help_query("\\help") != "\\help"
        @test check_help_query("test") == "test"
        @test check_nptr_query("", "1", "2") == "(1,2)"
        @test check_nptr_query("test", "", "") == "test"
    end

    @testset "check_concept_query" begin
        result = check_concept_query("\\concept test")
        @test occursin("arrow", result)
        @test check_concept_query("normal query") == "normal query"
    end

    @testset "add_orphan" begin
        params = SearchParameters()
        add_orphan(params, "test")
        @test "test" in params.names
    end

    @testset "arrow_ptr_from_names" begin
        SemanticSpacetime.reset_arrows!()
        add_mandatory_arrows!()
        arr, stt = arrow_ptr_from_names(["then"])
        @test !isempty(arr) || !isempty(stt)
        SemanticSpacetime.reset_arrows!()
    end

    @testset "solve_node_ptrs" begin
        SemanticSpacetime.reset_arrows!()
        add_mandatory_arrows!()
        store = MemoryStore()
        n1 = mem_vertex!(store, "hello", "ch1")
        n2 = mem_vertex!(store, "world", "ch1")
        ptrs = solve_node_ptrs(store, ["hello"])
        @test !isempty(ptrs)
        SemanticSpacetime.reset_arrows!()
    end

    @testset "min_max_policy" begin
        params = SearchParameters()
        push!(params.names, "test")
        minl, maxl = min_max_policy(params)
        @test minl >= 1
        @test maxl > 0
    end

    @testset "score_context" begin
        @test score_context(1, 2) == true
    end

    @testset "is_quote_char" begin
        @test is_quote_char('"') == true
        @test is_quote_char('\'') == true
        @test is_quote_char('\u201c') == true
        @test is_quote_char('a') == false
    end

    @testset "read_to_next" begin
        chars = collect("hello)")
        s, offset = read_to_next(chars, 1, ')')
        @test s == "hello)"
        @test offset == 6
    end
end
