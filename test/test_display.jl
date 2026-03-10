function _capture_stdout(f)
    old = stdout
    rd, wr = redirect_stdout()
    try
        f()
    finally
        redirect_stdout(old)
        close(wr)
    end
    return read(rd, String)
end

@testset "Display Functions" begin
    @testset "indent" begin
        @test indent(5) == "     "
        @test indent(0) == ""
    end

    @testset "show_time" begin
        @test show_time(1, 2, 3, 4) == "1 Years, 2 Days, 3 Hours, 4 Minutes"
        @test show_time(0, 0, 0, 5) == "5 Minutes"
        @test show_time(0, 0, 0, 0) == "0 Minutes"
        @test show_time(0, 1, 2, 30) == "1 Days, 2 Hours, 30 Minutes"
    end

    @testset "print_sta_index" begin
        @test print_sta_index(SemanticSpacetime.sttype_to_index(0)) == "NEAR"
        @test print_sta_index(SemanticSpacetime.sttype_to_index(1)) == "+LEADSTO"
        @test print_sta_index(SemanticSpacetime.sttype_to_index(-1)) == "-LEADSTO"
    end

    @testset "show_text" begin
        output = _capture_stdout() do
            show_text("Hello world this is a test")
        end
        @test occursin("Hello", output)
    end

    @testset "show_context" begin
        output = _capture_stdout() do
            show_context("ambient", "intent", "key")
        end
        @test occursin("ambient", output)
        @test occursin("intent", output)
        @test occursin("key", output)
    end

    @testset "print_node_orbit" begin
        store = MemoryStore()
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.add_mandatory_arrows!()
        n1 = mem_vertex!(store, "center", "ch1")
        n2 = mem_vertex!(store, "satellite", "ch1")
        mem_edge!(store, n1, "then", n2)

        output = _capture_stdout() do
            print_node_orbit(store, n1.nptr; limit=10)
        end
        @test occursin("center", output)
    end

    @testset "print_link_orbit empty" begin
        satellites = [Orbit[] for _ in 1:ST_TOP]
        output = _capture_stdout() do
            print_link_orbit(satellites, Int(LEADSTO))
        end
        @test output == ""
    end
end
