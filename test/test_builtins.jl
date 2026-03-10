@testset "Built-in Functions" begin
    @testset "expand_dynamic_functions no braces" begin
        @test expand_dynamic_functions("no braces here") == "no braces here"
        @test expand_dynamic_functions("hello") == "hello"
    end

    @testset "expand_dynamic_functions empty braces" begin
        result = expand_dynamic_functions("before {} after")
        @test isa(result, String)
    end

    @testset "evaluate_in_built" begin
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.add_mandatory_arrows!()
        chars = collect("{TimeUntil Hr14}")
        _, result = evaluate_in_built(chars, 1)
        @test isa(result, String)
    end

    @testset "do_in_built_function unknown" begin
        @test do_in_built_function(SubString{String}[]) == ""
        @test do_in_built_function(["Unknown"]) == ""
    end

    @testset "in_built_time_since" begin
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.add_mandatory_arrows!()
        result = in_built_time_since(["TimeSince", "Yr2020", "January", "Day1"])
        @test occursin("Years", result)
    end
end
