@testset "Search Commands" begin
    @testset "Command constants" begin
        @test SemanticSpacetime.CMD_ON == "\\on"
        @test SemanticSpacetime.CMD_CHAPTER == "\\chapter"
        @test SemanticSpacetime.CMD_ON_2 == "on"
        @test SemanticSpacetime.CMD_STATS == "\\stats"
        @test SemanticSpacetime.CMD_STATS_2 == "stats"
        @test length(SemanticSpacetime.SEARCH_KEYWORDS) > 30
    end

    @testset "matches_cmd" begin
        @test SemanticSpacetime.matches_cmd("on", SemanticSpacetime.CMD_ON) == true
        @test SemanticSpacetime.matches_cmd("\\on", SemanticSpacetime.CMD_ON) == true
        @test SemanticSpacetime.matches_cmd("chapter", SemanticSpacetime.CMD_CHAPTER) == true
        @test SemanticSpacetime.matches_cmd("xyz", SemanticSpacetime.CMD_ON) == false
    end

    @testset "is_param" begin
        kw = SemanticSpacetime.SEARCH_KEYWORDS
        @test SemanticSpacetime.is_param(1, 3, ["hello", "world", "test"], kw) == true
        @test SemanticSpacetime.is_param(1, 3, ["\\chapter", "world", "test"], kw) == false
        @test SemanticSpacetime.is_param(5, 3, ["a", "b", "c"], kw) == false
    end

    @testset "fill_in_parameters" begin
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.add_mandatory_arrows!()

        # Chapter parsing
        parts = [["\\chapter", "mybook"]]
        param = SemanticSpacetime.fill_in_parameters(parts)
        @test param.chapter == "mybook"

        # Depth parsing
        parts2 = [["\\depth", "5"]]
        param2 = SemanticSpacetime.fill_in_parameters(parts2)
        @test param2.depth == 5

        # Stats
        parts3 = [["\\stats"]]
        param3 = SemanticSpacetime.fill_in_parameters(parts3)
        @test param3.stats == true

        # Sequence
        parts4 = [["\\sequence"]]
        param4 = SemanticSpacetime.fill_in_parameters(parts4)
        @test param4.seq_only == true

        # Context
        parts5 = [["\\context", "quantum,mechanics"]]
        param5 = SemanticSpacetime.fill_in_parameters(parts5)
        @test "quantum" in param5.context
        @test "mechanics" in param5.context

        # From/To
        parts6 = [["\\from", "alpha"], ["\\to", "beta"]]
        param6 = SemanticSpacetime.fill_in_parameters(parts6)
        @test "alpha" in param6.from_names
        @test "beta" in param6.to_names

        # Arrow (with registered arrow)
        parts7 = [["\\arrow", "then"]]
        param7 = SemanticSpacetime.fill_in_parameters(parts7)
        @test !isempty(param7.arrows)

        # Range
        parts8 = [["\\limit", "42"]]
        param8 = SemanticSpacetime.fill_in_parameters(parts8)
        @test param8.range_val == 42

        # Min/Max limits
        parts9 = [["\\min", "3"], ["\\max", "10"]]
        param9 = SemanticSpacetime.fill_in_parameters(parts9)
        @test 3 in param9.min_limits
        @test 10 in param9.max_limits

        # Page
        parts10 = [["\\page", "7"]]
        param10 = SemanticSpacetime.fill_in_parameters(parts10)
        @test param10.page_nr == 7

        # Horizon
        parts11 = [["\\new"]]
        param11 = SemanticSpacetime.fill_in_parameters(parts11)
        @test param11.horizon == SemanticSpacetime.RECENT

        parts12 = [["\\never"]]
        param12 = SemanticSpacetime.fill_in_parameters(parts12)
        @test param12.horizon == SemanticSpacetime.NEVER_HORIZON

        SemanticSpacetime.reset_arrows!()
    end

    @testset "decode_search_command" begin
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.add_mandatory_arrows!()

        param = SemanticSpacetime.decode_search_command("\\chapter mybook \\depth 3 test")
        @test param.chapter == "mybook"
        @test param.depth == 3
        @test "test" in param.names

        # Dirac notation
        param2 = SemanticSpacetime.decode_search_command("<a|ctx|b>")
        @test "b" in param2.from_names
        @test "a" in param2.to_names
        @test "ctx" in param2.context

        SemanticSpacetime.reset_arrows!()
    end
end
