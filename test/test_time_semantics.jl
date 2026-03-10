using Dates

@testset "Time Semantics" begin
    @testset "season" begin
        n, s = season("January")
        @test n == "N_Winter"
        @test s == "S_Summer"

        n, s = season("July")
        @test n == "N_Summer"
        @test s == "S_Winter"

        n, s = season("April")
        @test n == "N_Spring"
        @test s == "S_Autumn"

        n, s = season("October")
        @test n == "N_Autumn"
        @test s == "S_Spring"

        n, s = season("InvalidMonth")
        @test n == "hurricane"
        @test s == "typhoon"
    end

    @testset "do_nowt" begin
        dt = DateTime(2024, 6, 15, 14, 30, 0)
        when, key = do_nowt(dt)

        @test occursin("N_Summer", when)
        @test occursin("S_Winter", when)
        @test occursin("Afternoon", when)
        @test occursin("June", when)
        @test occursin("Yr2024", when)
        @test occursin("Hr14", key)
        @test occursin("Qu3", key)  # minute 30 → quarter 3
    end

    @testset "do_nowt edge cases" begin
        # Midnight
        dt = DateTime(2024, 1, 1, 0, 0, 0)
        when, key = do_nowt(dt)
        @test occursin("Night", when)
        @test occursin("January", when)
        @test occursin("Hr00", key)

        # Evening
        dt = DateTime(2024, 12, 25, 22, 45, 0)
        when, key = do_nowt(dt)
        @test occursin("Evening", when)
        @test occursin("December", when)
    end

    @testset "get_time_context" begin
        context, key, ts = get_time_context()
        @test !isempty(context)
        @test !isempty(key)
        @test ts > 0
    end

    @testset "get_time_from_semantics" begin
        now = DateTime(2024, 6, 15, 10, 0, 0)

        # Test with specific day and hour
        result = get_time_from_semantics(["cmd", "Day20", "Hr14"], now)
        @test Dates.day(result) == 20
        @test Dates.hour(result) == 14

        # Test with year
        result = get_time_from_semantics(["cmd", "Yr2025", "Day1"], now)
        @test Dates.year(result) == 2025
        @test Dates.day(result) == 1

        # Test with month
        result = get_time_from_semantics(["cmd", "March"], now)
        @test Dates.month(result) == 3

        # Test with weekday
        result = get_time_from_semantics(["cmd", "Monday"], now)
        @test Dates.dayofweek(result) == 1  # Monday
    end

    @testset "GR constants" begin
        @test length(GR_MONTH_TEXT) == 12
        @test GR_MONTH_TEXT[1] == "January"
        @test GR_MONTH_TEXT[12] == "December"

        @test length(GR_DAY_TEXT) == 7
        @test GR_DAY_TEXT[1] == "Monday"

        @test length(GR_SHIFT_TEXT) == 4
        @test GR_SHIFT_TEXT[1] == "Night"
        @test GR_SHIFT_TEXT[2] == "Morning"
    end
end
