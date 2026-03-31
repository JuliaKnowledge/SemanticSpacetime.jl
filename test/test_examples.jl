"""
Run the local N4L example corpus through the parser and compiler.
Each file must parse and compile cleanly without relying on a sibling repo.
"""

using Test
using SemanticSpacetime

function find_n4l_files(dir::String)
    files = String[]
    for (root, _, fnames) in walkdir(dir)
        for f in fnames
            endswith(f, ".n4l") && push!(files, joinpath(root, f))
        end
    end
    sort!(files)
    return files
end

@testset "Local example files" begin
    @test isdir(TEST_SST_CONFIG_DIR)
    @test isdir(TEST_SST_EXAMPLES_DIR)

    n4l_files = find_n4l_files(TEST_SST_EXAMPLES_DIR)
    @test length(n4l_files) >= 4

    n_pass = Ref(0)
    n_parse_error = Ref(0)
    n_crash = Ref(0)

    @testset "Parse+compile: $(relpath(f, TEST_SST_EXAMPLES_DIR))" for f in n4l_files
        example_config = let d = joinpath(dirname(f), "SSTconfig")
            isdir(d) ? d : TEST_SST_CONFIG_DIR
        end

        local result
        try
            result = parse_n4l_file(f; config_dir=example_config)
        catch
            n_crash[] += 1
            @test false
            continue
        end

        if has_errors(result)
            n_parse_error[] += 1
            @test false
            continue
        end

        try
            store = MemoryStore()
            cr = compile_n4l!(store, result)
            @test cr.nodes_created >= 0
            @test cr.edges_created >= 0
            n_pass[] += 1
        catch
            n_crash[] += 1
            @test false
        end
    end

    @testset "Summary" begin
        total = length(n4l_files)
        @info "Example tests" passed=n_pass[] parse_errors=n_parse_error[] crashes=n_crash[] total=total
        @test n_pass[] == total
        @test n_parse_error[] == 0
        @test n_crash[] == 0
    end
end
