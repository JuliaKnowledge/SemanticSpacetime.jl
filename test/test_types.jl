@testset "Types" begin
    @testset "STType enum" begin
        @test Int(NEAR) == 0
        @test Int(LEADSTO) == 1
        @test Int(CONTAINS) == 2
        @test Int(EXPRESS) == 3
    end

    @testset "ST index conversion" begin
        @test SemanticSpacetime.sttype_to_index(0) == ST_ZERO + 1   # NEAR
        @test SemanticSpacetime.sttype_to_index(3) == ST_TOP         # +EXPRESS
        @test SemanticSpacetime.sttype_to_index(-3) == 1             # -EXPRESS
        @test SemanticSpacetime.index_to_sttype(ST_ZERO + 1) == 0
        @test SemanticSpacetime.index_to_sttype(1) == -3
        @test SemanticSpacetime.index_to_sttype(ST_TOP) == 3
    end

    @testset "Constants" begin
        @test ST_ZERO == Int(EXPRESS)
        @test ST_TOP == 7
        @test CAUSAL_CONE_MAXLIMIT == 100
        @test length(SemanticSpacetime.ST_COLUMN_NAMES) == 7
    end

    @testset "NodePtr" begin
        np1 = NodePtr(1, 42)
        np2 = NodePtr(1, 42)
        np3 = NodePtr(2, 42)

        @test np1 == np2
        @test np1 != np3
        @test hash(np1) == hash(np2)
        @test NO_NODE_PTR == NodePtr(0, 0)
        @test sprint(show, np1) == "(1,42)"
    end

    @testset "Etc" begin
        etc = Etc()
        @test !etc.e && !etc.t && !etc.c
        @test sprint(show, etc) == "-"

        etc.e = true
        etc.c = true
        @test sprint(show, etc) == "EC"
    end

    @testset "Link" begin
        l1 = Link(1, 1.0f0, 0, NodePtr(1, 2))
        l2 = Link(1, 1.0f0, 0, NodePtr(1, 2))
        l3 = Link(2, 1.0f0, 0, NodePtr(1, 2))

        @test l1 == l2
        @test l1 != l3
        @test hash(l1) == hash(l2)
    end

    @testset "Node" begin
        n = Node("hello world", "chapter1")
        @test n.l == 11
        @test n.s == "hello world"
        @test n.chap == "chapter1"
        @test n.nptr == NO_NODE_PTR
        @test length(n.incidence) == ST_TOP
        @test all(isempty, n.incidence)
    end

    @testset "n_channel" begin
        @test n_channel("word") == N1GRAM
        @test n_channel("two words") == N2GRAM
        @test n_channel("three word phrase") == N3GRAM
        @test n_channel("this is a longer phrase") == LT128
        # Strings must have spaces for higher classes (n_channel counts spaces)
        @test n_channel(join(fill("w", 30), " ")) == LT128        # 59 chars, 29 spaces
        @test n_channel(join(fill("word", 100), " ")) == LT1024   # 499 chars
        @test n_channel(join(fill("word", 300), " ")) == GT1024   # 1499 chars
    end

    @testset "sql_escape" begin
        @test SemanticSpacetime.sql_escape("it's") == "it''s"
        @test SemanticSpacetime.sql_escape("no quotes") == "no quotes"
    end
end
