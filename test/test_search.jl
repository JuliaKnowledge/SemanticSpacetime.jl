@testset "Search" begin
    # Reset arrow state for tests
    SemanticSpacetime.reset_arrows!()

    @testset "SearchParameters construction" begin
        sp = SemanticSpacetime.SearchParameters()
        @test isempty(sp.names)
        @test sp.chapter == ""
        @test isempty(sp.context)
        @test isempty(sp.arrows)
        @test sp.seq_only == false
        @test sp.limit == CAUSAL_CONE_MAXLIMIT
        @test sp.from_node == NO_NODE_PTR
        @test sp.to_node == NO_NODE_PTR
        @test sp.orientation == ""
        @test sp.depth == 0
    end

    @testset "decode_search_field - empty" begin
        sp = SemanticSpacetime.decode_search_field("")
        @test isempty(sp.names)
        @test sp.chapter == ""
    end

    @testset "decode_search_field - chapter" begin
        sp = SemanticSpacetime.decode_search_field("chapter physics")
        @test sp.chapter == "physics"

        sp2 = SemanticSpacetime.decode_search_field("in biology")
        @test sp2.chapter == "biology"

        sp3 = SemanticSpacetime.decode_search_field("section math")
        @test sp3.chapter == "math"
    end

    @testset "decode_search_field - context" begin
        sp = SemanticSpacetime.decode_search_field("context quantum,mechanics")
        @test "quantum" in sp.context
        @test "mechanics" in sp.context
    end

    @testset "decode_search_field - sequence" begin
        sp = SemanticSpacetime.decode_search_field("sequence about gravity")
        @test sp.seq_only == true
        @test "gravity" in sp.names
    end

    @testset "decode_search_field - from/to" begin
        sp = SemanticSpacetime.decode_search_field("from alpha to beta")
        @test "alpha" in sp.names
        @test "beta" in sp.names
    end

    @testset "decode_search_field - range/limit" begin
        sp = SemanticSpacetime.decode_search_field("range 50")
        @test sp.limit == 50

        sp2 = SemanticSpacetime.decode_search_field("limit 25")
        @test sp2.limit == 25

        sp3 = SemanticSpacetime.decode_search_field("depth 3")
        @test sp3.depth == 3
    end

    @testset "decode_search_field - orientation" begin
        sp = SemanticSpacetime.decode_search_field("forward")
        @test sp.orientation == "forward"

        sp2 = SemanticSpacetime.decode_search_field("backward")
        @test sp2.orientation == "backward"
    end

    @testset "decode_search_field - notes" begin
        sp = SemanticSpacetime.decode_search_field("notes chemistry")
        @test sp.chapter == "chemistry"
    end

    @testset "decode_search_field - about/on/for" begin
        sp = SemanticSpacetime.decode_search_field("about relativity")
        @test "relativity" in sp.names

        sp2 = SemanticSpacetime.decode_search_field("on electrons")
        @test "electrons" in sp2.names
    end

    @testset "decode_search_field - bare words" begin
        sp = SemanticSpacetime.decode_search_field("photon energy")
        @test "photon" in sp.names
        @test "energy" in sp.names
    end

    @testset "decode_search_field - any wildcard" begin
        sp = SemanticSpacetime.decode_search_field("about any in physics")
        @test "%%" in sp.names
        @test sp.chapter == "physics"
    end

    @testset "decode_search_field - complex" begin
        sp = SemanticSpacetime.decode_search_field("sequence about gravity in physics limit 10")
        @test sp.seq_only == true
        @test "gravity" in sp.names
        @test sp.chapter == "physics"
        @test sp.limit == 10
    end

    @testset "node_where_string" begin
        where = SemanticSpacetime.node_where_string("test", "chap1", String[], ArrowPtr[], false)
        @test occursin("Search", where)
        @test occursin("Chap", where)

        where2 = SemanticSpacetime.node_where_string("", "", String[], ArrowPtr[], false)
        @test where2 == "true"

        where3 = SemanticSpacetime.node_where_string("test", "", String[], ArrowPtr[], true)
        @test occursin("Seq", where3)
    end

    # Cleanup
    SemanticSpacetime.reset_arrows!()
end
