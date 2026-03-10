@testset "SQL Utilities" begin
    @testset "sql_escape" begin
        @test SemanticSpacetime.sql_escape("it's") == "it''s"
        @test SemanticSpacetime.sql_escape("no quotes") == "no quotes"
    end

    @testset "format_sql_string_array" begin
        @test format_sql_string_array(String[]) == "'{ }'"
        r = format_sql_string_array(["a", "b"])
        @test occursin("\"a\"", r)
        @test occursin("\"b\"", r)
    end

    @testset "format_sql_int_array" begin
        @test format_sql_int_array(Int[]) == "'{ }'"
        r = format_sql_int_array([3, 1, 2])
        @test occursin("1", r)
        @test occursin("2", r)
        @test occursin("3", r)
    end

    @testset "format_sql_nodeptr_array" begin
        @test format_sql_nodeptr_array(NodePtr[]) == "'{ }'"
        r = format_sql_nodeptr_array([NodePtr(1, 2)])
        @test occursin("(1,2)", r)
    end

    @testset "format_sql_link_array" begin
        lnk = Link(77, 0.5f0, 334, NodePtr(4, 2))
        r = format_sql_link_array([lnk])
        @test occursin("77", r)
        @test occursin("4,2", r)
    end

    @testset "parse_sql_array_string" begin
        @test parse_sql_array_string("{\"a\",\"b\",c}") == ["a", "b", "c"]
        @test parse_sql_array_string("{ }") == []  || parse_sql_array_string("{ }") == [""]
    end

    @testset "parse_sql_nptr_array" begin
        ptrs = parse_sql_nptr_array("{\"(1,2)\",\"(3,4)\"}")
        @test length(ptrs) == 2
        @test ptrs[1] == NodePtr(1, 2)
        @test ptrs[2] == NodePtr(3, 4)
    end

    @testset "parse_sql_link_string" begin
        lnk = parse_sql_link_string("77,0.5,334,4,2")
        @test Int(lnk.arr) == 77
        @test lnk.dst == NodePtr(4, 2)
        @test Int(lnk.ctx) == 334
    end

    @testset "parse_sql_link_string short" begin
        lnk = parse_sql_link_string("77,0.5")
        @test lnk.dst == NO_NODE_PTR
    end

    @testset "parse_link_array" begin
        links = SemanticSpacetime.parse_link_array("{}")
        @test isempty(links)
    end

    @testset "parse_link_path" begin
        paths = parse_link_path("")
        @test isempty(paths)
    end

    @testset "storage_class" begin
        _, c = storage_class("hello")
        @test c == N1GRAM
        _, c2 = storage_class("hello world")
        @test c2 == N2GRAM
        _, c3 = storage_class("hello world foo")
        @test c3 == N3GRAM
        _, c4 = storage_class("a b c d")
        @test c4 == LT128
    end

    @testset "sttype_db_channel" begin
        @test sttype_db_channel(0) == "In0"
        @test sttype_db_channel(1) == "Il1"
        @test sttype_db_channel(2) == "Ic2"
        @test sttype_db_channel(3) == "Ie3"
        @test sttype_db_channel(-1) == "Im1"
        @test sttype_db_channel(-2) == "Im2"
        @test sttype_db_channel(-3) == "Im3"
        @test_throws ErrorException sttype_db_channel(4)
    end

    @testset "sttype_name" begin
        @test sttype_name(0) == "=Similarity"
        @test sttype_name(1) == "+leads to"
        @test sttype_name(2) == "+contains"
        @test sttype_name(3) == "+property"
        @test sttype_name(-1) == "-comes from"
        @test sttype_name(-2) == "-contained by"
        @test sttype_name(-3) == "-is property of"
    end

    @testset "dirac_notation" begin
        ok, beg_t, fin_t, ctx = dirac_notation("<a|b>")
        @test ok == true
        @test beg_t == "b"
        @test fin_t == "a"
        @test ctx == ""

        ok2, beg2, fin2, ctx2 = dirac_notation("<a|ctx|b>")
        @test ok2 == true
        @test beg2 == "b"
        @test ctx2 == "ctx"
        @test fin2 == "a"

        ok3, _, _, _ = dirac_notation("not dirac")
        @test ok3 == false

        ok4, _, _, _ = dirac_notation("")
        @test ok4 == false
    end

    @testset "array/string conversions" begin
        @test array2str(["a", "b"]) == "a, b"
        @test array2str(String[]) == ""
        arr, n = str2array("{a,b,c}")
        @test length(arr) == 3
        @test n == 3
    end

    @testset "escape_json_string" begin
        @test escape_json_string("hello\nworld") == "helloworld"
        @test escape_json_string("say \"hi\"") == "say \\\"hi\\\""
    end

    @testset "context_string" begin
        @test context_string(["a", "b", "c"]) == "a b c"
        @test context_string(String[]) == ""
    end

    @testset "similar_string" begin
        @test similar_string("hello world", "hello") == true
        @test similar_string("hello", "hello") == true
        @test similar_string("hello", "any") == true
        @test similar_string("any", "hello") == true
        @test similar_string("", "hello") == true
        @test similar_string("hello", "xyz") == false
    end

    @testset "in_list" begin
        idx, found = in_list("b", ["a", "b", "c"])
        @test found == true
        @test idx == 2
        idx2, found2 = in_list("x", ["a", "b"])
        @test found2 == false
    end

    @testset "match_arrows" begin
        @test match_arrows(ArrowPtr[1, 2, 3], ArrowPtr(2)) == true
        @test match_arrows(ArrowPtr[1, 2, 3], ArrowPtr(5)) == false
    end

    @testset "match_contexts" begin
        @test match_contexts(String[], ContextPtr(0)) == true
        @test match_contexts(["test"], ContextPtr(0)) == true
    end

    @testset "matches_in_context" begin
        @test matches_in_context("hello", ["hello", "world"]) == true
        @test matches_in_context("xyz", ["hello", "world"]) == false
    end

    @testset "arrow2int" begin
        @test arrow2int(ArrowPtr[1, 2, 3]) == [1, 2, 3]
        @test arrow2int(ArrowPtr[]) == Int[]
    end
end
