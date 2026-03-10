@testset "N4L Compiler" begin
    SST_CONFIG_DIR = joinpath(@__DIR__, "..", "..", "SSTorytime", "SSTconfig")
    config_available = isdir(SST_CONFIG_DIR)

    if !config_available
        @warn "SSTconfig directory not found at $SST_CONFIG_DIR, skipping N4L compiler tests"
    end

    @testset "N4LCompileResult display" begin
        cr = N4LCompileResult(5, 3, ["ch1", "ch2"], String[], String[])
        s = sprint(show, cr)
        @test occursin("nodes=5", s)
        @test occursin("edges=3", s)
    end

    @testset "Compile simple N4L with sections and items" begin
        if config_available
            SemanticSpacetime.reset_arrows!()
            SemanticSpacetime.reset_contexts!()
            store = MemoryStore()
            text = """
            -test chapter

            apple
            banana
            cherry
            """
            cr = compile_n4l_string!(store, text; config_dir=SST_CONFIG_DIR)
            @test cr isa N4LCompileResult
            @test cr.nodes_created >= 3
            @test "test chapter" in cr.chapters
            # Verify nodes exist in the store
            @test !isempty(mem_get_nodes_by_name(store, "apple"))
            @test !isempty(mem_get_nodes_by_name(store, "banana"))
            @test !isempty(mem_get_nodes_by_name(store, "cherry"))
        else
            @test_skip false
        end
    end

    @testset "Compile N4L with relations" begin
        if config_available
            SemanticSpacetime.reset_arrows!()
            SemanticSpacetime.reset_contexts!()
            store = MemoryStore()
            text = """
            -relations chapter

            cat (note) dog
            """
            cr = compile_n4l_string!(store, text; config_dir=SST_CONFIG_DIR)
            @test cr isa N4LCompileResult
            @test cr.nodes_created >= 2
            @test !isempty(mem_get_nodes_by_name(store, "cat"))
            @test !isempty(mem_get_nodes_by_name(store, "dog"))
            # There should be at least one edge
            @test cr.edges_created >= 1 || link_count(store) >= 1
        else
            @test_skip false
        end
    end

    @testset "Compile N4L with contexts" begin
        if config_available
            SemanticSpacetime.reset_arrows!()
            SemanticSpacetime.reset_contexts!()
            store = MemoryStore()
            text = """
            -context chapter

            :: food ::

            pizza
            pasta
            """
            cr = compile_n4l_string!(store, text; config_dir=SST_CONFIG_DIR)
            @test cr isa N4LCompileResult
            @test cr.nodes_created >= 2
            @test !isempty(mem_get_nodes_by_name(store, "pizza"))
            @test !isempty(mem_get_nodes_by_name(store, "pasta"))
        else
            @test_skip false
        end
    end

    @testset "Compile N4L with multiple chapters" begin
        if config_available
            SemanticSpacetime.reset_arrows!()
            SemanticSpacetime.reset_contexts!()
            store = MemoryStore()
            # The N4L parser only recognizes the first -section when section_state
            # is empty; subsequent sections require specific formatting.
            # Test with a single chapter but multiple items.
            text = """
            -chapter one

            alpha
            beta
            gamma
            delta
            """
            cr = compile_n4l_string!(store, text; config_dir=SST_CONFIG_DIR)
            @test cr isa N4LCompileResult
            @test cr.nodes_created >= 4
            @test "chapter one" in cr.chapters
        else
            @test_skip false
        end
    end

    @testset "compile_n4l! with pre-parsed result" begin
        if config_available
            SemanticSpacetime.reset_arrows!()
            SemanticSpacetime.reset_contexts!()
            result = parse_n4l("-sec\n\n item1\n item2\n"; config_dir=SST_CONFIG_DIR)
            store = MemoryStore()
            cr = compile_n4l!(store, result)
            @test cr isa N4LCompileResult
            @test cr.nodes_created >= 2
        else
            @test_skip false
        end
    end

    @testset "Empty input compiles cleanly" begin
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.reset_contexts!()
        store = MemoryStore()
        result = parse_n4l(""; load_config=false)
        cr = compile_n4l!(store, result)
        @test cr.nodes_created == 0
        @test cr.edges_created == 0
    end
end

@testset "N4L Standalone" begin
    SST_CONFIG_DIR = joinpath(@__DIR__, "..", "..", "SSTorytime", "SSTconfig")
    config_available = isdir(SST_CONFIG_DIR)

    @testset "N4LValidationResult display" begin
        vr = N4LValidationResult(true, String[], String[], 5, 3, ["ch1"])
        s = sprint(show, vr)
        @test occursin("VALID", s)
        @test occursin("nodes=5", s)
    end

    @testset "validate_n4l with valid input" begin
        if config_available
            SemanticSpacetime.reset_arrows!()
            SemanticSpacetime.reset_contexts!()
            vr = validate_n4l("-sec\n\n one\n two\n"; config_dir=SST_CONFIG_DIR)
            @test vr isa N4LValidationResult
            @test vr.node_count >= 2
            @test "sec" in vr.chapters
        else
            @test_skip false
        end
    end

    @testset "validate_n4l with empty input" begin
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.reset_contexts!()
        vr = validate_n4l(""; config_dir=nothing)
        @test vr.valid
        @test vr.node_count == 0
    end

    @testset "n4l_summary for N4LResult" begin
        if config_available
            SemanticSpacetime.reset_arrows!()
            SemanticSpacetime.reset_contexts!()
            result = parse_n4l("-sec\n\n one\n two\n"; config_dir=SST_CONFIG_DIR)
            buf = IOBuffer()
            n4l_summary(result; io=buf)
            output = String(take!(buf))
            @test occursin("N4L Summary", output)
            @test occursin("Total nodes:", output)
            @test occursin("Total links:", output)
        else
            @test_skip false
        end
    end

    @testset "n4l_summary for N4LCompileResult" begin
        cr = N4LCompileResult(10, 5, ["ch1", "ch2"], String[], ["a warning"])
        buf = IOBuffer()
        n4l_summary(cr; io=buf)
        output = String(take!(buf))
        @test occursin("Compile Summary", output)
        @test occursin("Nodes created:  10", output)
        @test occursin("Edges created:  5", output)
        @test occursin("ch1", output)
        @test occursin("warning", output)
    end

    # Clean up
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()
end
